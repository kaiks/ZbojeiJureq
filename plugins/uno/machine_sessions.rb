# frozen_string_literal: true

require 'securerandom'
require_relative 'machine_protocol'

module UnoMachine
  Result = Data.define(:success, :code, :game_id) do
    def success?
      success
    end
  end

  # IRC nickname normalization for authorization and routing. This follows the
  # RFC1459 equivalences used by conventional IRC servers.
  module Nick
    module_function

    def normalize(nick)
      nick.to_s.downcase.tr('[]\\^', '{}|~')
    end
  end

  class Allowlist
    def self.from(config: {}, env: ENV)
      raw = if env.key?('UNO_MACHINE_ALLOWLIST')
              env.fetch('UNO_MACHINE_ALLOWLIST')
            else
              config.fetch('uno_machine_allowlist', [])
            end
      new(raw)
    end

    def initialize(nicks)
      values = nicks.is_a?(String) ? nicks.split(',') : Array(nicks)
      @nicks = values.map { |nick| Nick.normalize(nick.to_s.strip) }.reject(&:empty?).uniq.freeze
    end

    def include?(nick)
      @nicks.include?(Nick.normalize(nick))
    end
  end

  Registration = Struct.new(:nick, :player, keyword_init: true)
  Decision = Struct.new(:id, :reason, :player, :status, :deferred, keyword_init: true)
  Session = Struct.new(
    :game_id, :channel, :game, :registration, :pending, :decisions, :applying,
    keyword_init: true
  )

  # Owns machine registration and one-decision-at-a-time application. Its mutex
  # is always acquired after the game monitor and is never held during delivery.
  class Sessions
    MAX_DECISION_HISTORY = 64

    def initialize(transport:, allowlist:, serializer: Jedna::GameStateSerializer.new,
                   executor_factory: ->(game) { Jedna::ActionExecutor.new(game) }, random: nil)
      @transport = transport
      @allowlist = allowlist
      @serializer = serializer
      @executor_factory = executor_factory
      @random = random || -> { SecureRandom.urlsafe_base64(9, padding: false) }
      @mutex = Mutex.new
      @by_id = {}
      @by_game = {}.compare_by_identity
      @game_sequence = 0
      @decision_sequence = 0
    end

    def attach_game(channel:, game:)
      @mutex.synchronize do
        @game_sequence += 1
        game_id = "g#{@game_sequence.to_s(36)}_#{@random.call}"
        session = Session.new(
          game_id: game_id,
          channel: channel,
          game: game,
          registration: nil,
          pending: nil,
          decisions: {},
          applying: nil
        )
        @by_id[game_id] = session
        @by_game[game] = session
        game_id
      end
    end

    def game_id_for(game)
      @mutex.synchronize { @by_game[game]&.game_id }
    end

    def channel_for_game(game_id)
      @mutex.synchronize { @by_id[game_id]&.channel }
    end

    def register(channel:, game:, nick:)
      return Result.new(success: false, code: 'not_allowlisted', game_id: nil) unless @allowlist.include?(nick)

      player = game.synchronize do
        game.players.find { |candidate| Nick.normalize(candidate.to_s) == Nick.normalize(nick) }
      end
      return Result.new(success: false, code: 'not_player', game_id: nil) unless player

      session = @mutex.synchronize do
        candidate = @by_game[game]
        next unless candidate && candidate.channel == channel
        existing = candidate.registration
        if existing && !existing.player.equal?(player)
          next :registration_taken
        end

        candidate.registration = Registration.new(nick: Nick.normalize(nick), player: player)
        candidate
      end
      if session == :registration_taken
        return Result.new(success: false, code: 'registration_taken', game_id: nil)
      end
      return Result.new(success: false, code: 'game_changed', game_id: nil) unless session

      deliver(nick, Protocol.registered_line(game_id: session.game_id, channel: channel))
      game.synchronize do
        action_required(game, player, :registration_sync) if game.started? && game.players.first.equal?(player)
      end
      Result.new(success: true, code: 'ok', game_id: session.game_id)
    end

    def unregister(channel:, game:, nick:, event: 'unregistered')
      delivery = @mutex.synchronize do
        session = @by_game[game]
        registration = session&.registration
        next unless session && session.channel == channel && registration&.nick == Nick.normalize(nick)

        decision_id = session.pending&.id
        clear_registration(session)
        terminal_delivery(session, registration, event, {}, decision_id: decision_id)
      end
      deliver(*delivery) if delivery
      !!delivery
    end

    # Called inline by Jedna while the game's monitor is owned.
    def action_required(game, player, reason)
      request = @serializer.serialize_for_current_player(game)
      return unless request

      delivery = @mutex.synchronize do
        session = @by_game[game]
        next unless session

        replace_pending_decision(session)
        registration = session&.registration
        next unless registration && registration.player.equal?(player)

        @decision_sequence += 1
        decision = Decision.new(
          id: "d#{@decision_sequence.to_s(36)}_#{@random.call}",
          reason: reason,
          player: player,
          status: :pending,
          deferred: []
        )
        session.pending = decision
        session.decisions[decision.id] = decision
        trim_history(session)
        lines = Protocol.state_lines(
          game_id: session.game_id,
          decision_id: decision.id,
          reason: reason,
          request: request
        )
        item = [player.to_s, lines]
        if session.applying
          session.applying.deferred << item
          nil
        else
          item
        end
      end
      deliver(*delivery) if delivery
    end

    def submit(sender:, game_id:, decision_id:, action:)
      session = @mutex.synchronize { @by_id[game_id] }
      return error(sender, 'unknown_game', game_id, decision_id) unless session

      outcome = nil
      deferred = []
      registered_nick = sender
      session.game.synchronize do
        claim = @mutex.synchronize { claim_decision(session, sender, decision_id) }
        unless claim.is_a?(Decision)
          outcome = [:error, claim, false]
          next
        end

        decision = claim
        registered_nick = decision.player.to_s
        begin
          result = @executor_factory.call(session.game).execute(action, player: decision.player)
          @mutex.synchronize do
            if result.success?
              decision.status = :consumed
              session.pending = nil if session.pending.equal?(decision)
              outcome = [:ack, result.action, false]
            else
              decision.status = :pending
              session.pending = decision if @by_id[game_id].equal?(session)
              outcome = [:error, result.code, true]
            end
            session.applying = nil if session.applying.equal?(decision)
            deferred = decision.deferred.dup
          end
        rescue StandardError
          @mutex.synchronize do
            decision.status = :failed
            session.pending = nil if session.pending.equal?(decision)
            session.applying = nil if session.applying.equal?(decision)
            deferred = decision.deferred.dup
          end
          outcome = [:error, 'internal_error', false]
        end
      end

      if outcome.first == :ack
        deliver(registered_nick, Protocol.ack_line(game_id: game_id, decision_id: decision_id, action: outcome[1]))
      else
        error(sender, outcome[1], game_id, decision_id, retryable: outcome[2])
      end
      deferred.each { |delivery| deliver(*delivery) }
      outcome.first == :ack
    end

    def finish_game(game, winner:)
      engine_payload = @serializer.serialize_game_end(game, winner)
      finish_session(game, event: 'game_ended', payload: engine_payload)
    end

    def cancel_game(game, event:, payload: {})
      finish_session(game, event: event, payload: payload)
    end

    def cleanup_nick(nick, event:, channel: nil, delivery_nick: nil)
      normalized = Nick.normalize(nick)
      deliveries = @mutex.synchronize do
        @by_id.values.filter_map do |session|
          registration = session.registration
          next unless registration&.nick == normalized
          next if channel && session.channel != channel

          decision_id = session.pending&.id
          clear_registration(session)
          terminal_delivery(
            session, registration, event, {}, decision_id: decision_id, delivery_nick: delivery_nick
          )
        end
      end
      deliveries.each { |delivery| deliver(*delivery) }
      deliveries.length
    end

    def cleanup_all(event:)
      deliveries = @mutex.synchronize do
        @by_id.values.filter_map do |session|
          registration = session.registration
          next unless registration

          decision_id = session.pending&.id
          clear_registration(session)
          terminal_delivery(session, registration, event, {}, decision_id: decision_id)
        end
      end
      deliveries.each { |delivery| deliver(*delivery) }
      deliveries.length
    end

    def shutdown(event: 'plugin_unloaded')
      deliveries = @mutex.synchronize do
        @by_id.values.filter_map do |session|
          registration = session.registration
          next unless registration

          decision_id = session.pending&.id
          clear_registration(session)
          terminal_delivery(session, registration, event, {}, decision_id: decision_id)
        end
      end
      deliveries.each { |delivery| deliver(*delivery) }
      @transport.shutdown
    end

    def protocol_error(nick, code, game_id: '-', decision_id: '-', retryable: false)
      error(nick, code, game_id, decision_id, retryable: retryable)
    end

    private

    def claim_decision(session, sender, decision_id)
      return 'game_ended' unless @by_id[session.game_id].equal?(session)
      registration = session.registration
      return 'unauthorized' unless registration&.nick == Nick.normalize(sender)

      decision = session.decisions[decision_id]
      return 'stale_decision' unless decision
      return 'duplicate_decision' if %i[processing consumed].include?(decision.status)
      return 'stale_decision' unless decision.equal?(session.pending) && decision.status == :pending
      return 'out_of_turn' unless session.game.players.first.equal?(registration.player)

      decision.status = :processing
      session.applying = decision
      decision
    end

    def finish_session(game, event:, payload:)
      delivery = @mutex.synchronize do
        session = @by_game.delete(game)
        next unless session

        @by_id.delete(session.game_id)
        registration = session.registration
        decision_id = session.pending&.id
        replace_pending_decision(session)
        session.registration = nil
        next unless registration

        terminal_delivery(session, registration, event, payload, decision_id: decision_id)
      end
      deliver(*delivery) if delivery
    end

    def terminal_delivery(session, registration, event, payload, decision_id: nil, delivery_nick: nil)
      lines = Protocol.event_lines(
        game_id: session.game_id,
        decision_id: decision_id,
        event: event,
        payload: payload
      )
      item = [delivery_nick || registration.player.to_s, lines]
      if session.applying
        session.applying.deferred << item
        nil
      else
        item
      end
    end

    def replace_pending_decision(session)
      session.pending.status = :stale if session.pending && session.pending.status == :pending
      session.pending = nil
    end

    def clear_registration(session)
      replace_pending_decision(session)
      session.registration = nil
    end

    def trim_history(session)
      overflow = session.decisions.length - MAX_DECISION_HISTORY
      return unless overflow.positive?

      removable = session.decisions.values.reject { |decision| decision.equal?(session.pending) }.first(overflow)
      removable.each { |decision| session.decisions.delete(decision.id) }
    end

    def error(nick, code, game_id, decision_id, retryable: false)
      deliver(
        nick,
        Protocol.error_line(
          code: code,
          game_id: game_id,
          decision_id: decision_id,
          retryable: retryable
        )
      )
      false
    end

    def deliver(nick, lines)
      @transport.deliver(nick, lines)
    end
  end
end

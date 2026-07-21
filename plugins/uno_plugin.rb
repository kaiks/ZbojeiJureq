require 'monitor'
require 'jedna'
require 'jedna/interfaces/irc_notifier'
require './plugins/uno/uno_db.rb'
require './plugins/uno/game_rules'
require './plugins/uno/machine_dispatcher'
require './plugins/uno/machine_sessions'
require './config.rb'

# IRC-specific UnoGame implementation with thread safety
class IrcUnoGame < Jedna::Game
  include ThreadSafeGame

  attr_reader :channel
  
  def initialize(creator, casual = 0, irc = nil, channel = '#kx', plugin = nil,
                 two_player_reverse_acts_as_skip: false)
    @channel = channel
    @ranked = casual != 1
    notifier = Jedna::IrcNotifier.new(irc, channel) if irc
    renderer = Jedna::IrcRenderer.new
    repository = if casual == 1
                   Jedna::NullRepository.new
                 else
                   Jedna::SqliteRepository.new(
                     game_model: UnoGameModel,
                     turn_model: UnoTurnModel,
                     action_model: UnoActionModel,
                     rank_model: UnoRankModel
                   )
                 end
    super(
      creator,
      casual,
      notifier,
      renderer,
      repository,
      two_player_reverse_acts_as_skip: two_player_reverse_acts_as_skip
    )
    
    # Set up the hook for game ended
    on_game_ended do
      plugin.game_ended(channel, self, upload: ranked?) if plugin
    end
    on_action_required do |game, player, reason|
      plugin.machine_action_required(game, player, reason) if plugin
    end
  end

  def ranked?
    @ranked
  end
end

class UnoGameHistory
  attr_accessor :stack
  attr_accessor :players
  attr_accessor :first_player

  def initialize(stack, first_player)
    @stack = stack
    @first_player = first_player
  end
end


class UnoPlugin
  include Cinch::Plugin

  self.prefix = '.'

  match /^ca$/,         group: :uno, method: :ca, use_prefix: false
  match /^cd$/,         group: :uno, method: :cd, use_prefix: false

  match /deal/,       group: :uno, method: :deal

  match /^jo$/,         group: :uno, method: :join, use_prefix: false

  match /^od$/,         group: :uno, method: :order, use_prefix: false
  match /^us$/,         group: :uno, method: :status, use_prefix: false

  match /^pa$/,         group: :uno, method: :pass, use_prefix: false
  match /^pe$/,         group: :uno, method: :pick, use_prefix: false
  match /^st$/,         group: :uno, method: :get_stack_size, use_prefix: false
  match /^pl ([A-Za-z0-9+]{1,10})$/, group: :uno, method: :play, use_prefix: false


  match /^tu$/,           group: :uno, method: :cd, use_prefix: false

  match /uno quit$/,     group: :uno, method: :stop
  match /uno test$/,     group: :uno, method: :testing

  match /uno casual/,   group: :uno, method: :start_casual
  match /uno reload/,   group: :uno, method: :reload
  match /uno stop/,     group: :uno, method: :stop
  match /uno top(?: ([1-5]))?$/, group: :uno, method: :top
  match /uno debug (.*)/,    group: :uno, method: :debug
  match /uno score$/,   group: :uno, method: :own_score
  match /uno score ([A-Za-z0-9_\-]+)/, group: :uno, method: :score
  match /uno status$/,  group: :uno, method: :status
  match /uno machine register$/, group: :uno, method: :machine_register
  match /uno machine unregister$/, group: :uno, method: :machine_unregister
  match /^UNO_MACHINE_V1 ACTION(?: .*)?$/, group: :uno_machine, method: :machine_action, use_prefix: false

  match /uno$/,         group: :uno, method: :start
  match /uno/,          group: :uno, method: :help

  listen_to :nick, method: :machine_nick_changed
  listen_to :part, method: :machine_parted
  listen_to :quit, method: :machine_quit
  listen_to :kick, method: :machine_kicked
  listen_to :disconnect, method: :machine_disconnected

  def initialize(*args)
    super
    @games = {}
    @game_histories = {}
    @testing_channels = Hash.new(false)
    @games_monitor = Monitor.new
    @channel_monitors = {}
    @machine_sessions = build_machine_sessions
  end

  def unregister
    @machine_sessions&.shutdown
    super
  end

  def debug(m, text)
    return unless m.user.has_admin_access?
    m.reply eval(text)
  end

  def testing(m)
    with_channel(m) do |channel|
      channel_lifecycle_monitor(channel).synchronize do
        enabled = @games_monitor.synchronize do
          @testing_channels[channel] = !@testing_channels[channel]
        end
        m.reply "Ok. Now set to #{enabled}"
      end
    end
  end

  def ca(m)
    with_game(m) do |game|
      current_player = game.players.find { |p| p.matches?(m.user.nick) }
      game.show_player_cards(current_player) if current_player
      game.show_card_count if game.game_state > 0
    end
  end

  def cd(m)
    with_game(m) do |game|
      game.notify_top_card if game.players.any? { |p| p.matches?(m.user.nick) }
    end
  end

  def get_stack_size(m)
    with_game(m) do |game|
      m.reply "#{game.card_stack.length} cards left in the stack" if game.started?
    end
  end


  def deal(m)
    with_game(m, notify: true) do |game, channel|
      if game.creator.to_s == m.user.nick
        testing, history = @games_monitor.synchronize do
          enabled = @testing_channels[channel]
          [enabled, enabled ? @game_histories.delete(channel) : nil]
        end
        if testing
          if history.nil?
            game.start_game
            if game.started?
              @games_monitor.synchronize do
                @game_histories[channel] = UnoGameHistory.new(game.starting_stack, game.first_player)
              end
            end
          else
            game.start_game history.stack, history.first_player
          end
        else
          game.start_game
        end
      elsif game.started?
        m.reply 'Cards have already been dealt.'
      else
        m.reply "#{game.creator} needs to deal"
      end
    end
  end

  def join(m)
    with_game(m) do |game|
      join_game(game, m)
    end
  end

  def order(m)
    with_game(m) do |game|
      players_ordered = game.players.map(&:to_s).join(' ')
      game.notify "Current order: #{players_ordered}"
    end
  end

  def pass(m)
    with_game(m) do |game|
      game.turn_pass if current_player?(game, m.user.nick)
    end
  end

  def pick(m)
    with_game(m) do |game|
      game.pick_single if current_player?(game, m.user.nick)
    end
  end

  def is_a_double_card_string? text
    length = text.length
    length > 3 && length.even? &&
      (text[0..(length / 2 - 1)] == text[(length / 2)..length])
  end

  def play(m)
    with_game(m) do |game|
      next unless current_player?(game, m.user.nick)

      player = game.players[0]
      proposed_card_text = m.message.split[1].downcase
      card_text = proposed_card_text
      card = nil
      if is_a_double_card_string?(proposed_card_text)
        card_text = proposed_card_text[0..(proposed_card_text.length / 2 - 1)]
      end

      if card_text.match?(/\Aw[rgby]\z/)
        card = player.hand.reverse.find_card('w')
        card.set_wild_color Jedna.expand_color(card_text[1]) unless card.nil?
      elsif card_text.match?(/\Awd4[rgby]\z/)
        card = player.hand.reverse.find_card('wd4')
        card.set_wild_color Jedna.expand_color(card_text[3]) unless card.nil?
      elsif card_text.match?(/\A[^w]+\z/)
        card = player.hand.reverse.find_card(card_text)
      end
      game.player_card_play(player, card, is_a_double_card_string?(proposed_card_text))
      player.hand.reset_wilds
    end
  end

  def start(m)
    start_game(m, casual: false)
  end

  def start_casual(m)
    start_game(m, casual: true)
  end

  def status(m)
    with_channel(m, error_target: :notice) do |channel|
      result = channel_lifecycle_monitor(channel).synchronize do
        game = @games_monitor.synchronize { @games[channel] }
        if game
          human_status_snapshot(game, m.user.nick) || { error: 'not_player' }
        else
          { error: 'no_game' }
        end
      end

      if result[:error]
        m.user.notice "UNO_STATUS_V1 error=#{result[:error]}"
        next
      end

      m.user.notice result.fetch(:public)
      m.user.notice result.fetch(:private) if result[:private]
    end
  end

  def machine_register(m)
    with_machine_game(m) do |game, channel|
      result = @machine_sessions.register(channel: channel, game: game, nick: m.user.nick)
      @machine_sessions.protocol_error(m.user.nick, result.code) unless result.success?
    end
  end

  def machine_unregister(m)
    with_machine_game(m) do |game, channel|
      removed = @machine_sessions.unregister(channel: channel, game: game, nick: m.user.nick)
      @machine_sessions.protocol_error(m.user.nick, 'not_registered') unless removed
    end
  end

  def machine_action(m)
    game_id, decision_id = machine_outer_ids(m.message)
    if m.channel
      @machine_sessions.protocol_error(
        m.user.nick, 'private_only', game_id: game_id, decision_id: decision_id
      )
      return
    end

    parsed = UnoMachine::Protocol.parse_action(m.message)
    channel = @machine_sessions.channel_for_game(parsed[:game_id])
    if channel
      channel_lifecycle_monitor(channel).synchronize do
        @machine_sessions.submit(sender: m.user.nick, **parsed)
      end
    else
      @machine_sessions.submit(sender: m.user.nick, **parsed)
    end
  rescue UnoMachine::Protocol::ProtocolError => e
    @machine_sessions.protocol_error(
      m.user.nick, e.code, game_id: game_id || '-', decision_id: decision_id || '-'
    )
  end

  # Invoked inline by Jedna under the individual game's monitor.
  def machine_action_required(game, player, reason)
    @machine_sessions&.action_required(game, player, reason)
  end

  def machine_nick_changed(m)
    old_nick = m.user.last_nick
    new_nick = m.user.nick
    games = @games_monitor.synchronize { @games.to_a }

    games.each do |channel, expected_game|
      channel_lifecycle_monitor(channel).synchronize do
        game = @games_monitor.synchronize { @games[channel] }
        next unless game.equal?(expected_game)

        game.synchronize do
          next unless game.players.any? { |player| player.matches?(old_nick) }

          @machine_sessions.cleanup_nick(
            old_nick,
            event: 'nick_changed',
            channel: channel,
            delivery_nick: new_nick
          )
          game.rename_player(old_nick, new_nick)
        end
      end
    end
  end

  def machine_parted(m)
    @machine_sessions.cleanup_nick(
      m.user.nick, event: 'parted', channel: normalize_channel(m.channel.name)
    )
  end

  def machine_quit(m)
    @machine_sessions.cleanup_nick(m.user.nick, event: 'quit')
  end

  def machine_kicked(m)
    kicked_nick = m.params[1]
    @machine_sessions.cleanup_nick(
      kicked_nick, event: 'kicked', channel: normalize_channel(m.channel.name)
    )
  end

  def machine_disconnected(*)
    @machine_sessions.cleanup_all(event: 'disconnected')
  end

  def stop(m)
    with_game(m, notify: true) do |game, channel|
      game.stop_game m.user.nick
      @machine_sessions&.cancel_game(game, event: 'stopped', payload: { stopped_by: m.user.nick })
      @games_monitor.synchronize do
        @games.delete(channel) if @games[channel].equal?(game)
        @game_histories.delete(channel)
      end
      m.reply 'Uno game has been stopped.'
      upload_db if game.ranked?
    end
  end

  def top(m, n = 5)
    counter = 0
    n = n ? n.to_i : 5

    m.reply '   ' + "nick".ljust(20) + 'points  games  average  wins  winrate - full list: http://uno.kaiks.eu '
    #SELECT *, ROUND(CAST(total_score AS FLOAT)/CAST(games AS FLOAT),2) sr FROM uno WHERE nick LIKE ' $+ %safe_nick $+ ' AND games >= 2 ORDER BY %by %ord LIMIT %count
    #UNODB[:uno].where('games > 2').select_append('ROUND(CAST(total_score as FLOAT)/CAST(games AS FLOAT,2)').order(Sequel.desc(5)).limit(n).each { |row|
    UNODB['SELECT *, ROUND(CAST(total_score AS FLOAT)/CAST(games AS FLOAT),2) FROM uno WHERE games >= 10 ORDER BY 5 DESC LIMIT ?', n].each { |row|
      counter += 1
      values = row.values.map { |v| v.is_a?(BigDecimal) ? v.to_s("F") : v.to_s }
      if values[0].to_s.length > 0
        m.reply "#{counter}. #{values[0].ljust(19)} #{values[1].ljust(7)} #{values[2].ljust(6)} #{values[4].ljust(8)} #{values[3].ljust(5)} #{(values[3].to_f*100.0/values[2].to_f).round(2).to_s.ljust(5, "0")}%"
      end
    }
  end

  def game_ended(channel_name, game, upload:)
    channel = normalize_channel(channel_name)
    @machine_sessions&.finish_game(game, winner: game.players.first)
    channel_lifecycle_monitor(channel).synchronize do
      @games_monitor.synchronize do
        @games.delete(channel) if @games[channel].equal?(game)
        @game_histories.delete(channel)
      end
    end
    upload_db if upload
    @bot.send_to_ftp UNODB.opts.fetch(:database), '', 'unodb'
  end

  def help(m)
    m.reply '.uno -> .deal / .uno stop / .uno top / ... uno help available at https://zboje.kaiks.eu/docs/index.html#uno-plugin'
  end

  def winrate(games, wins)
    if games.zero?
      0.0
    else
      (100.to_f * wins / games).round(2)
    end
  end

  def score(m, user)
    rank = UnoRankModel[user]
    unless rank
      m.reply "No uno score found for #{user}."
      return
    end

    games = rank.games.to_i
    wins = rank.wins.to_i
    total_score = rank.total_score.to_i
    average = games.zero? ? 0.0 : (total_score.to_f / games).round(2)

    m.reply "#{rank.nick}: #{average} avg #{total_score} pts #{games} games #{wins} wins #{winrate(games, wins)}% winrate"
  end

  def own_score(m)
    score(m, m.user.nick)
  end

  def reload(m)
    original_verbose = $VERBOSE
    gem_root = Gem.loaded_specs.fetch('jedna').full_gem_path
    source_root = File.join(gem_root, 'lib', 'jedna') + File::SEPARATOR
    loaded_sources = $LOADED_FEATURES.select { |path| path.start_with?(source_root) }

    $VERBOSE = nil
    loaded_sources.each { |path| load path }
    m.reply 'Uno reloaded.'
  ensure
    $VERBOSE = original_verbose
  end

  def upload_db
    #todo: ftp
    database_path = UNODB.opts.fetch(:database)
    @bot.upload_to_dropbox database_path
    @bot.send_to_ftp(database_path)
  end

  private

  def build_machine_sessions
    dispatcher = UnoMachine::Dispatcher.new(error_handler: method(:machine_delivery_error))
    transport = UnoMachine::Transport.new(
      dispatcher: dispatcher,
      notice_target: ->(nick) { @bot.User(nick) }
    )
    UnoMachine::Sessions.new(
      transport: transport,
      allowlist: UnoMachine::Allowlist.from(config: CONFIG)
    )
  end

  def machine_delivery_error(error)
    @bot.loggers.error("[uno machine] delivery failed: #{error.class}: #{error.message}")
  end

  def machine_outer_ids(message)
    match = message.to_s.match(/\AUNO_MACHINE_V1 ACTION game=([^ ]+) decision=([^ ]+)/)
    return ['-', '-'] unless match

    match.captures.map { |token| UnoMachine::Protocol.valid_token?(token) ? token : '-' }
  end

  def with_machine_game(m)
    channel_name = m.channel&.name
    unless channel_name
      @machine_sessions.protocol_error(m.user.nick, 'channel_only')
      return
    end

    channel = normalize_channel(channel_name)
    channel_lifecycle_monitor(channel).synchronize do
      game = @games_monitor.synchronize { @games[channel] }
      unless game
        @machine_sessions.protocol_error(m.user.nick, 'no_game')
        next
      end

      yield game, channel
    end
  end

  def start_game(m, casual:)
    with_channel(m) do |channel|
      channel_lifecycle_monitor(channel).synchronize do
        if @games_monitor.synchronize { @games.key?(channel) }
          m.reply 'An uno game is already being played in this channel.'
          next
        end

        reverse_acts_as_skip = UnoRules.two_player_reverse_acts_as_skip?(config: CONFIG)
        game = IrcUnoGame.new(
          m.user.nick,
          casual ? 1 : 0,
          @bot,
          m.channel.name,
          self,
          two_player_reverse_acts_as_skip: reverse_acts_as_skip
        )
        @machine_sessions&.attach_game(channel: channel, game: game)
        @games_monitor.synchronize { @games[channel] = game }

        casual_text = casual ? 'casual ' : ''
        m.reply "Ok, created #{casual_text}04U09N12O08! game on #{m.channel}, say 'jo' to join in"
        join_game(game, m)
      end
    end
  end

  def join_game(game, m)
    if game.players.none? { |player| player.matches?(m.user.nick) }
      game.add_player Jedna::Player.new(m.user.nick)
    else
      m.reply "You are already in the game, #{m.user.nick}."
    end
  end

  def current_player?(game, nick)
    game.players.first&.matches?(nick)
  end

  def with_channel(m, error_target: :reply)
    channel = m.channel&.name
    unless channel
      message = error_target == :notice ? 'UNO_STATUS_V1 error=channel_only' : 'Uno games can only be played in a channel.'
      error_target == :notice ? m.user.notice(message) : m.reply(message)
      return
    end

    yield normalize_channel(channel)
  end

  def with_game(m, notify: false)
    with_channel(m) do |channel|
      channel_lifecycle_monitor(channel).synchronize do
        game = @games_monitor.synchronize { @games[channel] }
        if game
          yield game, channel
        elsif notify
          m.reply 'No uno game is running in this channel.'
        end
      end
    end
  end

  def channel_lifecycle_monitor(channel)
    @games_monitor.synchronize do
      @channel_monitors ||= {}
      @channel_monitors[channel] ||= Monitor.new
    end
  end

  def normalize_channel(channel)
    channel.to_s.downcase
  end

  def human_status_snapshot(game, requester_nick)
    game.synchronize do
      requester = game.players.find { |player| player.matches?(requester_nick) }
      next unless requester

      started = game.started?
      phase = if started
                'active'
              elsif game.top_card
                'ended'
              else
                'waiting'
              end
      current_player = started ? game.players.first : nil
      fields = {
        phase: phase,
        current: current_player || '-',
        top: game.top_card || '-',
        mode: human_game_mode(game.game_state),
        stacked_cards: game.stacked_cards,
        already_picked: game.already_picked ? 1 : 0,
        players: game.players.map { |player| "#{player}:#{player.hand.size}" }.join(',')
      }
      public_line = "UNO_STATUS_V1 #{fields.map { |key, value| "#{key}=#{value}" }.join(' ')}"
      private_line = if current_player&.matches?(requester_nick)
                       "UNO_STATUS_PRIVATE_V1 picked_card=#{game.picked_card || '-'}"
                     end
      { public: public_line, private: private_line }
    end
  end

  def human_game_mode(game_state)
    {
      0 => 'off',
      1 => 'normal',
      2 => 'war_+2',
      3 => 'war_wd4'
    }.fetch(game_state, 'unknown')
  end
end

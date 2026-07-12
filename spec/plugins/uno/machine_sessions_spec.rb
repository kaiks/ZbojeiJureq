# frozen_string_literal: true

require 'spec_helper'
require 'jedna'
require_relative '../../../plugins/uno/machine_dispatcher'
require_relative '../../../plugins/uno/machine_sessions'

RSpec.describe UnoMachine::Sessions do
  class RecordingMachineTransport
    attr_reader :deliveries

    def initialize
      @deliveries = []
    end

    def deliver(nick, lines)
      @deliveries << [nick, Array(lines)]
      true
    end

    def shutdown(*)
      @shutdown = true
    end

    def shutdown?
      @shutdown
    end
  end

  let(:transport) { RecordingMachineTransport.new }
  let(:allowlist) { UnoMachine::Allowlist.new(%w[ALICE Carol]) }
  let(:random_values) { Enumerator.new { |values| index = 0; loop { values << "secret#{index += 1}" } } }
  let(:sessions) do
    described_class.new(transport: transport, allowlist: allowlist, random: -> { random_values.next })
  end
  let(:game_class) { Class.new(Jedna::Game) { include ThreadSafeGame } }
  let(:game) { game_class.new('creator', 1, Jedna::NullNotifier.new) }
  let(:alice) { Jedna::Player.new('Alice') }
  let(:bob) { Jedna::Player.new('Bob') }

  before do
    game.add_player(alice)
    game.add_player(bob)
    sessions.attach_game(channel: '#one', game: game)
    game.on_action_required { |current_game, player, reason| sessions.action_required(current_game, player, reason) }
  end

  def register_alice
    sessions.register(channel: '#one', game: game, nick: 'alice')
  end

  def latest_state
    nick, lines = transport.deliveries.reverse.find { |_, frame| frame.first.include?(' STATE ') }
    [nick, UnoMachine::Protocol.reassemble(lines)]
  end

  it 'defaults authorization to explicit normalized allowlist membership and a concrete player' do
    denied = UnoMachine::Allowlist.from(config: {}, env: {})
    denied_sessions = described_class.new(transport: transport, allowlist: denied)
    other_game = game_class.new('creator', 1, Jedna::NullNotifier.new)
    other_game.add_player(Jedna::Player.new('Alice'))
    denied_sessions.attach_game(channel: '#one', game: other_game)

    expect(denied_sessions.register(channel: '#one', game: other_game, nick: 'Alice').code)
      .to eq('not_allowlisted')
    expect(sessions.register(channel: '#one', game: game, nick: 'Mallory').code)
      .to eq('not_allowlisted')
    expect(sessions.register(channel: '#one', game: game, nick: 'Carol').code)
      .to eq('not_player')
    expect(sessions.register(channel: '#two', game: game, nick: 'Alice').code)
      .to eq('game_changed')
    expect(register_alice).to be_success
    expect(transport.deliveries.last.first).to eq('alice')
    expect(transport.deliveries.last.last.first).to include(' REGISTERED ')
  end

  it 'sends authoritative state only to the registered current player with monotonic opaque decisions' do
    register_alice
    transport.deliveries.clear
    game.start_game(nil, 'Alice')

    nick, first = latest_state
    expect(nick).to eq('Alice')
    expect(first.dig('request', 'state', 'your_id')).to eq('Alice')
    expect(first.dig('request', 'state', 'hand').length).to eq(7)
    expect(first['reason']).to eq('turn_started')

    first_sequence = first.fetch('decision_id').match(/\Ad([0-9a-z]+)_/)[1].to_i(36)
    action = { action: 'draw' }
    sessions.submit(
      sender: 'ALICE', game_id: first.fetch('game_id'), decision_id: first.fetch('decision_id'), action: action
    )
    _, second = latest_state
    second_sequence = second.fetch('decision_id').match(/\Ad([0-9a-z]+)_/)[1].to_i(36)
    expect(second_sequence).to eq(first_sequence + 1)
    expect(second['reason']).to eq('card_drawn')
    expect(transport.deliveries.map(&:first).uniq).to eq(['Alice'])
  end

  it 'acknowledges a draw before delivering its post-draw decision' do
    register_alice
    game.start_game(nil, 'Alice')
    _, state = latest_state
    transport.deliveries.clear

    expect(sessions.submit(
      sender: 'Alice', game_id: state['game_id'], decision_id: state['decision_id'], action: { action: 'draw' }
    )).to be(true)

    expect(transport.deliveries.map { |_, lines| lines.first.split[1] }).to eq(%w[ACK STATE])
    follow_up = UnoMachine::Protocol.reassemble(transport.deliveries.last.last)
    expect(follow_up.dig('request', 'state')).to include('already_picked' => true)
  end

  it 'keeps a decision retryable after canonical validation failure' do
    register_alice
    game.start_game(nil, 'Alice')
    _, state = latest_state
    transport.deliveries.clear

    expect(sessions.submit(
      sender: 'Alice', game_id: state['game_id'], decision_id: state['decision_id'], action: { action: 'pass' }
    )).to be(false)
    expect(transport.deliveries.last.last.first).to include('code=action_unavailable retry=1')

    expect(sessions.submit(
      sender: 'Alice', game_id: state['game_id'], decision_id: state['decision_id'], action: { action: 'draw' }
    )).to be(true)
  end

  it 'invalidates an old pending decision when a new unregistered-player turn begins' do
    register_alice
    game.start_game(nil, 'Alice')
    _, first = latest_state
    sessions.submit(
      sender: 'Alice', game_id: first['game_id'], decision_id: first['decision_id'], action: { action: 'draw' }
    )
    _, post_draw = latest_state
    game.synchronize do
      game.players.rotate!
      sessions.action_required(game, bob, :turn_started)
    end
    transport.deliveries.clear

    expect(sessions.submit(
      sender: 'Alice',
      game_id: post_draw['game_id'],
      decision_id: post_draw['decision_id'],
      action: { action: 'pass' }
    )).to be(false)
    expect(transport.deliveries.last.last.first).to include('code=stale_decision retry=0')
  end

  it 'emits a fresh authoritative registration sync for a reconnecting current player' do
    register_alice
    game.start_game(nil, 'Alice')
    _, first = latest_state
    transport.deliveries.clear

    expect(register_alice).to be_success
    expect(transport.deliveries.map { |_, lines| lines.first.split[1] }).to eq(%w[REGISTERED STATE])
    _, synced = latest_state
    expect(synced['reason']).to eq('registration_sync')
    expect(synced['decision_id']).not_to eq(first['decision_id'])
  end

  it 'atomically prevents concurrent duplicate execution' do
    register_alice
    game.start_game(nil, 'Alice')
    _, state = latest_state
    original_size = alice.hand.size
    transport.deliveries.clear

    threads = 2.times.map do
      Thread.new do
        sessions.submit(
          sender: 'Alice', game_id: state['game_id'], decision_id: state['decision_id'], action: { action: 'draw' }
        )
      end
    end
    results = threads.map(&:value)

    expect(results.count(true)).to eq(1)
    expect(alice.hand.size).to eq(original_size + 1)
    frames = transport.deliveries.map { |_, lines| lines.first }
    expect(frames.count { |line| line.include?(' ACK ') }).to eq(1)
    expect(frames.count { |line| line.include?(' ERROR ') }).to eq(1)
  end

  it 'rejects unauthorized, stale, and out-of-turn actions without disclosing state' do
    register_alice
    game.start_game(nil, 'Alice')
    _, state = latest_state
    transport.deliveries.clear

    sessions.submit(
      sender: 'Mallory', game_id: state['game_id'], decision_id: state['decision_id'], action: { action: 'draw' }
    )
    expect(transport.deliveries.last.first).to eq('Mallory')
    expect(transport.deliveries.last.last.first).to include('code=unauthorized retry=0')

    game.players.rotate!
    sessions.submit(
      sender: 'Alice', game_id: state['game_id'], decision_id: state['decision_id'], action: { action: 'draw' }
    )
    expect(transport.deliveries.last.last.first).to include('code=out_of_turn retry=0')
    expect(transport.deliveries.flatten.join).not_to include('"hand"')
  end

  it 'cleans registration and invalidates decisions on unregister and terminal lifecycle' do
    register_alice
    game.start_game(nil, 'Alice')
    _, state = latest_state
    transport.deliveries.clear

    expect(sessions.unregister(channel: '#one', game: game, nick: 'ALICE')).to be(true)
    event = UnoMachine::Protocol.reassemble(transport.deliveries.last.last)
    expect(event['event']).to eq('unregistered')
    expect(event['decision_id']).to eq(state['decision_id'])

    sessions.submit(
      sender: 'Alice', game_id: state['game_id'], decision_id: state['decision_id'], action: { action: 'draw' }
    )
    expect(transport.deliveries.last.last.first).to include('code=unauthorized')

    register_alice
    sessions.cancel_game(game, event: 'stopped')
    expect(UnoMachine::Protocol.reassemble(transport.deliveries.last.last)['event']).to eq('stopped')
    expect(sessions.submit(
      sender: 'Alice', game_id: state['game_id'], decision_id: state['decision_id'], action: { action: 'draw' }
    )).to be(false)
    expect(transport.deliveries.last.last.first).to include('code=unknown_game')
  end

  it 'does not let a second player take over an existing registration' do
    register_alice

    expect(sessions.register(channel: '#one', game: game, nick: 'Carol').code).to eq('not_player')

    carol = Jedna::Player.new('Carol')
    game.add_player(carol)
    expect(sessions.register(channel: '#one', game: game, nick: 'Carol').code).to eq('registration_taken')
  end

  it 'applies an unrestricted double wild draw four through the canonical executor' do
    alice.hand << [
      Jedna::Card.new(:wild, 'wild+4'),
      Jedna::Card.new(:wild, 'wild+4'),
      Jedna::Card.new(:blue, 1)
    ]
    bob.hand << Jedna::Card.new(:yellow, 2)
    game.players.replace([alice, bob])
    game.instance_variable_set(:@played_cards, Jedna::CardStack.new)
    game.instance_variable_set(:@top_card, Jedna::Card.new(:red, 7))
    game.instance_variable_set(:@game_state, 1)
    register_alice
    game.synchronize { sessions.action_required(game, alice, :turn_started) }
    _, state = latest_state

    submitted = sessions.submit(
      sender: 'Alice',
      game_id: state['game_id'],
      decision_id: state['decision_id'],
      action: { action: 'play', card: 'wd4', wild_color: 'red', double_play: true }
    )
    expect(submitted).to be(true), transport.deliveries.last.inspect

    expect(alice.hand.map(&:to_s)).to eq(['b1'])
    expect(game.top_card.to_s).to eq('wd4r')
    expect(game.stacked_cards).to eq(8)
  end

  it 'acknowledges a winning action before its correlated private game-end frame' do
    alice.hand << Jedna::Card.new(:red, 5)
    bob.hand << Jedna::Card.new(:yellow, 2)
    game.players.replace([alice, bob])
    game.instance_variable_set(:@played_cards, Jedna::CardStack.new)
    game.instance_variable_set(:@top_card, Jedna::Card.new(:red, 7))
    game.instance_variable_set(:@game_state, 1)
    game.on_game_ended { sessions.finish_game(game, winner: game.players.first) }
    register_alice
    game.synchronize { sessions.action_required(game, alice, :turn_started) }
    _, state = latest_state
    transport.deliveries.clear

    expect(sessions.submit(
      sender: 'Alice',
      game_id: state['game_id'],
      decision_id: state['decision_id'],
      action: { action: 'play', card: 'r5' }
    )).to be(true)

    expect(transport.deliveries.map { |_, lines| lines.first.split[1] }).to eq(%w[ACK EVENT])
    ended = UnoMachine::Protocol.reassemble(transport.deliveries.last.last)
    expect(ended).to include(
      'event' => 'game_ended',
      'game_id' => state['game_id'],
      'decision_id' => state['decision_id']
    )
    expect(ended.dig('payload', 'winner')).to eq('Alice')
  end

  it 'cleans only the bound registration on nick and channel lifecycle changes' do
    register_alice
    game.start_game(nil, 'Alice')
    transport.deliveries.clear

    expect(sessions.cleanup_nick('ALICE', event: 'nick_changed', delivery_nick: 'Alice2')).to eq(1)
    expect(transport.deliveries.last.first).to eq('Alice2')
    expect(UnoMachine::Protocol.reassemble(transport.deliveries.last.last)['event']).to eq('nick_changed')
    expect(sessions.cleanup_nick('Alice', event: 'parted', channel: '#two')).to eq(0)
  end

  it 'returns from the action hook without network IO and delivers after the game monitor is released' do
    callback = Queue.new
    delivery = Queue.new
    monitored_game = game.instance_variable_get(:@__monitor)
    global_monitor = Monitor.new
    channel_monitor = Monitor.new
    dispatcher = UnoMachine::Dispatcher.new
    async_transport = UnoMachine::Transport.new(
      dispatcher: dispatcher,
      notice_target: lambda do |_nick|
        Object.new.tap do |target|
          target.define_singleton_method(:notice) do |line|
            callback << [
              line.split[1],
              monitored_game.mon_owned?,
              global_monitor.mon_owned?,
              channel_monitor.mon_owned?
            ]
            delivery << true
          end
        end
      end
    )
    async_sessions = described_class.new(transport: async_transport, allowlist: allowlist)
    async_sessions.attach_game(channel: '#one', game: game)
    async_sessions.register(channel: '#one', game: game, nick: 'Alice')
    delivery.pop # registration frame
    game.on_action_required do |current_game, player, reason|
      async_sessions.action_required(current_game, player, reason)
    end

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    channel_monitor.synchronize { game.start_game(nil, 'Alice') }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    delivery.pop
    expect(elapsed).to be < 0.1
    registration_callback = callback.pop
    state_callback = callback.pop
    expect(registration_callback.drop(1)).to eq([false, false, false])
    expect(state_callback).to eq(['STATE', false, false, false])
  ensure
    async_transport&.shutdown
  end
end

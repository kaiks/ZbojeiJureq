require 'spec_helper'
require 'cinch'
require 'sequel'
require_relative '../../extensions/database'
require_relative '../../plugins/uno_plugin'

RSpec.describe IrcUnoGame do
  describe 'persistence integration' do
    it 'constructs ranked games with the application database models' do
      database = Sequel.sqlite
      database.create_table(:games) do
        primary_key :ID
        String :start
        String :created_by
      end
      database.create_table(:turn) { primary_key :ID }
      database.create_table(:player_action) { primary_key :ID }
      database.create_table(:uno) { String :nick, primary_key: true }

      stub_const('UnoGameModel', Class.new(Sequel::Model(database[:games])))
      stub_const('UnoTurnModel', Class.new(Sequel::Model(database[:turn])))
      stub_const('UnoActionModel', Class.new(Sequel::Model(database[:player_action])))
      rank_model = Class.new(Sequel::Model(database[:uno]))
      rank_model.unrestrict_primary_key
      stub_const('UnoRankModel', rank_model)

      game = described_class.new('Alice', 0)

      expect(game.repository).to be_a(Jedna::SqliteRepository)
      expect(database[:games].first).to include(created_by: 'Alice')
    ensure
      database&.disconnect
    end

    it 'keeps casual games out of the application database' do
      game = described_class.new('Alice', 1)

      expect(game.repository).to be_a(Jedna::NullRepository)
    end
  end

  it 'synchronizes the inherited game API' do
    game = described_class.new('Alice', 1)

    expect(game.instance_variable_get(:@__monitor)).to be_a(Monitor)
    expect(game.method(:add_player).owner).not_to eq(Jedna::Game)
  end
end

RSpec.describe UnoPlugin do
  let(:plugin) { described_class.allocate }
  let(:bot) { double('bot') }
  let(:channel) { double('channel', name: '#one', to_s: '#one') }
  let(:user) { double('user', nick: 'Alice') }

  before do
    plugin.instance_variable_set(:@bot, bot)
    plugin.instance_variable_set(:@games, {})
    plugin.instance_variable_set(:@game_histories, {})
    plugin.instance_variable_set(:@testing_channels, Hash.new(false))
    plugin.instance_variable_set(:@games_monitor, Monitor.new)
    plugin.instance_variable_set(:@channel_monitors, {})
  end

  describe '#play' do
    let(:player) { Jedna::Player.new('Alice') }
    let(:game) { instance_double(IrcUnoGame, players: [player]) }
    let(:message) { double('message', user: user, channel: channel, message: 'pl wr') }

    before do
      player.hand << Jedna::Card.new(:wild, 'wild')
      plugin.instance_variable_get(:@games)['#one'] = game
      allow(game).to receive(:player_card_play)
    end

    it 'uses the jedna namespace when selecting a wild color' do
      expect(game).to receive(:player_card_play) do |_player, card, double_play|
        expect(card.color).to eq(:red)
        expect(double_play).to be(false)
      end

      plugin.play(message)
    end

    it 'normalizes uppercase card commands' do
      uppercase_message = double('uppercase message', user: user, channel: channel, message: 'pl WR')
      expect(game).to receive(:player_card_play) do |_player, card, _double_play|
        expect(card.color).to eq(:red)
      end

      plugin.play(uppercase_message)
    end

    it 'plays two wild draw fours with the selected color' do
      2.times { player.hand << Jedna::Card.new(:wild, 'wild+4') }
      double_message = double('double wd4 message', user: user, channel: channel, message: 'pl wd4rwd4r')

      expect(game).to receive(:player_card_play) do |_player, card, double_play|
        expect(card.figure).to eq('wild+4')
        expect(card.color).to eq(:red)
        expect(double_play).to be(true)
      end

      plugin.play(double_message)
    end

    it 'applies double wild draw four syntax through the real game engine' do
      real_game = IrcUnoGame.new('Alice', 1)
      alice = Jedna::Player.new('Alice')
      bob = Jedna::Player.new('Bob')
      alice.hand << [
        Jedna::Card.new(:wild, 'wild+4'),
        Jedna::Card.new(:wild, 'wild+4'),
        Jedna::Card.new(:blue, 1)
      ]
      bob.hand << Jedna::Card.new(:yellow, 2)
      real_game.players.replace([alice, bob])
      real_game.notifier = Jedna::NullNotifier.new
      real_game.instance_variable_set(:@played_cards, Jedna::CardStack.new)
      real_game.instance_variable_set(:@top_card, Jedna::Card.new(:red, 7))
      real_game.instance_variable_set(:@game_state, 1)
      plugin.instance_variable_get(:@games)['#one'] = real_game
      double_message = double('double wd4 message', user: user, channel: channel, message: 'pl wd4rwd4r')

      plugin.play(double_message)

      expect(alice.hand.map(&:to_s)).to eq(['b1'])
      expect(real_game.top_card.to_s).to eq('wd4r')
      expect(real_game.game_state).to eq(3)
      expect(real_game.stacked_cards).to eq(8)
    end
  end

  describe '#status' do
    def game_with_players
      game = IrcUnoGame.new('Alice', 1)
      alice = Jedna::Player.new('Alice')
      bob = Jedna::Player.new('Bob')
      game.players.replace([alice, bob])
      [game, alice, bob]
    end

    def install_game(game)
      plugin.instance_variable_get(:@games)['#one'] = game
    end

    it 'privately reports a deterministic active snapshot and the current player picked card' do
      game, alice, bob = game_with_players
      picked_card = Jedna::Card.new(:red, 5)
      alice.hand << [picked_card, Jedna::Card.new(:blue, 7)]
      bob.hand << Jedna::Card.new(:yellow, 2)
      game.instance_variable_set(:@top_card, Jedna::Card.new(:green, 'wild+4'))
      game.instance_variable_set(:@game_state, 3)
      game.instance_variable_set(:@stacked_cards, 8)
      game.instance_variable_set(:@already_picked, true)
      game.instance_variable_set(:@picked_card, picked_card)
      install_game(game)
      message = double('status message', user: user, channel: channel)
      channel_monitor = plugin.send(:channel_lifecycle_monitor, '#one')

      expect(user).to receive(:notice).with(
        'UNO_STATUS_V1 phase=active current=Alice top=wd4g mode=war_wd4 ' \
        'stacked_cards=8 already_picked=1 players=Alice:2,Bob:1'
      ) do
        expect(plugin.instance_variable_get(:@games_monitor).mon_owned?).to be(false)
        expect(channel_monitor.mon_owned?).to be(false)
      end
      expect(user).to receive(:notice).with('UNO_STATUS_PRIVATE_V1 picked_card=r5') do
        expect(plugin.instance_variable_get(:@games_monitor).mon_owned?).to be(false)
        expect(channel_monitor.mon_owned?).to be(false)
      end

      plugin.status(message)
    end

    it 'never discloses the picked card to another player' do
      game, alice, bob = game_with_players
      picked_card = Jedna::Card.new(:red, 5)
      alice.hand << picked_card
      game.instance_variable_set(:@top_card, Jedna::Card.new(:red, 7))
      game.instance_variable_set(:@game_state, 1)
      game.instance_variable_set(:@already_picked, true)
      game.instance_variable_set(:@picked_card, picked_card)
      install_game(game)
      bob_user = double('Bob', nick: 'Bob')
      message = double('Bob status message', user: bob_user, channel: channel)

      expect(bob_user).to receive(:notice).once.with(
        'UNO_STATUS_V1 phase=active current=Alice top=r7 mode=normal ' \
        'stacked_cards=0 already_picked=1 players=Alice:1,Bob:0'
      )

      plugin.status(message)
    end

    it 'reports a pre-deal game without inventing a current player' do
      game, = game_with_players
      install_game(game)
      message = double('status message', user: user, channel: channel)

      expect(user).to receive(:notice).with(
        'UNO_STATUS_V1 phase=waiting current=- top=- mode=off ' \
        'stacked_cards=0 already_picked=0 players=Alice:0,Bob:0'
      )

      plugin.status(message)
    end

    it 'reports an ended game object explicitly' do
      game, = game_with_players
      game.instance_variable_set(:@top_card, Jedna::Card.new(:red, 7))
      install_game(game)
      message = double('status message', user: user, channel: channel)

      expect(user).to receive(:notice).with(
        'UNO_STATUS_V1 phase=ended current=- top=r7 mode=off ' \
        'stacked_cards=0 already_picked=0 players=Alice:0,Bob:0'
      )

      plugin.status(message)
    end

    it 'returns private errors for a nonplayer, a missing game, and a private-message invocation' do
      game, = game_with_players
      install_game(game)
      stranger = double('stranger', nick: 'Mallory')

      expect(stranger).to receive(:notice).with('UNO_STATUS_V1 error=not_player')
      plugin.status(double('nonplayer status', user: stranger, channel: channel))

      plugin.instance_variable_get(:@games).delete('#one')
      expect(stranger).to receive(:notice).with('UNO_STATUS_V1 error=no_game')
      plugin.status(double('missing status', user: stranger, channel: channel))

      expect(stranger).to receive(:notice).with('UNO_STATUS_V1 error=channel_only')
      plugin.status(double('private status', user: stranger, channel: nil))
    end

    it 'reports no game after a game is stopped' do
      game, = game_with_players
      install_game(game)
      message = double('stop/status message', user: user, channel: channel)
      allow(message).to receive(:reply)

      plugin.stop(message)

      expect(user).to receive(:notice).with('UNO_STATUS_V1 error=no_game')
      plugin.status(message)
    end
  end

  describe '#reload' do
    it 'reloads jedna without redefining application database models' do
      message = double('message')
      database = UNODB
      game_model = UnoGameModel
      expect(message).to receive(:reply).with('Uno reloaded.')

      expect { plugin.reload(message) }.not_to raise_error
      expect(UNODB).to be(database)
      expect(UnoGameModel).to be(game_model)
    end
  end

  describe '#score' do
    it 'reports a missing player without raising' do
      message = double('message')
      allow(UnoRankModel).to receive(:[]).with('Missing').and_return(nil)
      expect(message).to receive(:reply).with('No uno score found for Missing.')

      expect { plugin.score(message, 'Missing') }.not_to raise_error
    end

    it 'formats a stored player score' do
      message = double('message')
      rank = double('rank', nick: 'Alice', total_score: 125, games: 10, wins: 4)
      allow(UnoRankModel).to receive(:[]).with('Alice').and_return(rank)
      expect(message).to receive(:reply).with('Alice: 12.5 avg 125 pts 10 games 4 wins 40.0% winrate')

      plugin.score(message, 'Alice')
    end
  end

  describe 'command registration' do
    it 'routes quit to stop and has one leaderboard matcher' do
      matchers = described_class.matchers
      quit_matcher = matchers.find { |matcher| matcher.pattern.source.include?('uno quit') }
      top_matchers = matchers.select { |matcher| matcher.pattern.source.include?('uno top') }

      expect(quit_matcher.method).to eq(:stop)
      expect(top_matchers.size).to eq(1)
      expect(matchers.map(&:method)).not_to include(:temp)
    end

    it 'registers both human status commands and accepts double wd4 syntax' do
      matchers = described_class.matchers
      status_patterns = matchers.select { |matcher| matcher.method == :status }.map { |matcher| matcher.pattern.source }
      play_matcher = matchers.find { |matcher| matcher.method == :play }

      expect(status_patterns).to contain_exactly('^us$', 'uno status$')
      expect(play_matcher.pattern).to match('pl wd4rwd4r')
    end

    it 'registers channel-bound machine lifecycle commands and private action routing' do
      matchers = described_class.matchers

      expect(matchers.find { |matcher| matcher.method == :machine_register }.pattern.source)
        .to eq('uno machine register$')
      expect(matchers.find { |matcher| matcher.method == :machine_unregister }.pattern.source)
        .to eq('uno machine unregister$')
      expect(matchers.find { |matcher| matcher.method == :machine_action }.pattern)
        .to match('UNO_MACHINE_V1 ACTION game=g1 decision=d1 data=e30')
      expect(described_class.listeners.map(&:event)).to include(:nick, :part, :quit, :kick, :disconnect)
    end
  end


  describe 'machine command boundary' do
    let(:machine_sessions) { instance_double(UnoMachine::Sessions) }

    before do
      plugin.instance_variable_set(:@machine_sessions, machine_sessions)
    end

    it 'passes a valid private action to the machine session manager' do
      line = UnoMachine::Protocol.encode_action(
        game_id: 'g1', decision_id: 'd1', action: { action: 'draw' }
      )
      message = double('private machine action', user: user, channel: nil, message: line)
      allow(machine_sessions).to receive(:channel_for_game).with('g1').and_return('#one')

      expect(machine_sessions).to receive(:submit).with(
        sender: 'Alice', game_id: 'g1', decision_id: 'd1', action: { 'action' => 'draw' }
      ) do
        expect(plugin.send(:channel_lifecycle_monitor, '#one').mon_owned?).to be(true)
      end

      plugin.machine_action(message)
    end

    it 'privately rejects a channel action and a malformed private action' do
      channel_line = UnoMachine::Protocol.encode_action(
        game_id: 'g1', decision_id: 'd1', action: { action: 'draw' }
      )
      expect(machine_sessions).to receive(:protocol_error).with(
        'Alice', 'private_only', game_id: 'g1', decision_id: 'd1'
      )
      plugin.machine_action(double('channel action', user: user, channel: channel, message: channel_line))

      expect(machine_sessions).to receive(:protocol_error).with(
        'Alice', 'malformed_action', game_id: '-', decision_id: '-'
      )
      plugin.machine_action(
        double('bad private action', user: user, channel: nil, message: 'UNO_MACHINE_V1 ACTION broken')
      )
    end

    it 'returns structured private registration errors for private and missing-game requests' do
      expect(machine_sessions).to receive(:protocol_error).with('Alice', 'channel_only')
      plugin.machine_register(double('private registration', user: user, channel: nil))

      expect(machine_sessions).to receive(:protocol_error).with('Alice', 'no_game')
      plugin.machine_register(double('missing registration', user: user, channel: channel))
    end

    it 'does not contradict a logically successful deferred unregister' do
      game = instance_double(IrcUnoGame)
      plugin.instance_variable_get(:@games)['#one'] = game
      message = double('machine unregister', user: user, channel: channel)
      expect(machine_sessions).to receive(:unregister).with(
        channel: '#one', game: game, nick: 'Alice'
      ).and_return(true)
      expect(machine_sessions).not_to receive(:protocol_error)

      plugin.machine_unregister(message)
    end
  end

  describe 'nick changes' do
    def started_game(first_player: 'Alice')
      game = IrcUnoGame.new('Alice', 1)
      alice = Jedna::Player.new('Alice')
      bob = Jedna::Player.new('Bob')
      game.add_player(alice)
      game.add_player(bob)
      game.start_game(nil, first_player)
      [game, alice, bob]
    end

    it 'renames an ordinary player in every active channel and permits continued play' do
      first_game, first_alice, = started_game
      second_game, second_alice, = started_game
      plugin.instance_variable_get(:@games).merge!('#one' => first_game, '#two' => second_game)
      machine_sessions = instance_double(UnoMachine::Sessions)
      plugin.instance_variable_set(:@machine_sessions, machine_sessions)
      changed_user = double('renamed user', last_nick: 'Alice', nick: 'Alice2')
      message = double('nick event', user: changed_user)

      expect(machine_sessions).to receive(:cleanup_nick).with(
        'Alice', event: 'nick_changed', channel: '#one', delivery_nick: 'Alice2'
      ).and_return(0)
      expect(machine_sessions).to receive(:cleanup_nick).with(
        'Alice', event: 'nick_changed', channel: '#two', delivery_nick: 'Alice2'
      ).and_return(0)

      plugin.machine_nick_changed(message)

      expect(first_alice).to be_matches('Alice2')
      expect(first_alice).not_to be_matches('Alice')
      expect(second_alice).to be_matches('Alice2')
      plugin.pick(double('new nick draw', user: changed_user, channel: channel))
      expect(first_game.already_picked).to be(true)
    end

    it 'queues cleanup before a racing new-nick registration and resynchronizes' do
      deliveries = []
      delivery_mutex = Mutex.new
      transport = Object.new
      transport.define_singleton_method(:deliver) do |nick, lines|
        delivery_mutex.synchronize { deliveries << [nick, Array(lines)] }
        true
      end
      transport.define_singleton_method(:deliver_batch) do |batch|
        batch.each { |nick, lines| deliver(nick, lines) }
        true
      end
      transport.define_singleton_method(:shutdown) { true }
      sessions = UnoMachine::Sessions.new(
        transport: transport,
        allowlist: UnoMachine::Allowlist.new(%w[Alice Alice2])
      )
      plugin.instance_variable_set(:@machine_sessions, sessions)
      game, alice, = started_game
      plugin.instance_variable_get(:@games)['#one'] = game
      sessions.attach_game(channel: '#one', game: game)
      game.on_action_required do |current_game, player, reason|
        sessions.action_required(current_game, player, reason)
      end
      expect(sessions.register(channel: '#one', game: game, nick: 'Alice')).to be_success
      deliveries.clear
      rename_entered = Queue.new
      release_rename = Queue.new
      allow(game).to receive(:rename_player).and_wrap_original do |original, old_nick, new_nick|
        rename_entered << true
        release_rename.pop
        original.call(old_nick, new_nick)
      end
      changed_user = double('renamed user', last_nick: 'Alice', nick: 'Alice2')
      nick_message = double('nick event', user: changed_user)
      register_message = double('new nick registration', user: changed_user, channel: channel)

      nick_thread = Thread.new { plugin.machine_nick_changed(nick_message) }
      rename_entered.pop
      register_thread = Thread.new { plugin.machine_register(register_message) }
      expect(register_thread.join(0.05)).to be_nil

      release_rename << true
      nick_thread.value
      register_thread.value

      expect(alice).to be_matches('Alice2')
      types = delivery_mutex.synchronize do
        deliveries.map { |_, lines| lines.first.split[1] }
      end
      expect(types).to eq(%w[EVENT REGISTERED STATE])
      event_delivery = delivery_mutex.synchronize { deliveries.first }
      expect(event_delivery.first).to eq('Alice2')
      expect(UnoMachine::Protocol.reassemble(event_delivery.last)['event']).to eq('nick_changed')
      state_delivery = delivery_mutex.synchronize { deliveries.last }
      expect(UnoMachine::Protocol.reassemble(state_delivery.last)['reason']).to eq('registration_sync')
    ensure
      release_rename << true if release_rename && release_rename.empty?
      nick_thread&.join
      register_thread&.join
    end
  end

  describe 'channel-scoped game state' do
    let(:broadcast) { double('broadcast', send: nil) }
    let(:notice) { double('notice', notice: nil) }

    before do
      allow(bot).to receive(:Channel).and_return(broadcast)
      allow(bot).to receive(:User).and_return(notice)
    end

    it 'runs independent games in different channels' do
      other_channel = double('other channel', name: '#two', to_s: '#two')
      first_message = double('first message', user: user, channel: channel, reply: nil)
      second_message = double('second message', user: user, channel: other_channel, reply: nil)

      plugin.start_casual(first_message)
      plugin.start_casual(second_message)

      games = plugin.instance_variable_get(:@games)
      expect(games.keys).to contain_exactly('#one', '#two')
      expect(games.values).to all(be_a(IrcUnoGame))
    end

    it 'creates only one game when starts race in the same channel' do
      message = double('message', user: user, channel: channel, reply: nil)
      creations = 0
      allow(IrcUnoGame).to receive(:new).and_wrap_original do |original, *args|
        creations += 1
        sleep 0.01
        original.call(*args)
      end

      threads = 2.times.map { Thread.new { plugin.start_casual(message) } }
      threads.each(&:join)

      expect(creations).to eq(1)
      expect(plugin.instance_variable_get(:@games).size).to eq(1)
    end

    it 'finishes a same-channel join before a racing stop removes the game' do
      bob = double('bob', nick: 'Bob')
      join_message = double('join message', user: bob, channel: channel)
      stop_message = double('stop message', user: user, channel: channel, reply: nil)
      lookup_started = Queue.new
      continue_join = Queue.new
      actions = Queue.new
      game = instance_double(IrcUnoGame, ranked?: false)
      allow(game).to receive(:players) do
        lookup_started << true
        continue_join.pop
        []
      end
      allow(game).to receive(:add_player) { actions << :join }
      allow(game).to receive(:stop_game) { actions << :stop }
      plugin.instance_variable_get(:@games)['#one'] = game

      join_thread = Thread.new { plugin.join(join_message) }
      lookup_started.pop
      stop_thread = Thread.new { plugin.stop(stop_message) }

      expect(stop_thread.join(0.05)).to be_nil
      continue_join << true
      join_thread.value
      stop_thread.value

      expect([actions.pop, actions.pop]).to eq(%i[join stop])
      expect(plugin.instance_variable_get(:@games)).not_to have_key('#one')
    ensure
      continue_join << true if continue_join&.empty? && join_thread&.alive?
      join_thread&.join
      stop_thread&.join
    end

    it 'does not serialize commands in different channels' do
      other_channel = double('other channel', name: '#two', to_s: '#two')
      bob = double('bob', nick: 'Bob')
      carol = double('carol', nick: 'Carol')
      first_message = double('first join message', user: bob, channel: channel)
      second_message = double('second join message', user: carol, channel: other_channel)
      first_started = Queue.new
      release_first = Queue.new
      second_finished = Queue.new
      first_game = instance_double(IrcUnoGame)
      second_game = instance_double(IrcUnoGame, players: [])
      allow(first_game).to receive(:players) do
        first_started << true
        release_first.pop
        []
      end
      allow(first_game).to receive(:add_player)
      allow(second_game).to receive(:add_player) { second_finished << true }
      plugin.instance_variable_get(:@games).merge!('#one' => first_game, '#two' => second_game)

      first_thread = Thread.new { plugin.join(first_message) }
      first_started.pop
      second_thread = Thread.new { plugin.join(second_message) }

      expect(second_thread.join(0.5)).to eq(second_thread)
      expect(second_finished.pop).to be(true)
      release_first << true
      first_thread.value
      second_thread.value
    ensure
      release_first << true if release_first&.empty? && first_thread&.alive?
      first_thread&.join
      second_thread&.join
    end

    it 'does not hold the global map monitor while constructing another channel game' do
      other_channel = double('other channel', name: '#two', to_s: '#two')
      bob = double('bob', nick: 'Bob')
      start_message = double('start message', user: user, channel: channel, reply: nil)
      join_message = double('join message', user: bob, channel: other_channel)
      constructor_started = Queue.new
      release_constructor = Queue.new
      second_finished = Queue.new
      first_game = instance_double(IrcUnoGame, players: [])
      second_game = instance_double(IrcUnoGame, players: [])
      allow(first_game).to receive(:add_player)
      allow(second_game).to receive(:add_player) { second_finished << true }
      allow(IrcUnoGame).to receive(:new) do
        expect(plugin.instance_variable_get(:@games_monitor).mon_owned?).to be(false)
        constructor_started << true
        release_constructor.pop
        first_game
      end
      plugin.instance_variable_get(:@games)['#two'] = second_game

      start_thread = Thread.new { plugin.start_casual(start_message) }
      constructor_started.pop
      join_thread = Thread.new { plugin.join(join_message) }

      expect(join_thread.join(0.5)).to eq(join_thread)
      expect(second_finished.pop).to be(true)
      release_constructor << true
      start_thread.value
      join_thread.value
      expect(plugin.instance_variable_get(:@games)['#one']).to equal(first_game)
    ensure
      release_constructor << true if release_constructor&.empty? && start_thread&.alive?
      start_thread&.join
      join_thread&.join
    end

    it 'does not insert a game when construction fails' do
      message = double('start message', user: user, channel: channel)
      allow(IrcUnoGame).to receive(:new).and_raise(Sequel::DatabaseError, 'database unavailable')

      expect { plugin.start(message) }.to raise_error(Sequel::DatabaseError, 'database unavailable')
      expect(plugin.instance_variable_get(:@games)).not_to have_key('#one')
    end

    it 'removes an ended game reentrantly from a same-channel game command' do
      game = IrcUnoGame.new('Alice', 1)
      plugin.instance_variable_get(:@games)['#one'] = game
      channel_monitor = plugin.send(:channel_lifecycle_monitor, '#one')
      allow(bot).to receive(:send_to_ftp)

      channel_monitor.synchronize do
        game.synchronize do
          plugin.game_ended('#one', game, upload: false)
        end
      end

      expect(plugin.instance_variable_get(:@games)).not_to have_key('#one')
    end

    it 'plays a casual game through start, join, deal, and stop' do
      bob = double('bob', nick: 'Bob')
      creator_message = double('creator message', user: user, channel: channel, reply: nil)
      join_message = double('join message', user: bob, channel: channel, reply: nil)

      plugin.start_casual(creator_message)
      plugin.join(join_message)
      plugin.deal(creator_message)

      game = plugin.instance_variable_get(:@games)['#one']
      expect(game).to be_started
      expect(game.players.map(&:to_s)).to contain_exactly('Alice', 'Bob')
      expect(game.players.map { |player| player.hand.size }).to eq([7, 7])

      expect(bot).not_to receive(:upload_to_dropbox)
      plugin.stop(creator_message)
      expect(plugin.instance_variable_get(:@games)).not_to have_key('#one')
    end

    it 'does not dereference missing game state' do
      message = double('message', user: user, channel: channel)

      expect { plugin.join(message) }.not_to raise_error
    end

    it 'explains missing game state for prefixed commands' do
      message = double('message', user: user, channel: channel)
      expect(message).to receive(:reply).with('No uno game is running in this channel.')

      plugin.deal(message)
    end
  end
end

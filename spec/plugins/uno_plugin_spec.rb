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

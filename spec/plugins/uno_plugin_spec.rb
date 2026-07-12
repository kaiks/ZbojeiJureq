require 'spec_helper'
require 'cinch'
require 'sequel'
require_relative '../../extensions/database'
require_relative '../../plugins/uno_plugin'

RSpec.describe IrcUnoGame do
  describe 'persistence integration' do
    it 'constructs ranked games with the application database models' do
      repository = Jedna::NullRepository.new
      expect(Jedna::SqliteRepository).to receive(:new).with(
        game_model: UnoGameModel,
        turn_model: UnoTurnModel,
        action_model: UnoActionModel,
        rank_model: UnoRankModel
      ).and_return(repository)

      game = described_class.new('Alice', 0)

      expect(game.repository).to be(repository)
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
  end

  describe 'channel-scoped game state' do
    let(:broadcast) { double('broadcast', send: nil) }

    before do
      allow(bot).to receive(:Channel).and_return(broadcast)
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

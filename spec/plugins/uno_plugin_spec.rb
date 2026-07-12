require 'spec_helper'
require 'cinch'
require 'sequel'
require_relative '../../extensions/database'
require_relative '../../extensions/thread_safe'
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
end

RSpec.describe UnoPlugin do
  describe '#play' do
    let(:plugin) { described_class.allocate }
    let(:player) { Jedna::Player.new('Alice') }
    let(:game) { instance_double(IrcUnoGame, players: [player]) }
    let(:user) { double('user', nick: 'Alice') }
    let(:message) { double('message', user: user, message: 'pl wr') }

    before do
      player.hand << Jedna::Card.new(:wild, 'wild')
      plugin.instance_variable_set(:@game, game)
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
end

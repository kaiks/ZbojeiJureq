require 'spec_helper'
require_relative '../../../plugins/uno/misc'
require_relative '../../../plugins/uno/uno'
require_relative '../../../plugins/uno/uno_card'
require_relative '../../../plugins/uno/interfaces/repository'

RSpec.describe "Uno::Repository" do
  let(:red_5) { UnoCard.new(:red, 5) }
  let(:creator) { 'TestCreator' }
  let(:start_time) { '2024-01-01 12:00:00' }
  
  describe Uno::NullRepository do
    let(:repository) { Uno::NullRepository.new }
    
    describe '#create_game' do
      it 'returns a mock game ID' do
        game_id = repository.create_game(creator, start_time)
        expect(game_id).to be_a(Integer)
      end
    end
    
    describe '#update_game_ended' do
      it 'accepts game end data without error' do
        expect {
          repository.update_game_ended(1, 'Alice', '2024-01-01 13:00:00', 100, 4, 5)
        }.not_to raise_error
      end
    end
    
    describe '#save_card_action' do
      it 'accepts card action data without error' do
        expect {
          repository.save_card_action(1, red_5, 'Alice', false)
        }.not_to raise_error
      end
    end
    
    describe '#record_player_join' do
      it 'accepts player join data without error' do
        expect {
          repository.record_player_join(1, 'Alice')
        }.not_to raise_error
      end
    end
    
    describe '#record_game_stopped' do
      it 'accepts game stop data without error' do
        expect {
          repository.record_game_stopped(1, 'Alice')
        }.not_to raise_error
      end
    end
    
    describe '#get_player_stats' do
      it 'returns default stats for any player' do
        stats = repository.get_player_stats('Alice')
        expect(stats).to eq({
          nick: 'Alice',
          games: 0,
          wins: 0,
          total_score: 0
        })
      end
    end
    
    describe '#update_player_stats' do
      it 'accepts player stats update without error' do
        expect {
          repository.update_player_stats('Alice', true, 50)
        }.not_to raise_error
      end
    end
  end
  
  # Mock repository for testing game integration
  class MockRepository
    include Uno::Repository
    
    attr_reader :games, :cards, :actions, :players
    
    def initialize
      @games = {}
      @cards = []
      @actions = []
      @players = {}
      @next_id = 1
    end
    
    def create_game(creator, start_time)
      game_id = @next_id
      @next_id += 1
      @games[game_id] = {
        id: game_id,
        creator: creator,
        start_time: start_time,
        end_time: nil,
        winner: nil,
        points: nil,
        players: nil
      }
      game_id
    end
    
    def update_game_ended(game_id, winner, end_time, points, total_players, game_number)
      return unless @games[game_id]
      @games[game_id].merge!({
        winner: winner,
        end_time: end_time,
        points: points,
        players: total_players,
        game_number: game_number
      })
    end
    
    def save_card_action(game_id, card, player, received = false)
      @cards << {
        game_id: game_id,
        card: card.to_s,
        player: player.to_s,
        received: received
      }
    end
    
    def record_player_join(game_id, player)
      @actions << {
        game_id: game_id,
        action: 'join',
        player: player
      }
    end
    
    def record_game_stopped(game_id, player)
      @actions << {
        game_id: game_id,
        action: 'stop',
        player: player
      }
    end
    
    def get_player_stats(player_nick)
      @players[player_nick] || {
        nick: player_nick,
        games: 0,
        wins: 0,
        total_score: 0
      }
    end
    
    def update_player_stats(player_nick, won, points = 0)
      @players[player_nick] ||= {
        nick: player_nick,
        games: 0,
        wins: 0,
        total_score: 0
      }
      
      @players[player_nick][:games] += 1
      if won
        @players[player_nick][:wins] += 1
        @players[player_nick][:total_score] += points
      end
      
      @players[player_nick]
    end
  end
  
  describe MockRepository do
    let(:repository) { MockRepository.new }
    
    it 'tracks game lifecycle' do
      # Create game
      game_id = repository.create_game('TestCreator', '2024-01-01 12:00:00')
      expect(game_id).to be_a(Integer)
      
      # Record players joining
      repository.record_player_join(game_id, 'Alice')
      repository.record_player_join(game_id, 'Bob')
      
      # Save some card actions
      repository.save_card_action(game_id, red_5, 'Alice', false)
      repository.save_card_action(game_id, red_5, 'Bob', true)
      
      # Update player stats
      repository.update_player_stats('Alice', true, 50)
      repository.update_player_stats('Bob', false, 0)
      
      # End game
      repository.update_game_ended(game_id, 'Alice', '2024-01-01 13:00:00', 50, 2, 1)
      
      # Verify tracked data
      expect(repository.games[game_id][:winner]).to eq('Alice')
      expect(repository.games[game_id][:points]).to eq(50)
      
      expect(repository.actions).to include(
        hash_including(action: 'join', player: 'Alice'),
        hash_including(action: 'join', player: 'Bob')
      )
      
      expect(repository.cards.size).to eq(2)
      
      alice_stats = repository.get_player_stats('Alice')
      expect(alice_stats[:wins]).to eq(1)
      expect(alice_stats[:total_score]).to eq(50)
    end
  end
end
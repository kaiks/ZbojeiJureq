require_relative 'uno_spec_helper'

RSpec.describe "UnoGame winning message" do
  let(:alice) { UnoPlayer.new('Alice') }
  let(:bob) { UnoPlayer.new('Bob') }
  
  describe "casual game winning message" do
    let(:game) { TestUnoGame.new('TestCreator', 1) } # casual mode
    
    before do
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
      
      # Set up alice to win
      game.instance_variable_set(:@players, [alice, bob])
      alice.hand = Hand.new
      alice.hand << UnoCard.new(:red, 5)
      
      # Bob has cards for scoring
      bob.hand = Hand.new
      bob.hand << [
        UnoCard.new(:blue, 9),      # 9 points
        UnoCard.new(:green, 'skip'), # 20 points  
        UnoCard.new(:yellow, 8),     # 8 points
        UnoCard.new(:red, '+2'),     # 20 points
        UnoCard.new(:blue, 6)        # 6 points
      ] # Total: 63 points
      
      game.instance_variable_set(:@top_card, UnoCard.new(:red, 3))
    end
    
    it "displays points correctly without database stats" do
      game.player_card_play(alice, alice.hand[0])
      
      # Find the winning message
      winning_message = game.notifications.find { |n| n.include?("gains") && n.include?("points") }
      expect(winning_message).to eq("Alice gains 63 points.")
    end
  end
  
  describe "regular game winning message with database stats" do
    let(:mock_repository) { double("Repository") }
    let(:test_notifier) { TestNotifier.new }
    let(:game) { UnoGame.new('TestCreator', 0, test_notifier, nil, mock_repository) }
    
    before do
      # Mock repository methods
      allow(mock_repository).to receive(:create_game).and_return(123)
      allow(mock_repository).to receive(:save_card_action)
      allow(mock_repository).to receive(:record_player_join)
      allow(mock_repository).to receive(:update_player_stats)
      allow(mock_repository).to receive(:update_game_ended)
      
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
      
      # Set up alice to win
      game.instance_variable_set(:@players, [alice, bob])
      alice.hand = Hand.new
      alice.hand << UnoCard.new(:red, 5)
      
      # Bob has cards for scoring
      bob.hand = Hand.new
      bob.hand << [
        UnoCard.new(:blue, 9),      # 9 points
        UnoCard.new(:green, 'skip'), # 20 points  
        UnoCard.new(:yellow, 8),     # 8 points
        UnoCard.new(:red, '+2'),     # 20 points
        UnoCard.new(:blue, 6)        # 6 points
      ] # Total: 63 points
      
      game.instance_variable_set(:@top_card, UnoCard.new(:red, 3))
    end
    
    it "formats BigDecimal values correctly" do
      # Mock get_player_stats to return BigDecimal values
      require 'bigdecimal'
      allow(mock_repository).to receive(:get_player_stats).with('Alice').and_return({
        nick: 'Alice',
        games: BigDecimal('1'),
        wins: BigDecimal('1'),
        total_score: BigDecimal('63')
      })
      
      game.player_card_play(alice, alice.hand[0])
      
      # Find the winning message
      winning_message = test_notifier.game_notifications.find { |n| n.include?("gains") && n.include?("points") }
      expect(winning_message).to eq("Alice gains 63 points. For a total of 63, and a total of 1 games played.")
    end
    
    it "handles large numbers correctly" do
      # Mock get_player_stats to return large BigDecimal values
      require 'bigdecimal'
      allow(mock_repository).to receive(:get_player_stats).with('Alice').and_return({
        nick: 'Alice',
        games: BigDecimal('150'),
        wins: BigDecimal('75'),
        total_score: BigDecimal('12345')
      })
      
      game.player_card_play(alice, alice.hand[0])
      
      # Find the winning message
      winning_message = test_notifier.game_notifications.find { |n| n.include?("gains") && n.include?("points") }
      expect(winning_message).to eq("Alice gains 63 points. For a total of 12345, and a total of 150 games played.")
    end
  end
end
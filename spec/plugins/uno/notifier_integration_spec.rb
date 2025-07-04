require 'spec_helper'
require 'jedna'

RSpec.describe "Notifier integration" do
  describe "UnoGame with NullNotifier" do
    let(:notifier) { Jedna::NullNotifier.new }
    let(:game) { Jedna::Game.new('TestCreator', 1, notifier, nil, Jedna::NullRepository.new) }
    let(:alice) { Jedna::Player.new('Alice') }
    let(:bob) { Jedna::Player.new('Bob') }
    
    it "captures game notifications" do
      game.add_player(alice)
      expect(notifier.game_notifications).to include("Alice joins the game")
    end
    
    it "captures player notifications" do
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
      
      # Find player notifications
      player_msgs = notifier.player_notifications
      expect(player_msgs).not_to be_empty
      expect(player_msgs.first[:player_id]).to match(/Alice|Bob/)
      # Check for card display in rendered format
      expect(player_msgs.first[:message]).to match(/\w+\d+|\[\w+\]/)  # Card display
    end
    
    it "handles game flow with notifier" do
      game.add_player(alice)
      game.add_player(bob)
      
      expect(notifier.game_notifications.size).to eq(2)
      
      game.start_game
      
      # Should have notifications about game start - check for actual game start message format
      start_notification = notifier.game_notifications.find { |n| n.include?("turn") && n.include?("Top card:") }
      expect(start_notification).not_to be_nil
    end
  end
  
  describe "UnoGame with different notifiers" do
    it "can be created with console notifier" do
      game = Jedna::Game.new('TestCreator', 1, Jedna::ConsoleNotifier.new)
      expect(game).to be_a(Jedna::Game)
      expect(game.notifier).to be_a(Jedna::ConsoleNotifier)
    end
  end
end
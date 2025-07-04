require 'spec_helper'
require_relative '../../../extensions/thread_safe'
require_relative '../../../plugins/uno/misc'
require_relative '../../../plugins/uno/uno'
require_relative '../../../plugins/uno/uno_card'
require_relative '../../../plugins/uno/uno_hand'
require_relative '../../../plugins/uno/uno_card_stack'
require_relative '../../../plugins/uno/uno_player'
require_relative '../../../plugins/uno/uno_game'

RSpec.describe "Notifier integration" do
  describe "UnoGame with NullNotifier" do
    let(:notifier) { Uno::NullNotifier.new }
    let(:game) { UnoGame.new('TestCreator', 1, notifier, nil, Uno::NullRepository.new) }
    let(:alice) { UnoPlayer.new('Alice') }
    let(:bob) { UnoPlayer.new('Bob') }
    
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
      game = UnoGame.new('TestCreator', 1, Uno::ConsoleNotifier.new)
      expect(game).to be_a(UnoGame)
      expect(game.notifier).to be_a(Uno::ConsoleNotifier)
    end
  end
end
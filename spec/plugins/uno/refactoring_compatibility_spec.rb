require 'spec_helper'
require_relative '../../../extensions/thread_safe'
require_relative '../../../plugins/uno/misc'
require_relative '../../../plugins/uno/uno'
require_relative '../../../plugins/uno/uno_card'
require_relative '../../../plugins/uno/uno_hand'
require_relative '../../../plugins/uno/uno_card_stack'
require_relative '../../../plugins/uno/interfaces/player_identity'
require_relative '../../../plugins/uno/uno_player'
require_relative '../../../plugins/uno/interfaces/notifier'
require_relative '../../../plugins/uno/interfaces/renderer'
require_relative '../../../plugins/uno/interfaces/repository'
require_relative '../../../plugins/uno/uno_game'

RSpec.describe "Refactoring Compatibility" do
  describe "IrcUnoGame with all interfaces" do
    let(:game) { IrcUnoGame.new('TestCreator', 1) }  # Casual mode
    
    it "initializes with all correct interfaces" do
      expect(game.notifier).to be_a(Uno::ConsoleNotifier)  # Falls back when no IRC
      expect(game.renderer).to be_a(Uno::IrcRenderer)
      expect(game.repository).to be_a(Uno::NullRepository)  # Casual mode
    end
    
    it "creates players with backward compatible identity" do
      player1 = UnoPlayer.new('Alice')
      player2 = UnoPlayer.new('Bob')
      
      game.add_player(player1)
      game.add_player(player2)
      
      expect(game.players.size).to eq(2)
      expect(game.players[0].nick).to match(/Alice|Bob/)
      expect(game.players[1].nick).to match(/Alice|Bob/)
    end
    
    it "handles player matching correctly" do
      alice = UnoPlayer.new('Alice')
      bob = UnoPlayer.new('Bob')
      
      game.add_player(alice)
      game.add_player(bob)
      
      # Find players by nick
      alice_player = game.players.find { |p| p.matches?('Alice') }
      bob_player = game.players.find { |p| p.matches?('Bob') }
      
      expect(alice_player).not_to be_nil
      expect(bob_player).not_to be_nil
      expect(alice_player.nick).to eq('Alice')
      expect(bob_player.nick).to eq('Bob')
    end
    
    it "starts and plays game with all interfaces" do
      alice = UnoPlayer.new('Alice')
      bob = UnoPlayer.new('Bob')
      
      game.add_player(alice)
      game.add_player(bob)
      
      # Start game
      game.start_game
      
      expect(game.started?).to be true
      expect(game.players.all? { |p| p.hand.size == 7 }).to be true
      
      # Verify notifier captured messages
      if game.notifier.is_a?(Uno::NullNotifier)
        expect(game.notifier.game_notifications).to include(match(/Alice joins the game|Bob joins the game/))
      end
    end
  end
  
  describe "Player identity backward compatibility" do
    it "maintains equality comparison" do
      player1_old = UnoPlayer.new('Alice')  # String-based
      player2_old = UnoPlayer.new('Alice')  # String-based
      player3_new = UnoPlayer.new(Uno::IrcIdentity.new('Alice'))  # Identity-based
      
      # Old-style comparison still works
      expect(player1_old == player2_old).to be true
      
      # Mixed comparison works
      expect(player1_old.matches?('Alice')).to be true
      expect(player3_new.matches?('Alice')).to be true
    end
    
    it "supports nick changes" do
      player = UnoPlayer.new('Alice')
      player.change_nick('Alice2')
      
      expect(player.nick).to eq('Alice2')
      expect(player.matches?('Alice2')).to be true
      expect(player.matches?('Alice')).to be false
    end
  end
  
  describe "Renderer integration" do
    let(:game) { IrcUnoGame.new('TestCreator', 1) }
    let(:renderer) { game.renderer }
    
    it "renders cards correctly" do
      card = UnoCard.new(:red, 5)
      rendered = renderer.render_card(card)
      
      expect(rendered).to include('[5]')
      expect(rendered).to include("\x03")  # IRC color code
    end
    
    it "renders hands correctly" do
      hand = Hand.new([
        UnoCard.new(:red, 5),
        UnoCard.new(:blue, 'skip'),
        UnoCard.new(:wild, 'wild')
      ])
      
      rendered = renderer.render_hand(hand)
      expect(rendered).to include('[5]')
      expect(rendered).to include('[S]')
      expect(rendered).to include('[W]')
    end
  end
  
  describe "Repository integration" do
    it "handles casual games with NullRepository" do
      game = IrcUnoGame.new('TestCreator', 1)  # Casual
      expect(game.repository).to be_a(Uno::NullRepository)
      
      # Should not raise errors
      expect { game.db_create_game }.not_to raise_error
      expect { game.db_save_card(UnoCard.new(:red, 5), 'Alice') }.not_to raise_error
    end
  end
  
  describe "Full game flow" do
    let(:game) { IrcUnoGame.new('TestCreator', 1) }
    
    it "plays through a turn successfully" do
      alice = UnoPlayer.new('Alice')
      bob = UnoPlayer.new('Bob')
      
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
      
      # Get current player
      current_player = game.players[0]
      top_card = game.top_card
      
      # Find a playable card
      playable_card = current_player.hand.find { |card| game.playable_now?(card) }
      
      if playable_card
        # Set color for wild cards
        if playable_card.color == :wild
          playable_card.set_wild_color(:red)
        end
        
        # Play the card
        success = game.player_card_play(current_player, playable_card)
        expect(success).to be true
        
        # Card should be removed from hand
        expect(current_player.hand.find_card(playable_card.to_s)).to be_nil
      else
        # Pick a card
        game.pick_single
        expect(current_player.hand.size).to eq(8)
      end
    end
  end
end
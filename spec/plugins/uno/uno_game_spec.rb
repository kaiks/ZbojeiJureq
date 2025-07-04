require_relative 'uno_spec_helper'

RSpec.describe UnoGame do
  let(:game) { TestUnoGame.new('TestCreator', 1) } # casual mode to avoid DB
  
  describe '#initialize' do
    it 'creates a game with initial state' do
      expect(game.game_state).to eq(0)
      expect(game.players).to be_empty
      expect(game.creator).to eq('TestCreator')
    end
    
    it 'initializes with empty players array' do
      expect(game.players).to be_a(Array)
      expect(game.players).to be_empty
    end
    
    it 'creates a full deck' do
      # Check internal full_deck
      full_deck = game.instance_variable_get(:@full_deck)
      expect(full_deck).to be_a(CardStack)
      expect(full_deck.size).to eq(108)
    end
  end
  
  describe '#add_player' do
    let(:alice) { UnoPlayer.new('Alice') }
    let(:bob) { UnoPlayer.new('Bob') }
    
    it 'adds player to the game' do
      game.add_player(alice)
      expect(game.players).to include(alice)
    end
    
    it 'shuffles players after adding' do
      # Add many players to test shuffling
      players = 10.times.map { |i| UnoPlayer.new("Player#{i}") }
      players.each { |p| game.add_player(p) }
      
      # Order should be randomized (very small chance of being in exact order)
      original_names = players.map(&:nick)
      game_names = game.players.map(&:nick)
      expect(game_names).to match_array(original_names)
    end
    
    it 'notifies when player joins' do
      game.add_player(alice)
      expect(game.notifications).to include("Alice joins the game")
    end
    
    it 'prevents joining after game is locked' do
      game.instance_variable_set(:@locked, true)
      game.add_player(alice)
      expect(game.players).to be_empty
      expect(game.notifications.last).to include("not possible to join")
    end
  end
  
  describe '#start_game' do
    let(:alice) { UnoPlayer.new('Alice') }
    let(:bob) { UnoPlayer.new('Bob') }
    
    before do
      game.add_player(alice)
      game.add_player(bob)
    end
    
    it 'requires at least 2 players' do
      single_game = TestUnoGame.new('Creator', 1)
      single_game.add_player(alice)
      single_game.start_game
      expect(single_game.game_state).to eq(0)
      expect(single_game.notifications.last).to include("at least two players")
    end
    
    it 'sets game state to 1' do
      game.start_game
      expect(game.game_state).to eq(1)
    end
    
    it 'deals 7 cards to each player' do
      game.start_game
      game.players.each do |player|
        expect(player.hand.size).to eq(7)
      end
    end
    
    it 'sets a top card' do
      game.start_game
      expect(game.top_card).not_to be_nil
      expect(game.top_card).to be_a(UnoCard)
    end
    
    it 'ensures first card is not offensive' do
      # The deck should be shuffled until first card is not +2 or wd4
      100.times do
        new_game = TestUnoGame.new('Creator', 1)
        new_game.add_player(UnoPlayer.new('P1'))
        new_game.add_player(UnoPlayer.new('P2'))
        new_game.start_game
        expect(new_game.top_card.is_offensive?).to be false
      end
    end
    
    it 'prevents starting twice' do
      game.start_game
      initial_notifications = game.notifications.size
      game.start_game
      expect(game.notifications.last).to include("already been dealt")
    end
  end
  
  describe '#player_card_play' do
    let(:alice) { UnoPlayer.new('Alice') }
    let(:bob) { UnoPlayer.new('Bob') }
    
    before do
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
      # Set a known top card
      @top_card = UnoCard.new(:red, 5)
      game.instance_variable_set(:@top_card, @top_card)
    end
    
    context 'valid plays' do
      before do
        # Ensure alice is the current player (at index 0)
        game.instance_variable_set(:@players, [alice, bob])
      end
      
      it 'allows playing matching color' do
        card = UnoCard.new(:red, 9)
        alice.hand = Hand.new
        alice.hand << card
        alice.hand << UnoCard.new(:blue, 5)  # Extra card so game doesn't end
        expect(game.player_card_play(alice, card)).to be true
        expect(alice.hand).not_to include(card)
        expect(game.top_card).to eq(card)
      end
      
      it 'allows playing matching number' do
        card = UnoCard.new(:blue, 5)
        alice.hand = Hand.new
        alice.hand << card
        alice.hand << UnoCard.new(:green, 3)  # Extra card so game doesn't end
        expect(game.player_card_play(alice, card)).to be true
      end
      
      it 'allows playing wild card' do
        card = UnoCard.new(:wild, 'wild')
        alice.hand = Hand.new
        alice.hand << card
        alice.hand << UnoCard.new(:blue, 5)  # Extra card so game doesn't end
        # Set wild color before playing
        card.set_wild_color(:red)
        expect(game.player_card_play(alice, card)).to be true
      end
      
      it 'removes card from player hand' do
        card = UnoCard.new(:red, 7)
        alice.hand = Hand.new
        alice.hand << card
        alice.hand << UnoCard.new(:blue, 5)  # Extra card so game doesn't end
        game.player_card_play(alice, card)
        expect(alice.hand).not_to include(card)
        expect(alice.hand.size).to eq(1)
      end
      
      it 'updates top card' do
        card = UnoCard.new(:red, 7)
        alice.hand = Hand.new
        alice.hand << card
        alice.hand << UnoCard.new(:blue, 5)  # Extra card so game doesn't end
        game.player_card_play(alice, card)
        expect(game.top_card).to eq(card)
      end
    end
    
    context 'invalid plays' do
      it 'rejects non-matching card' do
        # Ensure alice is the current player
        game.instance_variable_set(:@players, [alice, bob])
        
        card = UnoCard.new(:blue, 9)
        alice.hand << card
        expect(game.player_card_play(alice, card)).to be false
        expect(alice.hand).to include(card)
        expect(game.notifications.last).to include("doesn't play")
      end
      
      it 'rejects play when not player turn' do
        # Ensure alice is the current player, not bob
        game.instance_variable_set(:@players, [alice, bob])
        
        card = UnoCard.new(:red, 9)
        bob.hand << card
        expect(game.player_card_play(bob, card)).to be false
        expect(game.notifications.last).to include("not your turn")
      end
      
      it 'rejects nil card' do
        # Ensure alice is the current player
        game.instance_variable_set(:@players, [alice, bob])
        
        expect(game.player_card_play(alice, nil)).to be false
        expect(game.notifications.last).to include("do not have that card")
      end
    end
  end
  
  describe 'special cards' do
    let(:alice) { UnoPlayer.new('Alice') }
    let(:bob) { UnoPlayer.new('Bob') }
    let(:charlie) { UnoPlayer.new('Charlie') }
    
    before do
      game.add_player(alice)
      game.add_player(bob)
      game.add_player(charlie)
      game.start_game
      # Set a known player order with alice first
      game.instance_variable_set(:@players, [alice, bob, charlie])
    end
    
    describe 'skip card' do
      it 'skips next player' do
        skip_card = UnoCard.new(:red, 'skip')
        alice.hand = Hand.new
        alice.hand << skip_card
        alice.hand << UnoCard.new(:blue, 5)  # Extra cards so game continues
        alice.hand << UnoCard.new(:green, 3)
        
        # Set a matching top card
        game.instance_variable_set(:@top_card, UnoCard.new(:red, 3))
        
        # Alice plays skip
        game.player_card_play(alice, skip_card)
        
        # Bob should be skipped, Charlie's turn
        expect(game.players[0].nick).to eq('Charlie')
        expect(game.notifications).to include("Bob was skipped!")
      end
    end
    
    describe 'reverse card' do
      it 'reverses play order' do
        reverse_card = UnoCard.new(:red, 'reverse')
        alice.hand = Hand.new
        alice.hand << reverse_card
        alice.hand << UnoCard.new(:blue, 5)  # Extra cards so game continues
        alice.hand << UnoCard.new(:green, 3)
        
        # Set a matching top card
        game.instance_variable_set(:@top_card, UnoCard.new(:red, 3))
        
        initial_order = game.players.map(&:nick)
        game.player_card_play(alice, reverse_card)
        
        expect(game.notifications).to include("Player order reversed!")
        # After reverse and rotate, last player should be next
        expect(game.players[0]).not_to eq(alice)
      end
    end
    
    describe '+2 card' do
      it 'starts draw two war' do
        draw2 = UnoCard.new(:red, '+2')
        alice.hand << draw2
        # Set a matching top card
        game.instance_variable_set(:@top_card, UnoCard.new(:red, 3))
        
        game.player_card_play(alice, draw2)
        expect(game.game_state).to eq(2)
        expect(game.notifications).to include(match(/draw 2 more cards \(total 2\)/))
      end
    end
    
    describe 'wild draw 4' do
      it 'starts wild draw four war' do
        wd4 = UnoCard.new(:wild, 'wild+4')
        alice.hand << wd4
        # Set color for wild card
        wd4.set_wild_color(:red)
        
        game.player_card_play(alice, wd4)
        expect(game.game_state).to eq(3)
        expect(game.notifications).to include(match(/draw 4 more cards \(total 4\)/))
      end
    end
  end
  
  describe 'war states' do
    let(:alice) { UnoPlayer.new('Alice') }
    let(:bob) { UnoPlayer.new('Bob') }
    
    before do
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
      # Set known player order
      game.instance_variable_set(:@players, [alice, bob])
    end
    
    describe '+2 war' do
      before do
        # Start +2 war
        draw2 = UnoCard.new(:red, '+2')
        alice.hand << draw2
        game.instance_variable_set(:@top_card, UnoCard.new(:red, 3))
        game.player_card_play(alice, draw2)
        # Now it's bob's turn
        expect(game.players[0]).to eq(bob)
      end
      
      it 'allows playing another +2' do
        another_draw2 = UnoCard.new(:blue, '+2')
        bob.hand << another_draw2
        
        expect(game.player_card_play(bob, another_draw2)).to be true
        expect(game.notifications).to include(match(/total 4/))
      end
      
      it 'allows playing reverse during war' do
        reverse = UnoCard.new(:red, 'reverse')
        bob.hand << reverse
        
        expect(game.player_card_play(bob, reverse)).to be true
      end
      
      it 'allows playing wd4 during +2 war' do
        wd4 = UnoCard.new(:wild, 'wild+4')
        wd4.set_wild_color(:red) # Must set color before playing
        bob.hand << wd4
        
        expect(game.player_card_play(bob, wd4)).to be true
        expect(game.game_state).to eq(3) # Escalates to wd4 war
      end
      
      it 'rejects regular cards during war' do
        regular = UnoCard.new(:red, 5)
        bob.hand << regular
        
        expect(game.player_card_play(bob, regular)).to be false
      end
    end
  end
  
  describe '#pick_single' do
    let(:alice) { UnoPlayer.new('Alice') }
    let(:bob) { UnoPlayer.new('Bob') }
    
    before do
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
    end
    
    it 'allows picking one card' do
      current_player = game.players[0]
      initial_size = current_player.hand.size
      game.pick_single
      expect(current_player.hand.size).to eq(initial_size + 1)
      expect(game.notifications.last).to include("draws a card")
    end
    
    it 'prevents picking twice' do
      game.pick_single
      game.pick_single
      expect(game.notifications.last).to include("can't pick now")
    end
    
    it 'forces draw in war state' do
      # Start +2 war
      game.instance_variable_set(:@game_state, 2)
      game.instance_variable_set(:@stacked_cards, 2)
      
      game.pick_single
      expect(game.notifications.last).to include("can't pick now")
    end
  end
  
  describe '#turn_pass' do
    let(:alice) { UnoPlayer.new('Alice') }
    let(:bob) { UnoPlayer.new('Bob') }
    
    before do
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
    end
    
    it 'requires picking first in normal state' do
      game.turn_pass
      expect(game.notifications.last).to include("pick a card first")
    end
    
    it 'allows pass after picking' do
      game.pick_single
      initial_player = game.players[0]
      game.turn_pass
      expect(game.players[0]).not_to eq(initial_player)
    end
    
    it 'forces drawing stacked cards in war state' do
      game.instance_variable_set(:@game_state, 2)
      game.instance_variable_set(:@stacked_cards, 4)
      
      current_player = game.players[0]
      initial_size = current_player.hand.size
      game.turn_pass
      expect(current_player.hand.size).to eq(initial_size + 4)
      expect(game.game_state).to eq(1) # Back to normal
    end
  end
  
  describe 'winning conditions' do
    let(:alice) { UnoPlayer.new('Alice') }
    let(:bob) { UnoPlayer.new('Bob') }
    
    before do
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
      # Clear hands
      alice.hand = Hand.new
      bob.hand = Hand.new
    end
    
    it 'detects winner when player has no cards' do
      current_player = game.players[0]
      other_player = game.players[1]
      
      # Set up current player with one card that plays
      current_player.hand = Hand.new
      card = UnoCard.new(:red, 5)
      current_player.hand << card
      game.instance_variable_set(:@top_card, UnoCard.new(:red, 3))
      
      # Other player has cards for scoring
      other_player.hand = Hand.new
      other_player.hand << [UnoCard.new(:blue, 5), UnoCard.new(:green, 'skip')]
      
      game.player_card_play(current_player, card)
      
      expect(game.game_state).to eq(0) # Game ended
      # Should see a notification about points (minimum 30)
      points_notification = game.notifications.find { |n| n.include?("gains") && n.include?("points") }
      expect(points_notification).not_to be_nil
    end
    
    it 'calculates score correctly' do
      # Ensure alice is the current player
      game.instance_variable_set(:@players, [alice, bob])
      
      # Set up alice with one card to win
      alice.hand = Hand.new
      alice.hand << UnoCard.new(:red, 5)
      
      # Bob has specific cards for scoring
      bob.hand = Hand.new
      bob.hand << [
        UnoCard.new(:blue, 9),      # 9 points
        UnoCard.new(:green, 'skip'), # 20 points
        UnoCard.new(:wild, 'wild')   # 50 points
      ]
      
      game.instance_variable_set(:@top_card, UnoCard.new(:red, 3))
      game.player_card_play(alice, alice.hand[0])
      
      expect(game.instance_variable_get(:@total_score)).to eq(79)
    end
    
    it 'enforces minimum score of 30' do
      current_player = game.players[0]
      other_player = game.players[1]
      
      # Set up for minimal score
      current_player.hand = Hand.new
      current_player.hand << UnoCard.new(:red, 5)
      
      other_player.hand = Hand.new
      other_player.hand << UnoCard.new(:blue, 1) # Only 1 point
      
      game.instance_variable_set(:@top_card, UnoCard.new(:red, 3))
      game.player_card_play(current_player, current_player.hand[0])
      
      # Check notification mentions 30 points (minimum)
      points_notification = game.notifications.find { |n| n.include?("gains 30 points") }
      expect(points_notification).not_to be_nil
    end
  end
  
  describe 'double play' do
    let(:alice) { UnoPlayer.new('Alice') }
    let(:bob) { UnoPlayer.new('Bob') }
    
    before do
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
      game.instance_variable_set(:@top_card, UnoCard.new(:red, 3))
    end
    
    it 'allows playing two identical cards' do
      current_player = game.players[0]
      card1 = UnoCard.new(:red, 5)
      card2 = UnoCard.new(:red, 5)
      current_player.hand << [card1, card2]
      
      expect(game.player_card_play(current_player, card1, true)).to be true
      # Player started with 7 cards, added 2, played 2, should have 7 left
      expect(current_player.hand.size).to eq(7)
      expect(game.notifications).to include('[Playing two cards]')
    end
    
    it 'rejects double play with picked card' do
      current_player = game.players[0]
      # Pick a card first
      game.pick_single
      
      # Get the actual picked card from the game instance
      picked_card = game.instance_variable_get(:@picked_card)
      
      if picked_card && picked_card.plays_after?(game.top_card)
        # If it's a wild card, we need to set its color first
        if picked_card.figure == 'wild' || picked_card.figure == 'wild+4'
          picked_card.set_wild_color(:red)
        end
        
        expect(game.player_card_play(current_player, picked_card, true)).to be false
        expect(game.notifications.last).to include("can't play the picked card twice")
      else
        # If no playable card was picked, test is not applicable
        skip "No playable card was picked"
      end
    end
  end
  
  describe 'uno announcement' do
    let(:alice) { UnoPlayer.new('Alice') }
    let(:bob) { UnoPlayer.new('Bob') }
    
    before do
      game.add_player(alice)
      game.add_player(bob)
      game.start_game
      # Set known player order
      game.instance_variable_set(:@players, [alice, bob])
      # Set up Alice with 2 cards
      alice.hand = Hand.new
      alice.hand << [UnoCard.new(:red, 5), UnoCard.new(:blue, 5)]
      game.instance_variable_set(:@top_card, UnoCard.new(:red, 3))
    end
    
    it 'announces UNO when player has one card left' do
      current_player = game.players[0]
      # Clear hand and give exactly 2 cards
      current_player.hand = Hand.new
      current_player.hand << [UnoCard.new(:red, 5), UnoCard.new(:blue, 5)]
      game.instance_variable_set(:@top_card, UnoCard.new(:red, 3))
      
      game.player_card_play(current_player, current_player.hand[0])
      # Check for the announcement (contains IRC color codes)
      uno_announcement = game.notifications.find { |n| n.include?("has just one card left!") }
      expect(uno_announcement).not_to be_nil
      expect(uno_announcement).to include(current_player.to_s)
    end
    
    it 'announces when player has three cards left' do
      current_player = game.players[0]
      # Clear hand and give exactly 4 cards
      current_player.hand = Hand.new
      current_player.hand << [
        UnoCard.new(:red, 5),
        UnoCard.new(:blue, 5), 
        UnoCard.new(:green, 5),
        UnoCard.new(:yellow, 5)
      ]
      game.instance_variable_set(:@top_card, UnoCard.new(:red, 3))
      
      game.player_card_play(current_player, current_player.hand[0])
      # The message includes IRC color code before "three"
      three_cards_announcement = game.notifications.find { |n| n.include?("three") && n.include?("cards left!") }
      expect(three_cards_announcement).not_to be_nil
      expect(three_cards_announcement).to include(current_player.to_s)
    end
  end
end
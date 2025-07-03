require 'spec_helper'
require_relative '../../../extensions/thread_safe'
require_relative '../../../plugins/uno/misc'
require_relative '../../../plugins/uno/uno'
require_relative '../../../plugins/uno/uno_card'
require_relative '../../../plugins/uno/uno_hand'
require_relative '../../../plugins/uno/uno_card_stack'
require_relative '../../../plugins/uno/uno_player'
require_relative '../../../plugins/uno/uno_game'

# We'll temporarily remove ThreadSafeDefault for testing
class UnoGameWithoutThreadSafety
  attr_reader :players, :top_card, :game_state, :creator
  attr_reader :card_stack
  attr_reader :starting_stack, :first_player
  attr_accessor :notifier
  
  def initialize(creator, casual = 0, notifier = nil)
    @players = []
    @stacked_cards = 0
    @card_stack = nil
    @played_cards = nil
    @top_card = nil
    @picked_card = nil
    @locked = false
    @game_state = 0
    @start = nil
    @end = nil
    @creator = creator
    @casual = casual
    @full_deck = CardStack.new
    @full_deck.fill
    @notifier = notifier || Uno::ConsoleNotifier.new
  end
  
  def add_player(p)
    if @locked == false
      @players.push p
      @players.shuffle!
      notify "#{p} joins the game"
    else
      notify "Sorry, it's not possible to join this game anymore."
    end
  end
  
  def start_game
    if @players.length < 2
      notify 'You need at least two players to start a game.'
      return
    end
    @game_state = 1
    @card_stack = @full_deck.clone
    prepare_card_stack
    @played_cards = CardStack.new
    top_card = @card_stack.pick(1)[0]
    @top_card = top_card
    @players.shuffle!
    deal_cards_to_players
    notify "Game started! Top card: #{@top_card.to_s}"
  end
  
  def prepare_card_stack
    loop do
      @card_stack.shuffle!
      break unless @card_stack[0].is_offensive?
    end
  end
  
  def deal_cards_to_players
    @players.each do |p|
      cards = @card_stack.pick(7)
      p.hand << cards
      notify_player(p, "Your cards: #{p.hand.to_s}")
    end
  end
  
  def notify(text)
    @notifier.notify_game(text)
  end
  
  def notify_player(p, text)
    @notifier.notify_player(p.to_s, text)
  end
end

RSpec.describe "Notifier integration" do
  describe "UnoGame with NullNotifier" do
    let(:notifier) { Uno::NullNotifier.new }
    let(:game) { UnoGameWithoutThreadSafety.new('TestCreator', 1, notifier) }
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
      expect(player_msgs.first[:message]).to include("Your cards:")  # Card display
    end
    
    it "handles game flow with notifier" do
      game.add_player(alice)
      game.add_player(bob)
      
      expect(notifier.game_notifications.size).to eq(2)
      
      game.start_game
      
      # Should have notifications about game start
      start_notification = notifier.game_notifications.find { |n| n.include?("Game started") }
      expect(start_notification).not_to be_nil
      expect(start_notification).to include("Top card:")
    end
  end
  
  describe "IrcUnoGame setup" do
    it "can be created without IRC bot (falls back to console notifier)" do
      game = IrcUnoGame.new('TestCreator', 1)
      expect(game).to be_a(IrcUnoGame)
      expect(game.notifier).to be_a(Uno::ConsoleNotifier)
    end
  end
end
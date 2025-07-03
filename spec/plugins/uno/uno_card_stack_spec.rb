require_relative 'uno_spec_helper'

RSpec.describe CardStack do
  let(:stack) { CardStack.new }
  
  describe '#fill' do
    before { stack.fill }
    
    it 'creates a standard UNO deck' do
      # Standard UNO deck has 108 cards
      expect(stack.size).to eq(108)
    end
    
    it 'creates correct number of number cards' do
      # 0: 1 of each color = 4 cards
      # 1-9: 2 of each color = 72 cards
      # Total: 76 number cards
      number_cards = stack.select { |card| card.figure.is_a?(Integer) }
      expect(number_cards.size).to eq(76)
    end
    
    it 'creates one zero of each color' do
      zeros = stack.select { |card| card.figure == 0 }
      expect(zeros.size).to eq(4)
      expect(zeros.map(&:color).sort).to eq([:blue, :green, :red, :yellow])
    end
    
    it 'creates two of each non-zero number per color' do
      (1..9).each do |num|
        cards = stack.select { |card| card.figure == num }
        expect(cards.size).to eq(8) # 2 per color, 4 colors
      end
    end
    
    it 'creates correct number of action cards' do
      # Skip, Reverse, +2: 2 of each color = 24 cards total
      action_figures = ['skip', 'reverse', '+2']
      action_cards = stack.select { |card| action_figures.include?(card.figure) }
      expect(action_cards.size).to eq(24)
    end
    
    it 'creates two of each action card per color' do
      ['skip', 'reverse', '+2'].each do |action|
        cards = stack.select { |card| card.figure == action }
        expect(cards.size).to eq(8) # 2 per color, 4 colors
        
        [:red, :green, :blue, :yellow].each do |color|
          colored_actions = cards.select { |card| card.color == color }
          expect(colored_actions.size).to eq(2)
        end
      end
    end
    
    it 'creates correct number of wild cards' do
      wild_cards = stack.select { |card| card.figure == 'wild' }
      wild4_cards = stack.select { |card| card.figure == 'wild+4' }
      
      expect(wild_cards.size).to eq(4)
      expect(wild4_cards.size).to eq(4)
    end
    
    it 'creates wild cards with :wild color' do
      wilds = stack.select { |card| card.special_card? }
      expect(wilds).to all(have_attributes(color: :wild))
    end
    
    it 'returns integer (not self for chaining)' do
      new_stack = CardStack.new
      # The fill method returns 4 from the times block, not self
      expect(new_stack.fill).to eq(4)
    end
  end
  
  describe '#pick' do
    before do
      # Add some known cards
      @red5 = UnoCard.new(:red, 5)
      @blue3 = UnoCard.new(:blue, 3)
      @green_skip = UnoCard.new(:green, 'skip')
      stack << [@red5, @blue3, @green_skip]
    end
    
    it 'returns specified number of cards' do
      picked = stack.pick(2)
      expect(picked.size).to eq(2)
    end
    
    it 'returns CardStack instance' do
      picked = stack.pick(1)
      expect(picked).to be_a(CardStack)
    end
    
    it 'removes picked cards from stack' do
      original_size = stack.size
      stack.pick(2)
      expect(stack.size).to eq(original_size - 2)
    end
    
    it 'picks from the beginning of the stack' do
      picked = stack.pick(2)
      expect(picked[0]).to eq(@red5)
      expect(picked[1]).to eq(@blue3)
    end
    
    it 'modifies the original stack' do
      stack.pick(1)
      expect(stack.first).to eq(@blue3)
    end
    
    it 'can pick all cards' do
      all_cards = stack.pick(3)
      expect(all_cards.size).to eq(3)
      expect(stack).to be_empty
    end
    
    it 'handles picking more cards than available' do
      # Ruby's shift handles this gracefully
      picked = stack.pick(5)
      expect(picked.size).to eq(3)
      expect(stack).to be_empty
    end
    
    it 'returns empty CardStack when picking from empty stack' do
      empty_stack = CardStack.new
      picked = empty_stack.pick(1)
      expect(picked).to be_a(CardStack)
      expect(picked).to be_empty
    end
  end
  
  describe '#create_discard_pile' do
    it 'creates a Hand instance for discard pile' do
      expect(stack.instance_variable_get(:@discard_pile)).to be_nil
      stack.create_discard_pile
      discard = stack.instance_variable_get(:@discard_pile)
      expect(discard).to be_a(Hand)
      expect(discard).to be_empty
    end
  end
  
  describe 'inheritance from Hand' do
    it 'supports all Hand methods' do
      stack << UnoCard.new(:red, 5)
      expect(stack).to respond_to(:to_s)
      expect(stack).to respond_to(:value)
      expect(stack).to respond_to(:find_card)
    end
    
    it 'can be shuffled' do
      stack.fill
      original_order = stack.map(&:to_s).join(',')
      
      # Shuffle multiple times to ensure it's actually random
      # (very small chance all shuffles result in same order)
      shuffled_differently = false
      10.times do
        stack.shuffle!
        if stack.map(&:to_s).join(',') != original_order
          shuffled_differently = true
          break
        end
      end
      
      expect(shuffled_differently).to be true
    end
  end
  
  describe 'integration with UNO deck' do
    it 'creates valid playable deck' do
      stack.fill
      
      # Verify deck composition
      total_cards = stack.size
      colors = stack.map(&:color).uniq.sort
      figures = stack.map(&:figure).uniq
      
      expect(total_cards).to eq(108)
      expect(colors).to include(:red, :green, :blue, :yellow, :wild)
      expect(figures).to include(0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
      expect(figures).to include('skip', 'reverse', '+2', 'wild', 'wild+4')
    end
    
    it 'allows dealing initial hands' do
      stack.fill
      stack.shuffle!
      
      # Deal 7 cards to 4 players
      hands = []
      4.times { hands << stack.pick(7) }
      
      expect(stack.size).to eq(108 - 28)
      hands.each do |hand|
        expect(hand.size).to eq(7)
        expect(hand).to be_a(CardStack)
      end
    end
  end
end
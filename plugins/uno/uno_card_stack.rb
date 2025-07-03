require './plugins/uno/uno_card.rb'
require './plugins/uno/uno_hand.rb'

class CardStack < Hand
  def create_discard_pile
    @discard_pile = Hand.new
  end

  def fill
    Uno::STANDARD_SHORT_FIGURES.each do |f|
      %w[r g b y].each do |c|
        self << UnoCard.parse(c + f)
        self << UnoCard.parse(c + f) if f != '0'
      end
    end

    4.times do
      self << UnoCard.parse('ww')
      self << UnoCard.parse('wd4')
    end
    
    self
  end

  # shuffle!

  def pick(n)
    to_return = CardStack.new(first(n))
    shift(n)
    to_return
  end
end

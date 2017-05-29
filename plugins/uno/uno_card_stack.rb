require './plugins/uno/uno_card.rb'
require './plugins/uno/uno_hand.rb'

class CardStack < Hand

  def create_discard_pile
    @discard_pile = Hand.new
  end

  def fill
    Uno::STANDARD_SHORT_FIGURES.each { |f|
      ['r','g','b','y'].each { |c|
        self << UnoCard.parse(c + f)
        if f != '0'
          self << UnoCard.parse(c + f)
        end
      }
    }

    4.times {
      self << UnoCard.parse('ww')
      self << UnoCard.parse('wd4')
    }
  end

  #shuffle!


  def pick(n)
    to_return = CardStack.new(self.first(n))
    shift(n)
    return to_return
  end


end
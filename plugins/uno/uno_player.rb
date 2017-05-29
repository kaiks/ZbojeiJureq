class UnoPlayer
  attr_accessor :hand
  attr_reader :nick
  def initialize(nick)
    @joined = Time.now
    @nick = nick
    @hand = Hand.new
  end

  def to_s
    nick
  end

  def change_nick new_nick
    @nick = new_nick
  end

  def ==(player)
    @nick == player.nick
  end
end
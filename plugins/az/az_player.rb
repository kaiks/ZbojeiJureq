class AzPlayer
  attr_reader :nick, :joined
  attr_accessor :tries
  def initialize(nick)
    @nick = nick
    @joined = Time.now
    @tries = 0
  end

  def to_s
    @nick
  end
end

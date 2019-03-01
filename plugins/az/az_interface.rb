require_relative 'az_game'
class AzInterface
  def initialize(channel, nick, db, dictionary, drawing_dictionary = nil)
    @channel = channel
    drawing_dictionary ||= dictionary
    @game = AzGame.new(nick, self, db, dictionary, drawing_dictionary)
    @db = db
  end

  def notify(msg)
    @channel.send msg
  end

  def try(msg, nick)
    @game.attempt(msg, nick)
  end

  def game_state
    return 0 if @game.nil? || @game.won?
    1
  end

  def cancel(nick)
    player = @game.find_player(nick)
    @game.cancel(player)
  end

  def range
    @game.range_to_s
  end

  def won?
    @game.won?
  end

  def hint
    @game.hint
  end
end

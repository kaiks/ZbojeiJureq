
module AzConfig
  TRIES_BEFORE_HINT = 10
end

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

class AzDictionary
  attr_reader :size


  def initialize(path)
    @dictionary_array = IO.read(path).split
    @dictionary = Hash[ @dictionary_array.map { |element| [element, 1] } ]
    @size = @dictionary_array.size
  end


  def word_at(number)
    @dictionary_array[number]
  end


  def random_word
    word_number = rand(@size)
    word_at(word_number)
  end


  def is_a_valid_word?(word)
    @dictionary.fetch(word, 0) == 1
  end


  def first_word
    word_at(0)
  end


  def last_word
    word_at(@size - 1)
  end
end

class AzGame
  #class instance variables are specific to only that class

  include Math

  def initialize(nick, interface = nil, db = nil, dictionary = nil, drawing_dictionary = nil)
    @@db = db unless db.nil?

    @dictionary = dictionary || AzDictionary.new('en_dict.txt')
    @easy = (!drawing_dictionary.nil?)
    @drawing_dictionary = drawing_dictionary || @dictionary
    @interface = interface
    player = AzPlayer.new(nick)
    @started_by = AzPlayer.new(nick)
    @started_at = Time.now

    @number_of_words = @dictionary.size

    @players = [player]
    @total_guesses = 0

    setup
  end


  def setup
    @won = false
    choose_winning_word
    set_lower_bound(@dictionary.first_word)
    set_upper_bound(@dictionary.last_word)

    save_game_to_db

    say 'AZ started! New range: ' + range_to_s
  end

  def save_game_to_db
    unless @@db.nil?
      @id = (@@db[:az_game].max(:id).to_i+1)
      @@db[:az_game].insert(:id => @id, :started_at => @started_at, :started_by => @started_by.to_s,
                            :winning_word => @winning_word, :channel => 'N/A')
    end
  end

  def finalize_game_in_db
    @@db[:az_game].where(:id => @id).update(:finished_at => @finished_at, :finished_by => @finished_by.to_s, :points => @points, :won => @won) unless @@db.nil?
  end


  def choose_winning_word
    @winning_word = @drawing_dictionary.random_word
  end


  def range_to_s
    @lower_bound.to_s + ' - ' + @upper_bound.to_s
  end


  def set_lower_bound(word)
    @lower_bound = word
  end


  def set_upper_bound(word)
    @upper_bound = word
  end


  def is_within_bounds(word)
    @dictionary.is_a_valid_word?(word) and word > @lower_bound and word < @upper_bound
  end


  def save_attempt_to_db(word, nick)
    @@db[:az_guess].insert(:nick => nick, :guess => word, :time => Time.now, :game => @id) unless @@db.nil?
  end


  def attempt(word, nick)
    if is_within_bounds(word) && @won == false
      player = find_player(nick)

      player.tries += 1
      @total_guesses += 1

      save_attempt_to_db(word, nick)


      if word < @winning_word
        @lower_bound = word
        say(range_to_s)
      elsif word > @winning_word
        @upper_bound = word
        say(range_to_s)
      else
        win(player)
      end

    end
  end


  def prepare_end(player)
    @finished_at = Time.now
    @finished_by = player.to_s
  end


  def win(player)
    prepare_end(player)
    @points = score
    @won = true
    say("Hurray! #{player.to_s} has won for #{@points.to_s} points after #{player.tries} tries and #{@total_guesses} total tries")
    finalize_game_in_db
  end


  def cancel(player)
    prepare_end(player)
    say "Game canceled by #{player.to_s} after #{@total_guesses} total tries. Winning word was #{@winning_word}"
    finalize_game_in_db
  end


  def add_player(nick)
    player = AzPlayer.new(nick)
    @players << player
    return player
  end


  def find_player(nick)
    player = @players.find { |player| player.nick == nick }
    player ||= add_player(nick)
    return player
  end


  def say(text)
    @interface.notify(text) unless @interface.nil?
  end


  def score
    n = @total_guesses
    p = @players.length
    t = (100*exp(-(n-1)**2/50.0**2)).ceil + p
    t /= 2 if @easy
    return t
  end


  def won?
    @won
  end

  def hint
    if @total_guesses > AzConfig::TRIES_BEFORE_HINT
      say "Last letters are #{@winning_word[-3..-1]}"
    else
      say "Sorry, you need at least #{AzConfig::TRIES_BEFORE_HINT} guesses! Got #{@total_guesses} so far."
    end
  end

end

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
    if @game.nil? or @game.won?
      return 0
    end
    return 1
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


class AzPlugin
  include Cinch::Plugin

  self.prefix = '.'
  match /az stop/, group: :az, method: :stop
  match /az help/, group: :az, method: :help
  match /az hint/, group: :az, method: :hint
  match /az ez/,   group: :az, method: :start_ez
  match /az top(\s?[0-5])?/, group: :az, method: :top
  match /az$/, group: :az, method: :start
  match /^([A-z]{1,45})$/, use_prefix: false, group: :az, method: :guess

  def initialize(*args)
    super
    @games = {}
    @dictionary = AzDictionary.new('en_dict.txt')
    @easy_dictionary = AzDictionary.new('ez.txt')
  end

  def hint(m)
    @games[m.channel].hint unless @games[m.channel].nil?
  end

  def stop(m)
    if @games[m.channel].nil?
      m.reply 'No az game is running.'
    else
      @games[m.channel].cancel(m.user.to_s)
      @games[m.channel] = nil
    end
  end

  def start(m)
    if @games[m.channel].nil?
      @games[m.channel] = AzInterface.new(m.channel, m.user.to_s, @bot.db, @dictionary)
    else
      m.reply @games[m.channel].range
    end
  end

  def start_ez(m)
    if @games[m.channel].nil?
      @games[m.channel] = AzInterface.new(m.channel, m.user.to_s, @bot.db, @dictionary, @easy_dictionary)
    else
      m.reply @games[m.channel].range
    end
  end


  def guess(m, word)
    unless @games[m.channel].nil?
      @games[m.channel].try(word, m.user.to_s)
      @games[m.channel] = nil if @games[m.channel].won?
    end
  end

  def help(m)
    m.reply 'az help available at http://kx.shst.pl/help/az.html'
  end

  def top(m, n = 5)
    counter = 0

    n ||= 5
    n = n.to_i

    nick_total_games = @bot.db[:az_guess].group(:nick).select_group(:nick).select_append(Sequel.function(:count, :game).distinct)

    m.reply '   ' + "nick".ljust(12) + 'points  games average wins - full list: http://kaiks.eu/az.php'
    @bot.db[:az_game].group(:finished_by).select_group(:finished_by).select_append(Sequel.function(:sum, :points)).select_append(Sequel.function(:count, :id)).order(Sequel.desc(2)).limit(n).each { |row|
      counter += 1
      values = row.values
      nick = values[0].to_s
      total_score = values[1]
      total_wins = values[2]
      total_games = nick_total_games.where(nick: nick).first[:count]
      average = (total_score.to_f/total_games.to_f).round(2)

      if values[0].to_s.length > 0
        m.reply "#{counter}. #{nick.ljust(12)} #{total_score.to_s.ljust(6)} #{total_games.to_s.ljust(5)} #{average.to_s.ljust(7)} #{total_wins.to_s.ljust(7)}"
      end
    }
  end


end
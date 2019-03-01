require_relative 'az_player'
require_relative 'az_dictionary'

class AzGame
  include Math
  attr_reader :db, :dictionary
  TRIES_BEFORE_HINT = 10

  def initialize(nick, interface = nil, database = nil, dictionary = nil, drawing_dictionary = nil)
    @db = database

    @dictionary = dictionary
    @easy = !drawing_dictionary.nil?
    @drawing_dictionary = drawing_dictionary || dictionary
    @interface = interface
    player = AzPlayer.new(nick)
    @started_by = AzPlayer.new(nick)
    @started_at = Time.now

    @number_of_words = dictionary.size

    @players = [player]
    @total_guesses = 0

    setup
  end

  def setup
    @won = false
    choose_winning_word
    set_lower_bound(dictionary.first_word)
    set_upper_bound(dictionary.last_word)

    save_game_to_db

    say 'AZ started! New range: ' + range_to_s
  end

  def save_game_to_db
    return if db.nil?
    @id = (db[:az_game].max(:id).to_i + 1)
    db[:az_game].insert(id: @id, started_at: @started_at, started_by: @started_by.to_s,
                        winning_word: @winning_word, channel: 'N/A')
  end

  def finalize_game_in_db
    return if db.nil?
    db[:az_game].where(id: @id).update(finished_at: @finished_at, finished_by: @finished_by.to_s, points: @points, won: @won)
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
    dictionary.word_valid?(word) && (word > @lower_bound) && (word < @upper_bound)
  end

  def save_attempt_to_db(word, nick)
    return if db.nil?
    db[:az_guess].insert(nick: nick, guess: word, time: Time.now, game: @id)
  end

  def attempt(word, nick)
    return if !is_within_bounds(word) || @won
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

  def prepare_end(player)
    @finished_at = Time.now
    @finished_by = player.to_s
  end

  def win(player)
    prepare_end(player)
    @points = score
    @won = true
    say("Hurray! #{player} has won for #{@points} points after #{player.tries} tries and #{@total_guesses} total tries")
    finalize_game_in_db
  end

  def cancel(player)
    prepare_end(player)
    say "Game canceled by #{player} after #{@total_guesses} total tries. Winning word was #{@winning_word}"
    finalize_game_in_db
  end

  def add_player(nick)
    player = AzPlayer.new(nick)
    @players << player
    player
  end

  def find_player(nick)
    player = @players.detect { |p| p.nick == nick }
    player || add_player(nick)
  end

  def say(text)
    @interface.notify(text) unless @interface.nil?
  end

  def score
    n = @total_guesses
    p = @players.length
    t = (100 * exp(-(n - 1)**2 / 50.0**2)).ceil + p
    t /= 2 if @easy
    t
  end

  def won?
    @won
  end

  def hint
    if @total_guesses >= TRIES_BEFORE_HINT
      say "Last letters are #{@winning_word[-3..-1]}"
    else
      say "Sorry, you need at least #{TRIES_BEFORE_HINT} guesses! Got #{@total_guesses} so far."
    end
  end
end

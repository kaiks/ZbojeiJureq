#todo: quit
#todo: help
#todo: fix wild


#todo: make it thread safe
require 'thread'
require './plugins/uno/uno_game.rb'
require './plugins/uno/uno_db.rb'
require './config.rb'

class UnoGameHistory
  attr_accessor :stack
  attr_accessor :players
  attr_accessor :first_player

  def initialize(stack, first_player)
    @stack = stack
    @first_player = first_player
  end
end


class UnoPlugin
  include Cinch::Plugin

  self.prefix = '.'

  match /^ca$/,         group: :uno, method: :ca, use_prefix: false
  match /^cd$/,         group: :uno, method: :cd, use_prefix: false

  match /deal/,       group: :uno, method: :deal

  match /^jo$/,         group: :uno, method: :join, use_prefix: false

  match /^od$/,         group: :uno, method: :order, use_prefix: false

  match /^pa$/,         group: :uno, method: :pass, use_prefix: false
  match /^pe$/,         group: :uno, method: :pick, use_prefix: false
  match /^st$/,         group: :uno, method: :get_stack_size, use_prefix: false
  match /^pl ([A-z0-9+]{1,6})$/,   group: :uno, method: :play, use_prefix: false


  match /^tu$/,           group: :uno, method: :cd, use_prefix: false

  match /uno quit$/,     group: :uno, method: :temp
  match /uno test$/,     group: :uno, method: :testing

  match /uno casual/,   group: :uno, method: :start_casual
  match /uno reload/,   group: :uno, method: :reload
  match /uno stop/,     group: :uno, method: :stop
  match /uno top ([1-5])/,      group: :uno, method: :top
  match /uno top$/,      group: :uno, method: :top
  match /uno debug (.*)/,    group: :uno, method: :debug
  match /uno score$/,   group: :uno, method: :own_score
  match /uno score ([A-z0-9_\-]+)/,    group: :uno, method: :score

  match /uno$/,         group: :uno, method: :start
  match /uno/,          group: :uno, method: :help

  match /uno top(\s?[0-5])?/, group: :uno, method: :top

  def initialize(*args)
    super
    @games = {}
    @game = nil
    @this_game_history = nil
    @testing = false
  end

  def debug(m, text)
    return unless f m.user.has_admin_access?
    m.reply eval(text)
  end

  def testing(m)
    @testing = !@testing
    m.reply "Ok. Now set to #{@testing}"
  end

  def ca(m)
    if @game.players.map(&:nick).member? m.user.nick
      @game.show_player_cards(@game.players.find{ |p| m.user.nick==p.nick })
    end
    if @game.game_state > 0
      @game.show_card_count
    end
  end

  def cd(m)
    return unless @game.players.map(&:nick).member? m.user.nick
    @game.notify_top_card
  end

  def get_stack_size(m)
    m.reply "#{@game.card_stack.length} cards left in the stack" if @game.started?
  end


  def deal(m)
    if @game.creator.to_s == m.user.nick
      if @testing
        if @this_game_history == nil
          @game.start_game
          @this_game_history = UnoGameHistory.new(@game.starting_stack, @game.first_player)
        else
          @game.start_game @this_game_history.stack, @this_game_history.first_player
          @this_game_history = nil
        end
      else
        @game.start_game
      end
    elsif @game.started?
      m.reply 'Cards have already been dealt.'
    else
      m.reply "#{@game.creator.to_s} needs to deal"
    end
  end

  def join(m)
    puts "Current players: " + @game.players.to_s
    if @game.players.find{ |p| m.user.nick == p.nick }.nil?
      new_player = UnoPlayer.new(m.user.nick)
      @game.add_player new_player
    else
      m.reply "You are already in the game, #{m.user.nick}."
    end
  end

  def order(m)
    players_ordered = @game.players.map(&:nick).join(' ')
    @game.notify "Current order: #{players_ordered}"
  end

  def pass(m)
    if m.user.nick == @game.players[0].nick
      @game.turn_pass
    end
  end

  def pick(m)
    if m.user.nick == @game.players[0].nick
      @game.pick_single
    end
  end

  def is_a_double_card_string? text
    length = text.length
    length > 3 && length.even? &&
      (text[0..(length / 2 - 1)] == text[(length / 2)..length]) &&
      text[1] != 'd' #even length, not a wd4
  end

  def play(m)
    if m.user.nick == @game.players[0].nick
      proposed_card_text = m.message.split[1]
      card_text = proposed_card_text
      card = nil
      #make it dry
      if is_a_double_card_string?(proposed_card_text)
        puts proposed_card_text.to_s
        card_text = proposed_card_text[0..(proposed_card_text.length / 2 - 1)]
      end

      if card_text =~ /w[rgby]/
        card = @game.players[0].hand.reverse.find_card('w') #bug 1
        card.set_wild_color Uno::expand_color card_text[1] unless card.nil?
      elsif card_text =~ /wd4[rgby]/
        card = @game.players[0].hand.reverse.find_card('wd4')
        card.set_wild_color Uno::expand_color card_text[3] unless card.nil?
      elsif card_text =~ /^[^w]+$/i
        card = @game.players[0].hand.reverse.find_card(card_text)
      end
      puts "Proposed card text: #{proposed_card_text}"
      @game.player_card_play(@game.players[0], card, is_a_double_card_string?(proposed_card_text))
      @game.players[0].hand.reset_wilds
    end
  end

  def start(m)
    if @game.nil?
      @game = (IrcUnoGame.new m.user.nick)
      @game.irc ||= @bot
      @game.plugin ||= self
      m.reply "Ok, created 04U09N12O08! game on #{m.channel}, say 'jo' to join in"
      join(m)
    else
      m.reply "An uno game is already being played."
    end
  end

  def start_casual(m)
    if @game.nil?
      @game = IrcUnoGame.new(m.user.nick, 1)
      @game.irc ||= @bot
      @game.plugin ||= self
      m.reply "Ok, created casual 04U09N12O08! game on #{m.channel}, say 'jo' to join in"
      join(m)
    else
      m.reply "An uno game is already being played."
    end
  end

  def stop(m)
    @game.stop_game m.user.nick
    @game = nil
    m.reply 'Uno game has been stopped.'
    upload_db
  end

  def top(m, n = 5)
    counter = 0
    n = n.to_i

    m.reply '   ' + "nick".ljust(20) + 'points  games  average  wins  winrate - full list: http://uno.kaiks.eu '
    #SELECT *, ROUND(CAST(total_score AS FLOAT)/CAST(games AS FLOAT),2) sr FROM uno WHERE nick LIKE ' $+ %safe_nick $+ ' AND games >= 2 ORDER BY %by %ord LIMIT %count
    #UNODB[:uno].where('games > 2').select_append('ROUND(CAST(total_score as FLOAT)/CAST(games AS FLOAT,2)').order(Sequel.desc(5)).limit(n).each { |row|
    UNODB['SELECT *, ROUND(CAST(total_score AS FLOAT)/CAST(games AS FLOAT),2) FROM uno WHERE games >= 10 ORDER BY 5 DESC LIMIT ?', n].each { |row|
      counter += 1
      values = row.values
      if values[0].to_s.length > 0
        m.reply "#{counter}. #{values[0].to_s.ljust(19)} #{values[1].to_s.ljust(7)} #{values[2].to_s.ljust(6)} #{values[4].to_s.ljust(8)} #{values[3].to_s.ljust(5)} #{(values[3].to_f*100.0/values[2].to_f).round(2).to_s.ljust(5, "0")}%"
      end
    }
  end

  def end_game
    @game = nil
    @bot.send_to_ftp './uno.db', '', 'unodb'
  end

  def help(m)
    m.reply '.uno -> .deal / .uno stop / .uno top / ... uno help available at http://kaiks.eu/help/uno.html'
  end

  def winrate(games, wins)
    if games.zero?
      0.0
    else
      (100.to_f * wins / games).round(2)
    end
  end

  #todo: fix formatting
  def score(m, user)
    r = UNODB['SELECT *, ROUND(CAST(total_score AS FLOAT)/CAST(games AS FLOAT),2) FROM uno WHERE nick = ?',user].first
    games = r[:games]
    wins = r[:wins]
    winrate = winrate(games, wins)

    avg = r[:'ROUND(CAST(total_score AS FLOAT)/CAST(games AS FLOAT),2)']
    m.reply "#{r[:nick]}: #{avg} avg #{r[:total_score]} pts #{games} games #{wins} wins #{winrate}% winrate"
  end

  def own_score(m)
    score(m, m.user.nick)
  end

  def reload(m)
    load './plugins/uno/misc.rb'
    load './plugins/uno/uno.rb'
    load './plugins/uno/uno_card.rb'
    load './plugins/uno/uno_card_stack.rb'
    load './plugins/uno/uno_deck.rb'
    load './plugins/uno/uno_game.rb'
    load './plugins/uno/uno_hand.rb'
    load './plugins/uno/uno_player.rb'
    load './plugins/uno/uno_db.rb'
    m.reply 'Uno reloaded.'
  end

  def upload_db
    #todo: ftp
    @bot.upload_to_dropbox './uno.db'
  end

end
##todo: game cancel -> actions

require './plugins/uno/uno_card_stack.rb'
require './plugins/uno/uno_player.rb'
require 'thread'

#game states: 0 OFF, 1 ON, 2 WAR, 3WARWD

class UnoGame
  attr_reader :players, :top_card, :game_state, :creator
  attr_reader :card_stack
  attr_reader :starting_stack, :first_player

  def initialize(creator, casual = 0)
    @players = []
    @stacked_cards = 0
    @card_stack = nil
    @played_cards = nil
    @top_card = nil
    @picked_card = nil
    @locked = false #= can't join game
    @game_state = 0
    @start = nil
    @end = nil
    @creator = creator
    @casual = casual
    @full_deck = CardStack.new
    @full_deck.fill
    @semaphore = Mutex.new
    db_create_game
  end


  def start_game stack = nil, first_player = nil
    if @players.length < 2
      notify 'You need at least two players to start a game.'
      return
    end
    if @game_state > 0
      notify 'Cards have already been dealt.'
      return
    end
    @game_state = 1

    @card_stack = @full_deck.clone

    if stack.nil?
      prepare_card_stack
      @starting_stack = CardStack.new @card_stack
    else
      stack.reset_wilds
      @card_stack = stack
    end

    @played_cards = CardStack.new

    top_card = @card_stack.pick(1)[0]



    put_card_on_top top_card

    rotated = false

    if first_player.nil?
      @players.shuffle!
      @first_player = @players[0].nick
    else
      if @players[0].nick == first_player
        puts "rotate1"
        rotated = true
        @players.rotate! #other player has to start with same hand
      end
    end

    deal_cards_to_players

    db_save_card top_card, nil


    @start = Time.now.strftime("%F %T")
    #@players.rotate! if rotated
    #puts "rotate2" if rotated
    next_turn
  end

  def prepare_card_stack
    loop do
      @card_stack.shuffle!
      break unless @card_stack[0].is_offensive?
    end
  end

  def put_card_on_top card
    accord_game_state_to_card_played card
    @locked = true
    @played_cards << card
    @top_card = card
  end

  def accord_game_state_to_card_played card
    @stacked_cards += card.offensive_value

    if @game_state < card.offensive_value #this is stupid code but whatever
      if card.offensive_value == 2
        @game_state = 2
      elsif card.offensive_value == 4
        @game_state = 3
      end
    end

    if card.offensive_value > 0
      notify "Next player must respond or draw #{card.offensive_value} more cards (total #{@stacked_cards})"
    end
  end

  def next_turn pass = false
    manage_order_by_card @top_card, pass
    notify_top_card pass
    show_player_cards @players[0]
    @already_picked = false
  end

  def show_player_cards player
    notify_player player, "#{player.hand.to_irc_s}"
  end

  def show_card_count
    notify "Card count: #{@players.map { |p| p.nick + ' ' + p.hand.size.to_s }.join(', ')}"
  end

  def deal_cards_to_players
    @players.each { |p|
      deal_cards_to_player p
    }
  end

  def deal_cards_to_player p
    p.hand << @card_stack.pick(7)
    p.hand.each { |card|
      db_save_card card, p.to_s, 1
    }
    p.hand.sort! { |a, b| a.to_s <=> b.to_s }
  end

  def check_for_empty_stack
    if @card_stack.empty?
      notify 'Reshuffling discard pile.'
      @played_cards.each { |c| c.unset_wild_color }
      @card_stack << @played_cards
      @played_cards = CardStack.new
      @card_stack.shuffle!
    end
  end

  def give_cards_to_player p, n
    check_for_empty_stack
    @already_picked = true
    picked = @card_stack.pick(n)
    picked.each { |card|
      db_save_card card, p.to_s, 1
    }

    notify_player(p, "You draw #{n} card#{n>1 ? 's' : ''}: #{picked.to_irc_s}")
    p.hand << picked

    p.hand.sort! { |a, b| a.to_s <=> b.to_s }

    @game_state = 1
    @stacked_cards = 0
    return picked
  end

  def turn_pass
    if @already_picked == false
      if @stacked_cards == 0
        notify "You have to pick a card first."
        return
      else
        give_cards_to_player @players[0], @stacked_cards
      end
    end
    next_turn true
  end

  def pick_single
    if @already_picked == false and @stacked_cards == 0
      @already_picked = true
      notify "#{@players[0]} draws a card."
      @picked_card = (give_cards_to_player @players[0], 1)[0]
    else
      notify "Sorry #{@players[0]}, you can't pick now."
    end
  end

  def card_played card
    @locked = true
    @played_cards << card
  end


  def notify_player_turn p
    notify "Hey #{p} it's your turn!"
  end

  def add_player p
    if @locked == false
      @players.push p
      @players.shuffle!
      db_player_joins p.nick unless @casual == 1
      notify "#{p} joins the game"
    else
      notify "Sorry, it's not possible to join this game anymore."
    end
  end

  def remove_player p
    @players.delete! p
    if @players.length == 0
      stop_game p.nick
    end
  end

  def stop_game nick
    db_stop nick unless @casual == 1
  end

  def rename_player old_nick, new_nick
    @players.detect { |player| player.nick==old_nick }.nick = new_nick
  end

  def notify_order
    notify 'Current player order is: ' + @players.join(' ')
  end

  def notify_top_card passes = false
    pass_string = (passes == true) ? "#{@players[-1]} passes. " : ''
    notify "#{pass_string}#{@players[0]}'s turn. Top card: #{@top_card.to_irc_s}"
  end

  def notify text
    puts text
  end

  def clean_up_end_game #virtual method for child classes
  end

  def notify_player(p, text)
    puts "[To #{p}]: #{text}"
  end

  def debug(text)
    puts "-debug- #{text}"
  end

  def playable_now? card
    return false unless card.plays_after?(@top_card)


    if @game_state > 1
      return false unless card.is_war_playable?
      if @game_state == 3
        return false if card.figure != 'reverse' and !card.special_card?
      end
    end
    debug "playable: all passed"
    return true
  end

  def manage_order_by_card card, pass
    if card.figure == 'reverse' and pass == false
      notify "Player order reversed#{@double_play ? " twice" : ""}!"
      @players.reverse! unless @double_play
    elsif card.figure == 'skip' and pass == false
      if @double_play
        notify "#{@players[1]} and #{@players.fetch(2, @players[0])} were skipped!"
        @players.rotate! 3
      else
        notify "#{@players[1]} was skipped!"
        @players.rotate! 2
      end
    else
      @players.rotate!
    end
    @double_play = false
  end

  def player_card_play(player, card, play_second = false)
    debug "#{player} plays #{card}"
    if @players[0] == player
      if card.nil?
        notify "You do not have that card."
        return false
      end
      if playable_now? card
        #todo: fix the wd4 stuff
        if @already_picked == true && (@picked_card.to_s != card.to_s && @picked_card.to_s != 'wd4')
          notify 'Sorry, you have to play the card you picked.'
          return false
        end

        put_card_on_top card
        db_save_card card, player.to_s unless @casual == 1
        player.hand.destroy(card)

        if play_second == true
          debug 'we are actually trying to double play'
          #throw 'Hey, these cards are not the same!' unless card.to_s == second.to_s
          card = @players[0].hand.find_card card.to_s
          unless card.nil?
            @double_play = true
            notify '[Playing two cards]'
            put_card_on_top card
            db_save_card card, player.to_s unless @casual == 1
            player.hand.destroy(card)
          end
        end

        #notify "#{player} played #{card}!"

        check_for_number_of_cards_left player

        if player_with_no_cards_exists?
          finish_game
        else
          next_turn
        end
        return true
      else
        notify "Sorry #{player}, that card doesn't play."
        card.set_wild_color :wild
        false
      end
    else
      notify "It's not your turn."
      card.set_wild_color :wild
      false
    end

  end

  def player_with_no_cards_exists?
    @players.each { |p|
      return true if p.hand.size == 0
    }
    return false
  end

  def finish_game
    @game_state = 0
    give_cards_to_player @players[1], @stacked_cards if @stacked_cards > 0

    @total_score = @players.map { |p| p.hand.value }.inject(:+) #tally up points

    #min score per game
    @total_score = [@total_score, 30].max

    db_update_after_game_ended unless @casual == 1
    player_stats = UnoRankModel[@players[0].to_s]

    notify "#{@players[0]} gains #{@total_score} points. For a total of #{player_stats.total_score}, and a total of #{player_stats.games} games played."
    clean_up_end_game
  end

  def end_game(nick) #todo
    @game.end = Time.now.strftime("%F %T")
    @game.save
  end

  def check_for_number_of_cards_left player
    if player.hand.length == 1
      notify "04U09N12O08! #{player} has just one card left!"
    elsif player.hand.length == 3
      notify "#{player} has only 7three cards left!"
    end
  end

  def db_save_card card, player, received = 0
    unless @casual == 1
      dbcard = UnoTurnModel.create(
          :card => card.to_s,
          :figure => card.normalize_figure,
          :color => card.normalize_color,
          :player => player.to_s,
          :received => received,
          :time => Time.now.strftime("%F %T"),
          :game => @game.ID
      )
      dbcard.save
    end
  end

  def db_create_game
    unless @casual == 1
      @game = UnoGameModel.create(
          :start => Time.now.strftime("%F %T"),
          :created_by => @creator
      )
      @game.save
    end
  end

  def db_update_after_game_ended
    unless @casual == 1
      @game.points = @total_score

      @game.winner = @players[0]
      @game.end = Time.now.strftime("%F %T")
      @game.players = @players.size

      db_update_player_rank


      players_game_no = UNODB[:uno].where(:nick => @players[0].to_s).first[:games]
      @game.game = players_game_no + 1
      @game.save
    end
  end

  def db_update_player_rank
    unless @casual == 1
      @players.each { |p|
        player_record = UnoRankModel[p.to_s]

        if player_record.nil?
          player_record = UnoRankModel.create(:nick => p.to_s)
        end

        player_record.games += 1
        if p == @players[0]
          @game.total_score = player_record.total_score
          player_record.wins += 1
          player_record.total_score += @total_score
        end

        player_record.save
      }
    end
  end

  def db_player_joins player
    unless @casual == 1
      action = UnoActionModel.create(
          :game => @game.ID,
          :action => 0,
          :player => player,
          :subject => player
      )
      puts action.to_s
      action.save
    end
  end

  def db_stop player
    unless @casual == 1
      action = UnoActionModel.create(
          :game => @game.ID,
          :action => 2,
          :player => player,
          :subject => player
      )
      action.save
    end
  end

end

class IrcUnoGame < UnoGame
  attr_accessor :irc
  attr_accessor :plugin

  def notify text
    @semaphore.synchronize {
      @irc.Channel('#kx').send text
    }
  end

  def notify_player p, text
    @semaphore.synchronize {
      @irc.User(p.nick).notice text
    }
  end

  def clean_up_end_game
    @plugin.upload_db
    @plugin.end_game
  end

end
=begin
g = UnoGame.new
p1 = UnoPlayer.new('a')
p2 = UnoPlayer.new('b')
g.add_player(p1)
g.add_player(p2)
g.start_game
puts g.inspect
puts '---'
g.players.each {|p|
  puts "#{p}'s cards: #{p.hand}"
}
g.player_card_play(p1,p1.hand[0])
=end
# #todo: game cancel -> actions

require './plugins/uno/uno_card_stack.rb'
require './plugins/uno/uno_player.rb'
require 'thread'

# game states: 0 OFF, 1 ON, 2 WAR, 3WARWD

require_relative 'interfaces/notifier'
require_relative 'interfaces/renderer'
require_relative 'interfaces/repository'

class UnoGame
  prepend ThreadSafeDefault
  attr_reader :players, :top_card, :game_state, :creator
  attr_reader :card_stack
  attr_reader :starting_stack, :first_player
  attr_accessor :notifier, :renderer, :repository

  def initialize(creator, casual = 0, notifier = nil, renderer = nil, repository = nil)
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
    @notifier = notifier || Uno::ConsoleNotifier.new
    @renderer = renderer || Uno::TextRenderer.new
    @repository = repository || (@casual == 1 ? Uno::NullRepository.new : Uno::SqliteRepository.new)
    db_create_game
  end

  def started?
    @game_state > 0
  end

  def start_game(stack = nil, first_player = nil)
    if @players.length < 2
      notify 'You need at least two players to start a game.'
      return
    end
    if started?
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
      @first_player = @players[0].identity.id
    else
      if @players[0].matches?(first_player)
        puts 'rotate1'
        rotated = true
        @players.rotate! # other player has to start with same hand
      end
    end

    deal_cards_to_players

    db_save_card top_card, nil

    @start = Time.now.strftime('%F %T')
    # @players.rotate! if rotated
    # puts "rotate2" if rotated
    next_turn
  end

  def prepare_card_stack
    loop do
      @card_stack.shuffle!
      break unless @card_stack[0].is_offensive?
    end
  end

  def put_card_on_top(card)
    accord_game_state_to_card_played card
    @locked = true
    @played_cards << card
    @top_card = card
  end

  def accord_game_state_to_card_played(card)
    @stacked_cards += card.offensive_value

    if @game_state < card.offensive_value # this is stupid code but whatever
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

  def next_turn(pass = false)
    manage_order_by_card @top_card, pass
    notify_top_card pass
    show_player_cards @players[0]
    @already_picked = false
  end

  def show_player_cards(player)
    notify_player player, @renderer.render_hand(player.hand)
  end

  def show_card_count
    notify "Card count: #{@players.map { |p| p.to_s + ' ' + p.hand.size.to_s }.join(', ')}"
  end

  def deal_cards_to_players
    @players.each do |p|
      deal_cards_to_player p
    end
  end

  def deal_cards_to_player(p)
    p.hand << @card_stack.pick(7)
    p.hand.each do |card|
      db_save_card card, p.to_s, 1
    end
    p.hand.sort! { |a, b| a.to_s <=> b.to_s }
  end

  def check_for_empty_stack(n = 0)
    if @card_stack.length <= n
      notify 'Reshuffling discard pile.'
      @played_cards.each(&:unset_wild_color)
      @card_stack << @played_cards
      @played_cards = CardStack.new
      @card_stack.shuffle!
    end
  end

  def give_cards_to_player(p, n)
    check_for_empty_stack(n)
    @already_picked = true
    picked = @card_stack.pick(n)
    picked.each do |card|
      db_save_card card, p.to_s, 1
    end

    notify_player(p, "You draw #{n} card#{n > 1 ? 's' : ''}: #{@renderer.render_hand(picked)}")
    p.hand << picked

    p.hand.sort! { |a, b| a.to_s <=> b.to_s }

    @game_state = 1
    @stacked_cards = 0
    picked
  end

  def turn_pass
    if @already_picked == false
      if @stacked_cards == 0
        notify 'You have to pick a card first.'
        return
      else
        give_cards_to_player @players[0], @stacked_cards
      end
    end
    next_turn true
  end

  def pick_single
    if (@already_picked == false) && (@stacked_cards == 0)
      @already_picked = true
      notify "#{@players[0]} draws a card."
      @picked_card = (give_cards_to_player @players[0], 1)[0]
    else
      notify "Sorry #{@players[0]}, you can't pick now."
    end
  end

  def card_played(card)
    @locked = true
    @played_cards << card
  end

  def notify_player_turn(p)
    notify "Hey #{p} it's your turn!"
  end

  def add_player(p)
    if @locked == false
      @players.push p
      @players.shuffle!
      db_player_joins p.to_s unless @casual == 1
      notify "#{p} joins the game"
    else
      notify "Sorry, it's not possible to join this game anymore."
    end
  end

  def remove_player(p)
    @players.delete! p
    stop_game p.to_s if @players.empty?
  end

  def stop_game(nick)
    db_stop nick unless @casual == 1
  end

  def rename_player(old_nick, new_nick)
    player = @players.detect { |p| p.matches?(old_nick) }
    player.change_nick(new_nick) if player
  end

  def notify_order
    notify 'Current player order is: ' + @players.join(' ')
  end

  def notify_top_card(passes = false)
    pass_string = passes == true ? "#{@players[-1]} passes. " : ''
    notify "#{pass_string}#{@players[0]}'s turn. Top card: #{@renderer.render_card(@top_card)}"
  end

  def notify(text)
    @notifier.notify_game(text)
  end

  def clean_up_end_game; end

  def notify_player(p, text)
    @notifier.notify_player(p.to_s, text)
  end

  def debug(text)
    @notifier.debug(text)
  end

  def playable_now?(card)
    return false unless card.plays_after?(@top_card)

    if @game_state > 1
      return false unless card.is_war_playable?
      if @game_state == 3
        return false if (card.figure != 'reverse') && !card.special_card?
      end
    end
    debug 'playable: all passed'
    true
  end

  def manage_order_by_card(card, pass)
    if (card.figure == 'reverse') && (pass == false)
      notify "Player order reversed#{@double_play ? ' twice' : ''}!"
      @players.reverse! unless @double_play
    elsif (card.figure == 'skip') && (pass == false)
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
        notify 'You do not have that card.'
        return false
      end
      if playable_now? card
        # TODO: fix the wd4 stuff
        if @already_picked == true && (@picked_card.to_s != card.to_s && @picked_card.to_s != 'wd4')
          notify 'Sorry, you have to play the card you picked.'
          return false
        end

        put_card_on_top card
        db_save_card card, player.to_s unless @casual == 1
        player.hand.destroy(card)

        if play_second == true
          if @already_picked == true
            notify "Sorry, you can't play the picked card twice."
            return false
          end
          debug 'we are actually trying to double play'
          # throw 'Hey, these cards are not the same!' unless card.to_s == second.to_s
          card = @players[0].hand.find_card card.to_s
          unless card.nil?
            @double_play = true
            notify '[Playing two cards]'
            put_card_on_top card
            db_save_card card, player.to_s unless @casual == 1
            player.hand.destroy(card)
          end
        end

        # notify "#{player} played #{card}!"

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
    @players.each do |p|
      return true if p.hand.empty?
    end
    false
  end

  def finish_game
    @game_state = 0
    give_cards_to_player @players[1], @stacked_cards if @stacked_cards > 0

    @total_score = @players.map { |p| p.hand.value }.inject(:+) # tally up points

    # min score per game
    @total_score = [@total_score, 30].max

    winning_string = "#{@players[0]} gains #{@total_score} points."
    if @casual != 1
      db_update_after_game_ended
      player_stats = @repository.get_player_stats(@players[0].to_s)
      winning_string += " For a total of #{player_stats[:total_score]}, and a total of #{player_stats[:games]} games played."
    end
    notify winning_string
    clean_up_end_game
  end

  def end_game(_nick) # todo
    @game.end = Time.now.strftime('%F %T')
    @game.save
  end

  def check_for_number_of_cards_left(player)
    if player.hand.length == 1
      notify "04U09N12O08! #{player} has just one card left!"
    elsif player.hand.length == 3
      notify "#{player} has only 7three cards left!"
    end
  end

  def db_save_card(card, player, received = 0)
    @repository.save_card_action(@game_id, card, player, received > 0)
  end

  def db_create_game
    @game_id = @repository.create_game(@creator, Time.now.strftime('%F %T'))
  end

  def db_update_after_game_ended
    unless @casual == 1
      db_update_player_rank
      
      winner_stats = @repository.get_player_stats(@players[0].to_s)
      @repository.update_game_ended(
        @game_id,
        @players[0].to_s,
        Time.now.strftime('%F %T'),
        @total_score,
        @players.size,
        winner_stats[:games]
      )
    end
  end

  def db_update_player_rank
    unless @casual == 1
      @players.each do |p|
        won = (p == @players[0])
        points = won ? @total_score : 0
        @repository.update_player_stats(p.to_s, won, points)
      end
    end
  end

  def db_player_joins(player)
    @repository.record_player_join(@game_id, player)
    debug "Player #{player} joined game #{@game_id}"
  end

  def db_stop(player)
    @repository.record_game_stopped(@game_id, player)
  end
end

class IrcUnoGame < UnoGame
  attr_accessor :plugin

  def initialize(creator, casual = 0, irc = nil, channel = '#kx')
    require_relative 'interfaces/irc_notifier'
    notifier = Uno::IrcNotifier.new(irc, channel) if irc
    renderer = Uno::IrcRenderer.new
    repository = casual == 1 ? Uno::NullRepository.new : Uno::SqliteRepository.new
    super(creator, casual, notifier, renderer, repository)
  end

  def clean_up_end_game
    @plugin.upload_db unless @casual
    @plugin.end_game
  end
end
# g = UnoGame.new
# p1 = UnoPlayer.new('a')
# p2 = UnoPlayer.new('b')
# g.add_player(p1)
# g.add_player(p2)
# g.start_game
# puts g.inspect
# puts '---'
# g.players.each {|p|
#   puts "#{p}'s cards: #{p.hand}"
# }
# g.player_card_play(p1,p1.hand[0])

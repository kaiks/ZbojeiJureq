require 'monitor'
require 'jedna'
require 'jedna/interfaces/irc_notifier'
require './plugins/uno/uno_db.rb'
require './config.rb'

# IRC-specific UnoGame implementation with thread safety
class IrcUnoGame < Jedna::Game
  include ThreadSafeGame

  attr_reader :channel
  
  def initialize(creator, casual = 0, irc = nil, channel = '#kx', plugin = nil)
    @channel = channel
    @ranked = casual != 1
    notifier = Jedna::IrcNotifier.new(irc, channel) if irc
    renderer = Jedna::IrcRenderer.new
    repository = if casual == 1
                   Jedna::NullRepository.new
                 else
                   Jedna::SqliteRepository.new(
                     game_model: UnoGameModel,
                     turn_model: UnoTurnModel,
                     action_model: UnoActionModel,
                     rank_model: UnoRankModel
                   )
                 end
    super(creator, casual, notifier, renderer, repository)
    
    # Set up the hook for game ended
    on_game_ended do
      plugin.game_ended(channel, self, upload: ranked?) if plugin
    end
  end

  def ranked?
    @ranked
  end
end

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
  match /^pl ([A-Za-z0-9+]{1,8})$/, group: :uno, method: :play, use_prefix: false


  match /^tu$/,           group: :uno, method: :cd, use_prefix: false

  match /uno quit$/,     group: :uno, method: :stop
  match /uno test$/,     group: :uno, method: :testing

  match /uno casual/,   group: :uno, method: :start_casual
  match /uno reload/,   group: :uno, method: :reload
  match /uno stop/,     group: :uno, method: :stop
  match /uno top(?: ([1-5]))?$/, group: :uno, method: :top
  match /uno debug (.*)/,    group: :uno, method: :debug
  match /uno score$/,   group: :uno, method: :own_score
  match /uno score ([A-Za-z0-9_\-]+)/, group: :uno, method: :score

  match /uno$/,         group: :uno, method: :start
  match /uno/,          group: :uno, method: :help

  def initialize(*args)
    super
    @games = {}
    @game_histories = {}
    @testing_channels = Hash.new(false)
    @games_monitor = Monitor.new
  end

  def debug(m, text)
    return unless m.user.has_admin_access?
    m.reply eval(text)
  end

  def testing(m)
    with_channel(m) do |channel|
      @testing_channels[channel] = !@testing_channels[channel]
      m.reply "Ok. Now set to #{@testing_channels[channel]}"
    end
  end

  def ca(m)
    with_game(m) do |game|
      current_player = game.players.find { |p| p.matches?(m.user.nick) }
      game.show_player_cards(current_player) if current_player
      game.show_card_count if game.game_state > 0
    end
  end

  def cd(m)
    with_game(m) do |game|
      game.notify_top_card if game.players.any? { |p| p.matches?(m.user.nick) }
    end
  end

  def get_stack_size(m)
    with_game(m) do |game|
      m.reply "#{game.card_stack.length} cards left in the stack" if game.started?
    end
  end


  def deal(m)
    with_game(m, notify: true) do |game, channel|
      if game.creator.to_s == m.user.nick
        if @testing_channels[channel]
          if @game_histories[channel].nil?
            game.start_game
            if game.started?
              @game_histories[channel] = UnoGameHistory.new(game.starting_stack, game.first_player)
            end
          else
            history = @game_histories.delete(channel)
            game.start_game history.stack, history.first_player
          end
        else
          game.start_game
        end
      elsif game.started?
        m.reply 'Cards have already been dealt.'
      else
        m.reply "#{game.creator} needs to deal"
      end
    end
  end

  def join(m)
    with_game(m) do |game|
      join_game(game, m)
    end
  end

  def order(m)
    with_game(m) do |game|
      players_ordered = game.players.map(&:to_s).join(' ')
      game.notify "Current order: #{players_ordered}"
    end
  end

  def pass(m)
    with_game(m) do |game|
      game.turn_pass if current_player?(game, m.user.nick)
    end
  end

  def pick(m)
    with_game(m) do |game|
      game.pick_single if current_player?(game, m.user.nick)
    end
  end

  def is_a_double_card_string? text
    length = text.length
    length > 3 && length.even? &&
      (text[0..(length / 2 - 1)] == text[(length / 2)..length]) &&
      text[1] != 'd' #even length, not a wd4
  end

  def play(m)
    with_game(m) do |game|
      next unless current_player?(game, m.user.nick)

      player = game.players[0]
      proposed_card_text = m.message.split[1].downcase
      card_text = proposed_card_text
      card = nil
      if is_a_double_card_string?(proposed_card_text)
        card_text = proposed_card_text[0..(proposed_card_text.length / 2 - 1)]
      end

      if card_text.match?(/\Aw[rgby]\z/)
        card = player.hand.reverse.find_card('w')
        card.set_wild_color Jedna.expand_color(card_text[1]) unless card.nil?
      elsif card_text.match?(/\Awd4[rgby]\z/)
        card = player.hand.reverse.find_card('wd4')
        card.set_wild_color Jedna.expand_color(card_text[3]) unless card.nil?
      elsif card_text.match?(/\A[^w]+\z/)
        card = player.hand.reverse.find_card(card_text)
      end
      game.player_card_play(player, card, is_a_double_card_string?(proposed_card_text))
      player.hand.reset_wilds
    end
  end

  def start(m)
    start_game(m, casual: false)
  end

  def start_casual(m)
    start_game(m, casual: true)
  end

  def stop(m)
    with_game(m, notify: true) do |game, channel|
      game.stop_game m.user.nick
      @games.delete(channel)
      @game_histories.delete(channel)
      m.reply 'Uno game has been stopped.'
      upload_db if game.ranked?
    end
  end

  def top(m, n = 5)
    counter = 0
    n = n ? n.to_i : 5

    m.reply '   ' + "nick".ljust(20) + 'points  games  average  wins  winrate - full list: http://uno.kaiks.eu '
    #SELECT *, ROUND(CAST(total_score AS FLOAT)/CAST(games AS FLOAT),2) sr FROM uno WHERE nick LIKE ' $+ %safe_nick $+ ' AND games >= 2 ORDER BY %by %ord LIMIT %count
    #UNODB[:uno].where('games > 2').select_append('ROUND(CAST(total_score as FLOAT)/CAST(games AS FLOAT,2)').order(Sequel.desc(5)).limit(n).each { |row|
    UNODB['SELECT *, ROUND(CAST(total_score AS FLOAT)/CAST(games AS FLOAT),2) FROM uno WHERE games >= 10 ORDER BY 5 DESC LIMIT ?', n].each { |row|
      counter += 1
      values = row.values.map { |v| v.is_a?(BigDecimal) ? v.to_s("F") : v.to_s }
      if values[0].to_s.length > 0
        m.reply "#{counter}. #{values[0].ljust(19)} #{values[1].ljust(7)} #{values[2].ljust(6)} #{values[4].ljust(8)} #{values[3].ljust(5)} #{(values[3].to_f*100.0/values[2].to_f).round(2).to_s.ljust(5, "0")}%"
      end
    }
  end

  def game_ended(channel_name, game, upload:)
    upload_db if upload
    @games_monitor.synchronize do
      channel = normalize_channel(channel_name)
      @games.delete(channel) if @games[channel].equal?(game)
    end
    @bot.send_to_ftp './uno.db', '', 'unodb'
  end

  def help(m)
    m.reply '.uno -> .deal / .uno stop / .uno top / ... uno help available at https://zboje.kaiks.eu/docs/index.html#uno-plugin'
  end

  def winrate(games, wins)
    if games.zero?
      0.0
    else
      (100.to_f * wins / games).round(2)
    end
  end

  def score(m, user)
    rank = UnoRankModel[user]
    unless rank
      m.reply "No uno score found for #{user}."
      return
    end

    games = rank.games.to_i
    wins = rank.wins.to_i
    total_score = rank.total_score.to_i
    average = games.zero? ? 0.0 : (total_score.to_f / games).round(2)

    m.reply "#{rank.nick}: #{average} avg #{total_score} pts #{games} games #{wins} wins #{winrate(games, wins)}% winrate"
  end

  def own_score(m)
    score(m, m.user.nick)
  end

  def reload(m)
    original_verbose = $VERBOSE
    gem_root = Gem.loaded_specs.fetch('jedna').full_gem_path
    source_root = File.join(gem_root, 'lib', 'jedna') + File::SEPARATOR
    loaded_sources = $LOADED_FEATURES.select { |path| path.start_with?(source_root) }

    $VERBOSE = nil
    loaded_sources.each { |path| load path }
    m.reply 'Uno reloaded.'
  ensure
    $VERBOSE = original_verbose
  end

  def upload_db
    #todo: ftp
    @bot.upload_to_dropbox './uno.db'
    @bot.send_to_ftp('./uno.db')
  end

  private

  def start_game(m, casual:)
    with_channel(m) do |channel|
      if @games[channel]
        m.reply 'An uno game is already being played in this channel.'
        next
      end

      game = IrcUnoGame.new(m.user.nick, casual ? 1 : 0, @bot, m.channel.name, self)
      @games[channel] = game
      casual_text = casual ? 'casual ' : ''
      m.reply "Ok, created #{casual_text}04U09N12O08! game on #{m.channel}, say 'jo' to join in"
      join_game(game, m)
    end
  end

  def join_game(game, m)
    if game.players.none? { |player| player.matches?(m.user.nick) }
      game.add_player Jedna::Player.new(m.user.nick)
    else
      m.reply "You are already in the game, #{m.user.nick}."
    end
  end

  def current_player?(game, nick)
    game.players.first&.matches?(nick)
  end

  def with_channel(m)
    channel = m.channel&.name
    unless channel
      m.reply 'Uno games can only be played in a channel.'
      return
    end

    @games_monitor.synchronize { yield normalize_channel(channel) }
  end

  def with_game(m, notify: false)
    with_channel(m) do |channel|
      game = @games[channel]
      if game
        yield game, channel
      elsif notify
        m.reply 'No uno game is running in this channel.'
      end
    end
  end

  def normalize_channel(channel)
    channel.to_s.downcase
  end
end

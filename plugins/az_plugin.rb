require './plugins/az/az_interface.rb'

class AzPlugin
  include Cinch::Plugin

  self.prefix = '.'
  match /az stop/, group: :az, method: :stop
  match /az help/, group: :az, method: :help
  match /az hint/, group: :az, method: :hint
  match /az ez/,   group: :az, method: :start_ez
  match /az top\z/, group: :az, method: :top
  match /az top ([1-5]\z)/, group: :az, method: :top
  match /az$/, group: :az, method: :start
  match /^([A-z]{1,45})$/, use_prefix: false, group: :az, method: :guess


  def initialize(*args)
    super
    @games = {}
    @default_dictionary = AzDictionary.new('en_dict.txt')
    @easy_dictionary    = AzDictionary.new('ez.txt')
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
      @games[m.channel] = AzInterface.new(m.channel, m.user.to_s, @bot.db, @default_dictionary)
    else
      m.reply @games[m.channel].range
    end
  end

  def start_ez(m)
    if @games[m.channel].nil?
      @games[m.channel] = AzInterface.new(m.channel, m.user.to_s, @bot.db, @default_dictionary, @easy_dictionary)
    else
      m.reply @games[m.channel].range
    end
  end

  def guess(m, word)
    return if @games[m.channel].nil?
    @games[m.channel].try(word, m.user.to_s)
    @games[m.channel] = nil if @games[m.channel].won?
  end

  def help(m)
    m.reply 'az help available at https://zboje.kaiks.eu/docs/index.html#az-plugin'
  end

  def top(m, n = 5)
    counter = 0

    n = [n.to_i, 5].min

    nick_total_games = @bot.db[:az_guess].group(:nick).select_group(:nick).select_append(Sequel.function(:count, :game).distinct)

    m.reply '   ' + 'nick'.ljust(12) + 'points  games average wins - full list: http://kaiks.eu/az.php'
    @bot.db[:az_game].group(:finished_by).select_group(:finished_by).select_append(Sequel.function(:sum, :points)).select_append(Sequel.function(:count, :id)).order(Sequel.desc(2)).limit(n).each { |row|
      counter += 1
      values = row.values
      nick = values[0].to_s
      total_score = values[1]
      total_wins = values[2]
      total_games = nick_total_games.where(nick: nick).first[:"count(DISTINCT `game`)"]
      average = (total_score.to_f/total_games.to_f).round(2)

      next if values[0].to_s.empty?
      m.reply "#{counter}. #{nick.ljust(12)} #{total_score.to_s.ljust(6)} #{total_games.to_s.ljust(5)} #{average.to_s.ljust(7)} #{total_wins.to_s.ljust(7)}"
    }
  end
end

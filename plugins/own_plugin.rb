require 'time'

module OwnConfig
  KICKS = 5
  TIME_LIMIT = 300
end

class OwnRecord < Sequel::Model(:own)
  def active?
    own_stage.to_i > 0
  end

  def to_s
    "#{nick} was owned #{owned_times} times and owned somebody #{owning_times} times"
  end

  def time
    return Time.at(0) if last_owned_time.nil? || last_owned_time.empty?

    Time.parse(last_owned_time)
  rescue ArgumentError
    Time.at(0)
  end
end

class OwnPlugin
  include Cinch::Plugin
  self.prefix = '.'
  match /own ([^\s]{2,15})/,        group: :own_command, method: :own
  match /unown ([^\s]{2,15})/,      group: :own_command, method: :unown

  match /own_stats ([^\s]{2,15})/,  group: :own_command, method: :stats
  match /own_stats/,                group: :own_command, method: :stats
  match /own(.*)/,                  group: :own_command, method: :own_help

  listen_to :join, method: :on_join

  def initialize(*args)
    super
    puts "Own plugin loaded."
  end

  def on_join(m)
    user = OwnRecord.where(nick: m.user.nick).first

    return if user.nil? || user.own_stage.nil?
    
    if user.own_stage > 1
      user.own_stage -= 1
      m.channel.kick(m.user, "##{OwnConfig::KICKS + 1 - user.own_stage}")
      user.save
    elsif user.own_stage == 1
      user.own_stage -= 1
      user.save
      m.channel.send "#{m.user.nick} was pwnz0r3d by #{user.last_owned_by} & #{bot.nick}!"
    end
  end

  def own(m, nick)
    return unless m.user.level > 0

    owner = OwnRecord.find_or_create(nick: m.user.nick)
    owned = OwnRecord.find_or_create(nick: nick)

    if (Time.now - owned.time).to_i <= OwnConfig::TIME_LIMIT
      m.reply "Daj mu juz spokoj #{m.user.nick} :("
      return
    end

    OwnRecord.db.transaction do
      owner.update(owning_times: owner.owning_times.to_i + 1)
      owned.update(
        owned_times: owned.owned_times.to_i + 1,
        last_owned_time: Time.now,
        last_owned_by: m.user.nick,
        own_stage: OwnConfig::KICKS
      )
    end

    user = m.channel.get_user(nick)
    m.channel.kick(user, '#1') if user
  end


  def unown(m, nick)
    return unless m.user.nick == nick || m.user.level > 0
    owned = OwnRecord.where(nick: nick).first
    unless owned
      m.reply "#{nick} is not currently owned."
      return
    end

    owned.own_stage = 0
    owned.save
    m.reply "Done."
  end


  def stats(m, nick = nil)
    nick ||= m.user.nick
    user = OwnRecord.where(nick: nick).first
    if user.nil?
      m.reply "Sorry, I've got no stats for #{nick}."
    else
      m.reply user.to_s
    end
  end

  def own_help(m, arg)
    m.channel.send 'To own a nick, type .own [nick]. To unown a nick, type .unown [nick].'
    m.channel.send 'To display owning stats, type .own_stats'
  end
end

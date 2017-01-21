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
    last_owned_time ||= (Date.today - 1337).to_s
    Time.parse(last_owned_time)
  end


end

class OwnPlugin
  include Cinch::Plugin
  self.prefix = '.'
  match /own ([^\s]{2,15})/,        group: :own_command, method: :own
  match /unown ([^\s]{2,15})/,      group: :own_command, method: :unown

  match /own_stats ([^\s]{2,15})/,  group: :own_command, method: :stats
  match /own_stats/,                group: :own_command, method: :stats
  match /own(.*)/,                group: :own_command, method: :own_help

  listen_to :join, method: :on_join

  def initialize(*args)
    super
    puts "Own plugin loaded."
  end

  def on_join(m)
    #m.channel.send "#{m.user.nick} joined."
    user = OwnRecord.where(:nick => m.user.nick).first

    unless user.nil?
      puts user.own_stage
      if user.own_stage > 1
        user.own_stage -= 1
        m.channel.kick(m.user, "##{OwnConfig::KICKS+1-user.own_stage}")
        user.save
      elsif user.own_stage == 1
        user.own_stage -= 1
        user.save
        m.channel.send "#{m.user.nick} was pwnz0r3d by #{user.last_owned_by} & #{bot.nick}!"
      end
    end
  end



  def own(m, nick)
    if m.user.level > 0
      owner = OwnRecord.where(:nick => m.user.nick).first


      if owner.nil?
        OwnRecord.create( :nick => nick,
                          :owning_times => 1
        )
      else
        owner.owning_times += 1
        owner.save
      end

      owned = OwnRecord.where(:nick => nick).first

      if owned.nil?
        OwnRecord.create( :nick => nick,
                            :last_owned_time => Time.now,
                            :last_owned_by => m.user.nick,
                            :own_stage => OwnConfig::KICKS,
                            :owned_times => 1
        )
      else
        if (Time.now - owned.time).to_i > OwnConfig::TIME_LIMIT
          owned.owned_times += 1
          owned.last_owned_time = Time.now
          owned.own_stage = OwnConfig::KICKS
          owned.last_owned_by = m.user.nick
          owned.save
          user = m.channel.get_user(nick)
          m.channel.kick(user, "#1")
        else
          owner.owning_times -= 1
          owner.save
          m.reply "Daj mu juz spokoj #{m.user.nick} :("
        end
      end




    end
  end


    def unown(m, nick)
      if (m.user.nick == nick || m.user.level > 0)
        owned = OwnRecord.where(:nick => nick).first
        owned.own_stage = 0
        owned.save
        m.reply "Done."
      end
    end


  def stats(m, nick = nil)
    nick ||= m.user.nick
    user = OwnRecord.where(:nick => nick).first
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
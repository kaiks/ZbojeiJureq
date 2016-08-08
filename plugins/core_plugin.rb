require './config.rb'

class CorePlugin
  include Cinch::Plugin

  self.prefix = '.'


  def initialize(*args)
    super
  end

  listen_to :kick,    :method => :rejoin

  def rejoin(m)
    return unless User(m.params[1]) == @bot
    sleep(1)
    m.channel.join(m.channel.key)
  end

  timer CONFIG['nick_check_delay'], method: :nick_check
  timer CONFIG['maindb_upload_delay'], method: :upload_general_db

  def upload_general_db
    @bot.upload_to_dropbox './ZbojeiJureq.db'
  end

  def nick_check
    @bot.nick = CONFIG['nick'] if @bot.nick != CONFIG['nick']
  end


end
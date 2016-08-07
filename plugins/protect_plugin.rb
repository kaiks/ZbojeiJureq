class ProtectPlugin
  include Cinch::Plugin

  self.prefix = '.'

  listen_to :deop,    :method => :unban
  listen_to :ban,     :method => :ban
  listen_to :join,    :method => :join



  def initialize(*args)
    super
  end

  def message(m)
    m.reply "This is a sample plugin"
  end


  def help(m)
    m.channel.send 'Template plugin help message'
  end

  def ban(m, ban)
    return if m.user.has_admin_access?
    m.channel.unban(ban.mask)
  end



  def join(m)
    return if m.user == bot
    sleep 0.5 # In case Chanserv/etc. has already given the user a mode.
    return if m.channel.opped? m.user # Return if user was already given a mode via chanserv, etc.
    return unless m.user.authorized?

    if m.user.op?
      m.channel.op(m.user)
    elsif m.user.voice?
      m.channel.voice(m.user)
    end
  end

end
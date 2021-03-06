class ProtectPlugin
  include Cinch::Plugin

  self.prefix = '.'

  listen_to :deop,    method: :unban
  listen_to :ban,     method: :ban
  listen_to :join,    method: :join

  match /op\z/, method: :op_self
  match /op ([^\s]+)\z/, method: :op

  match /kick ([^\s]+)\z/, method: :kick_user

  match /v\z/, method: :voice_self
  match /v (#[^\s]+)\z/, method: :voice_channel, group: :voice
  match /v ([^\s]+)\z/, method: :voice_user, group: :voice


  def initialize(*args)
    super
  end

  def op_self(m)
    return unless m.user.has_admin_access?
    m.channel.op(m.user)
  end

  def op(m, user)
    return unless m.user.has_admin_access?
    m.channel.op(m.channel.get_user(user))
  end

  def voice_self(m)
    return unless m.user.has_admin_access?
    m.channel.voice(m.user)
  end

  def voice_channel(m, channel)
    Channel(channel).voice(m.user)
  end

  def voice_user(m, user)
    m.channel.voice(m.channel.get_user(user))
  end

  def kick(m, user)
    return unless m.user.has_admin_access?
    m.channel.kick(m.channel.get_user(user))
  end

  def ban(m, ban)
    return unless m.user.has_admin_access?
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
class ObsoletePlugin
  include Cinch::Plugin

  self.prefix = '!'


  match /(w)$/,           method: :message
  match /(noter).*$/,     method: :message, group: :note
  match /(note).*/,       method: :message, group: :note
  match /(uno).*/,        method: :message
  match /(btc)/,          method: :message
  match /^(timer).*/,     method: :message, use_prefix: false




  def initialize(*args)
    super
  end

  def message(m, message)
    m.reply "Command no longer in use. Try .#{message.split[0]}"
  end


end
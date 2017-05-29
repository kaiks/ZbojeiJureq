class TemplatePlugin
  include Cinch::Plugin

  self.prefix = '.'


  match /template/,         method: :message
  match /template(\s[^\s].*)/, method: :help




  def initialize(*args)
    super
  end

  def message(m)
    m.reply "This is a sample plugin"
  end


  def help(m)
    m.channel.send 'Template plugin help message'
  end
end
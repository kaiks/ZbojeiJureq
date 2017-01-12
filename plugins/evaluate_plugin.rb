class EvaluatePlugin
  include Cinch::Plugin
  self.prefix = '.'
  match /eval (.+)/, method: :evaluate

  def evaluate(m, arg)
    if m.user.level == 100
      m.reply eval(arg)
    end
  end
end
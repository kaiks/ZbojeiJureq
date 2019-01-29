class EvaluatePlugin
  include Cinch::Plugin
  self.prefix = '.'
  match /eval (.+)/, method: :evaluate

  def evaluate(m, arg)
    return unless m.user.level == 100

    begin
      m.reply eval(arg)
    rescue StandardError => e
      m.reply e.message
    end
  end
end
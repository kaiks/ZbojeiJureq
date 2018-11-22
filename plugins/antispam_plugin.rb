require 'ruby-fann'

class AntispamPlugin
  MSG_CHANNEL = '#kx'
  CONFIDENCE_THRESHOLD = 0.9

  include Cinch::Plugin

  self.prefix = '.'

  match /(.*)/,  method: :verify, use_prefix: false

  def initialize(*args)
    load_ai
    super
  end

  def load_ai
    @ai = RubyFann::Standard.new(filename: "./plugins/antispam_plugin/spamdetector.net")
  end

  def translate_input_element(string)
    output = Array.new(10000,0)
    string.split('').each { |c| output[c.ord] += 1 if c.ord < 10000 }
    output
  end

  def spam?(current)
    formatted_input = translate_input_element(string)
    @ai.run(formatted_input) > CONFIDENCE_THRESHOLD
  end

  def verify(m, text)
    if spam?(text)
      m.channel.kick(m.user, "no spamerino")
    end
  end

end
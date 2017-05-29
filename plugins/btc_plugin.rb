require 'open-uri'

class BtcPlugin
  include Cinch::Plugin

  self.prefix = '.'


  match /btc/,         method: :btc
  #match /template(\s[^\s].*)/, method: :help




  def initialize(*args)
    super
  end

  def btc(m)
    m.reply (1.0/(open('https://blockchain.info/tobtc?currency=USD&value=1').read).to_f).to_s + ' USD'
  end

end
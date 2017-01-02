require 'money'
require 'money/bank/google_currency'

class CurrencyPlugin
  include Cinch::Plugin

  self.prefix = '.'


  match /e ([0-9]+\.?[0-9]*) ([A-Za-z]{3}) ([A-Za-z]{3})/,
        method: :exchange, group: :exchange_group
  match /e ([0-9]+\.?[0-9]*) ([A-Za-z]{3}) to ([A-Za-z]{3})/,
        method: :exchange, group: :exchange_group
  match /e$/, method: :help, group: :exchange_group
  match /e update/, method: :update_bank, group: :exchange_group
  match /e /, method: :help, group: :exchange_group
  timer 300,              :method => :updater




  def initialize(*args)
    super
    I18n.config.available_locales = :en
    update_bank
  end

  def updater
    update_bank if @last_update + 3600*4 < Time.now
  end

    def update_bank
      Money.default_bank = Money::Bank::GoogleCurrency.new
      @last_update = Time.now
    end

  def exchange(m, from_amount, from_currency, to_currency)
    from_amount_cents = from_amount.to_f*100
    money = Money.new(from_amount.to_f*100, from_currency)
    m.reply "#{from_amount} #{from_currency} = #{money.exchange_to(to_currency.to_sym).to_s} #{to_currency}"
  end


  def help(m)
    m.reply 'Money exchange: .e [FROM_AMOUNT] [FROM_CURRENCY] [TARGET_CURRENCY], e.g. .e 50 usd pln'
  end
end
require 'cinch'
require 'net/http'
require 'json'

class CurrencyPlugin
  include Cinch::Plugin

  self.prefix = '.'

  # Define command patterns
  match /e ([0-9]+\.?[0-9]*) ([A-Za-z]{3}) ([A-Za-z]{3})/, method: :exchange, group: :exchange_group
  match /e ([0-9]+\.?[0-9]*) ([A-Za-z]{3}) to ([A-Za-z]{3})/, method: :exchange, group: :exchange_group
  match /e$/, method: :help, group: :exchange_group
  match /e /, method: :help, group: :exchange_group

  def initialize(*args)
    super
    @host = 'api.frankfurter.app'
  end

  # Method to handle currency exchange commands
  def exchange(m, amount, from_currency, to_currency)
    from_currency = from_currency.upcase
    to_currency = to_currency.upcase

    begin
      uri = URI("https://#{@host}/latest?amount=#{amount}&from=#{from_currency}&to=#{to_currency}")
      response = Net::HTTP.get(uri)
      data = JSON.parse(response)

      if data['rates'] && data['rates'][to_currency]
        converted_amount = data['rates'][to_currency]
        m.reply "#{amount} #{from_currency} = #{converted_amount} #{to_currency}"
      else
        m.reply "Unable to perform conversion. Please check your currencies."
      end
    rescue StandardError => e
      m.reply "Error during exchange: #{e.message}"
    end
  end

  # Method to display help information
  def help(m)
    m.reply 'Money exchange: .e [AMOUNT] [FROM_CURRENCY] [TO_CURRENCY], e.g. .e 50 USD EUR'
  end
end

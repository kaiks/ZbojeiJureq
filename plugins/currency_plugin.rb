require 'money'
require 'money/bank/variable_exchange'
require 'net/http'
require 'json'

class CurrencyPlugin
  include Cinch::Plugin

  self.prefix = '.'

  # Define command patterns
  match /e ([0-9]+\.?[0-9]*) ([A-Za-z]{3}) ([A-Za-z]{3})/,
        method: :exchange, group: :exchange_group
  match /e ([0-9]+\.?[0-9]*) ([A-Za-z]{3}) to ([A-Za-z]{3})/,
        method: :exchange, group: :exchange_group
  match /e$/, method: :help, group: :exchange_group
  match /e update/, method: :update_bank, group: :exchange_group
  match /e /, method: :help, group: :exchange_group

  # Set a timer to periodically update exchange rates (e.g., every 5 minutes)
  timer 300, :method => :updater

  def initialize(*args)
    super
    I18n.config.available_locales = :en

    # Initialize the VariableExchange bank
    @bank = Money::Bank::VariableExchange.new
    @bank.add_rate("EUR", "EUR", 1.0) # Base currency

    # Set the default bank to the initialized VariableExchange bank
    Money.default_bank = @bank

    # Fetch and update exchange rates initially
    update_bank
  end

  # Method called by the timer to update rates if outdated
  def updater
    # Update if last update was more than 4 hours ago
    update_bank if @last_update.nil? || @last_update + 3600*4 < Time.now
  end

  # Fetch exchange rates from Frankfurter API and update the bank
  def update_bank(m = nil)
    uri = URI('https://api.frankfurter.app/latest?base=EUR')
    response = Net::HTTP.get(uri)
    data = JSON.parse(response)

    rates = data['rates']
    base_currency = data['base']

    # Clear existing rates except for the base currency
    @bank.rates.clear
    @bank.add_rate(base_currency, base_currency, 1.0)

    # Add fetched rates to the bank
    rates.each do |currency, rate|
      @bank.add_rate(base_currency, currency, rate)
      @bank.add_rate(currency, base_currency, 1.0 / rate)
    end

    # Optionally, handle cross rates if needed
    # For simplicity, this example only sets rates relative to the base currency

    @last_update = Time.now

    # Notify if this method was called via a user command
    m.reply "Exchange rates updated successfully." if m
  rescue StandardError => e
    puts "Failed to update exchange rates: #{e.message}"
    m.reply "Failed to update exchange rates: #{e.message}" if m
  end

  # Method to handle currency exchange commands
  def exchange(m, from_amount, from_currency, to_currency)
    from_currency = from_currency.upcase
    to_currency = to_currency.upcase

    begin
      # Create a Money object with the specified amount and currency
      money = Money.from_amount(from_amount.to_f, from_currency)

      # Perform the currency exchange
      converted = money.exchange_to(to_currency)

      # Reply with the result
      m.reply "#{from_amount} #{from_currency} = #{converted.format} #{to_currency}"
    rescue Money::Bank::UnknownRate => e
      m.reply "Exchange rate from #{from_currency} to #{to_currency} is not available."
    rescue StandardError => e
      m.reply "Error during exchange: #{e.message}"
    end
  end

  # Method to display help information
  def help(m)
    m.reply 'Money exchange: .e [FROM_AMOUNT] [FROM_CURRENCY] [TARGET_CURRENCY], e.g. .e 50 USD PLN'
  end
end

#dentaku https://github.com/rubysolo/dentaku
#todo: przecinki

require 'dentaku'
class ObliczPlugin
  include Cinch::Plugin

  self.prefix = ''


  match /^.oblicz set ([A-z]+) (([1-9]*)|(([1-9]*)\.([0-9]*)))\s*$/, method: :set, group: :oblicz
  match /^\.oblicz (.*)/, method: :oblicz, group: :oblicz
  match /^oblicz (.*)/, method: :oblicz, group: :oblicz
  match /oblicz/,         method: :help, group: :oblicz


  def factorial(n)
    (1..n).inject(:*)
  end

  def fib_memo(n, memo)
    memo[n] ||= fib_memo(n-1, memo) + fib_memo(n-2, memo)
  end

  def fib(n)
    raise "fib not defined for negative numbers" if n < 0
    fib_memo(n, [0, 1])
  end

  def initialize(*args)
    super
    @calculator = Dentaku::Calculator.new
    #
    #> c.add_function(:pow, :numeric, ->(mantissa, exponent) { mantissa ** exponent })
    @calculator.add_function(:rand, :numeric, ->(from,to) { rand(to-from+1)+from } )
    @calculator.add_function(:fac, :numeric, ->(n) { (1..n).inject(:*) } )
    @calculator.add_function(:fib, :numeric, ->(n) { fib(n) } )
  end


  def oblicz(m, tekst)
    tekst = tekst.gsub(',', '.') unless tekst =~ /[A-Za-z]/
    result = (@calculator.evaluate tekst).to_s
    m.reply eval result.gsub(/E([0-9]+)/,'*10**\1')
  end

  def set(m, variable, value)
    eval("@calculator.store(#{variable}: #{value})")
    m.reply "Ok. #{variable} = #{value}"
  end


  def help(m)
    m.channel.send 'Oblicz -> example: oblicz 2+3'
  end
end
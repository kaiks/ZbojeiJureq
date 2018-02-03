module Text
  BLACK = 3.chr + '1'
  DARK_BLUE = 3.chr + '2'
  DARK_GREEN = 3.chr + '3'
  RED = 3.chr + '4'
  DARK_RED = 3.chr + '5'
  PURPLE = 3.chr + '6'
  ORANGE = 3.chr + '7'
  YELLOW = 3.chr + '8'
  GREEN = 3.chr + '9'
  MARINE = 3.chr + '10'
  LIGHT_BLUE = 3.chr + '11'
  BLUE = 3.chr + '12'
  PINK = 3.chr + '13'
  DARK_GRAY = 3.chr + '14'
  GRAY = 3.chr + '15'

  def self.color(string, color)
    color + 0.chr + string.to_s + 3.chr
  end

  def self.bold(string)
    2.chr + string.to_s + 2.chr
  end
end
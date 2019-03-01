class AzDictionary
  attr_reader :size

  def initialize(path)
    @dictionary_array = IO.read(path).split
    @dictionary = Hash[@dictionary_array.map { |element| [element, 1] } ]
    @size = @dictionary_array.size
  end

  def word_at(number)
    @dictionary_array[number]
  end

  def random_word
    word_number = rand(@size)
    word_at(word_number)
  end

  def word_valid?(word)
    @dictionary.fetch(word, 0) == 1
  end

  def first_word
    word_at(0)
  end

  def last_word
    word_at(@size - 1)
  end
end

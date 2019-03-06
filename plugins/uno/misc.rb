

class Array
  # array exists and has nth element (1=array start) not null
  def exists_and_has(n)
    size >= n && !at(n - 1).nil?
  end
end

class NilClass
  def exists_and_has(_n)
    false
  end
end

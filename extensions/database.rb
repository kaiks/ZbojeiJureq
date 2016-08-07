DB = Sequel.connect('jdbc:sqlite:ZbojeiJureq.db')

module Cinch
  class Bot
    def db
      self.config.shared[:database]
    end
  end
end
DATABASE_DIRECTORY = File.expand_path('../db', __dir__).freeze

def sqlite_path(filename)
  File.join(DATABASE_DIRECTORY, filename)
end

def sqlite_load(filename)
  Sequel.sqlite(sqlite_path(filename))
end

DB = sqlite_load('ZbojeiJureq.db')

module Cinch
  class Bot
    def db
      self.config.shared[:database]
    end
  end
end

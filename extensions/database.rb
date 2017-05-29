def sqlite_load(filename)
  driver_prefix = if RUBY_PLATFORM == 'java'
                    'jdbc:sqlite:'
                  else
                    'sqlite://'
                  end
  Sequel.connect(driver_prefix + filename)
end

DB = sqlite_load('ZbojeiJureq.db')

module Cinch
  class Bot
    def db
      self.config.shared[:database]
    end
  end
end
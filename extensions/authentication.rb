#todo: naprawic blad zajmowania usera (???)

module Cinch

  class User
    attr_accessor :authentication

    def authorize_by_nick
      dataset = @bot.db[:user].where(:matchmethod => 0, :nick => self.nick)

      if dataset.count > 0
        access = dataset.join(:user_access, :id => :accesslevel).reverse_order(:level).first
        @authentication = access unless access[:level] < level
      end
    end

    def authorize_by_address
      query = @bot.db[:user].where(:matchmethod => 2).join(:user_access, :id => :accesslevel).reverse_order(:level)

      puts query.all.to_s
      query.all.each { |row|
        puts row[:address]
        puts mask.to_s
        puts mask.to_s.scan(Regexp.new(row[:address].to_s))
      }
      results = query.all.select{ |row| mask.to_s.scan(Regexp.new(row[:address].to_s)).size == 1}

      if results.length > 0
        @authentication = results[0] unless results[0][:level] < level
      end
    end

    def authorize_by_password(password)
      query = @bot.db[:user].where(:matchmethod => 4, :password => password).join(:user_access, :id => :accesslevel).reverse_order(:level)

      if query.count > 0
        access = query.first
        @authentication = access unless access[:level] < level
      end

    end

    def authorize
      authorize_by_nick
      authorize_by_address
    end

    def level
      @authentication.to_h.fetch(:level,0)
    end

    def authorized?
      level > 0
    end

    def has_admin_access?
      authorized? && @authentication[:can_add]
    end

    def op?
      authorized? && @authentication[:op]
    end

    def voice?
      authorized? && @authentication[:voice]
    end
  end

  class Channel
    def get_user(nick)
      puts "Looking for #{nick}..."
      users.keys.detect{ |user| user.nick == nick }
    end
  end

end
#todo: usuwanie uzytkownika przez jgo auth poziom
#todo: wymyslic cos z wyjatkami

#todo: access level string. make it admin, mod, user

#match methods:
# 0 - by nick
# 2 - by host
# 4 - by password

class AuthenticationPlugin
  include Cinch::Plugin
  self.prefix = '.'
  match /level/,                        method: :level
  match /auth (.+)/,                    group: :auth, method: :auth_by_pass
  match /auth/,                         group: :auth, method: :auth


  match /add nick ([^\s]+) ([0-9]+)/,  group: :add, method: :add_nick
  match /add ident ([^\s]+) ([0-9]+)/, group: :add, method: :add_ident
  match /add host ([^\s]+) ([0-9]+)/,  group: :add, method: :add_host
  match /add auth ([^\s]+) ([0-9]+)/,  group: :add, method: :add_auth
  match /add.*/,                       group: :add, method: :add_help
  match /remove auth ([0-9]+)/,          group: :remove, method: :remove_auth
  #match /eval (.*)/,                    method: :evaluate

  listen_to :join
  #match /^command3 (.+)/, use_prefix: false


  def auth(m, arg = nil)
    m.user.authorize
    m.reply "Ok. (#{m.user.level})"
  end

  def level(m, arg = nil)
    m.reply "Your level is: #{m.user.level}"
  end

  def auth_by_pass(m, arg)
    m.user.authorize_by_password(arg)
    m.reply "Ok. (#{m.user.level})"
  end


  def listen(m)
    if m.user.nick == @bot.nick
      m.channel.users.keys.each { |user| user.authorize }
    else
      m.user.authorize
    end
  end

  def add_help(m)
    m.reply 'To add a user access: .add [nick|ident|host|auth] [USER_NICK] [USER_LEVEL]'
  end


  def add_nick(m, nick, level)
    if m.user.has_admin_access?
      #begin
        @bot.db[:user].insert(:matchmethod => 0, :nick => nick, :accesslevel => level)
        m.reply 'Ok.'
      #rescue
      #  m.reply 'Fail. (wrong access level?)'
      #end
    else
      m.reply 'Access denied.'
    end
  end

  #przetestowac
  def add_ident(m, nick, level)
    if m.user.has_admin_access?
      puts m.channel.users
      user = m.channel.get_user(nick)

      if user.nil?
        m.reply 'No such user here.'
      else
        #begin
        address = user.mask.to_s.gsub(/[^!\s]+!~?([^@]+)@[^\.]+\.(.+)/ ,'[^s!]+!~?\1@[^.]+.\2').gsub(/\./,'\\\.')
          @bot.db[:user].insert(:matchmethod => 2,
                                  :address => address,
                                  :accesslevel => level,
                                  :name => "IDENT #{nick} #{Time.now.to_s}")
          m.reply 'Ok.'
        #rescue
        #  m.reply 'Fail. (wrong access level?)'
        #end
      end

    else
      m.reply 'Access denied.'
    end
  end


  #przetestowac
  def add_host(m, nick, level)
    if m.user.has_admin_access?
      puts m.channel.users
      user = m.channel.get_user(nick)
      #user = User(arg[0])
      if user.nil?
        m.reply 'No such user here.'
      else
        #begin
        host = user.mask(".*!%u@%h").to_s
        puts "inserting as #{host}"
        @bot.db[:user].insert(:matchmethod => 2,
                                    :address => host,
                                    :accesslevel => level,
                                    :name => "HOST #{nick} #{Time.now.to_s}")
        m.reply 'Ok.'
        #rescue
        #  m.reply 'Fail. (wrong access level?)'
        #end
      end

    else
      m.reply 'Access denied.'
    end
  end

  def add_auth(m, password, level)
    if m.user.authorized? && m.user.has_admin_access?
      @bot.db[:user].insert(:matchmethod => 4, :name => "PW by #{m.user.to_s} #{Time.now.to_s}",
                            :password => password, :accesslevel => level)
      m.reply 'Ok.'
      else
      m.reply 'Access denied.'
    end
  end

  def evaluate(m, text)
    if m.user.has_admin_access?
      m.reply "#{eval m.message[6..1000]}"
    end
  end


  def remove_auth(m, id)
    if m.user.has_admin_access?
      qr = @bot.db[:user].where(:id => id).delete
      m.reply "Result: #{qr.to_s}"
    end
  end

  def remove(m, nick)
    if m.user.has_admin_access?
      @bot.db[:user].where('name LIKE \'%? %\'',nick).delete
      m.reply 'Ok.'
    end
  end
end
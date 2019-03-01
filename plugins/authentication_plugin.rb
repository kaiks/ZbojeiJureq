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
  match /level\z/,                      method: :level
  match /level (.+)/,                   method: :level
  match /auth help/,                    group: :auth, method: :auth_help
  match /auth (.+)/,                    group: :auth, method: :auth_by_pass
  match /auth/,                         group: :auth, method: :auth

  match /add nick ([^\s]+) ([0-9]+)/,  group: :add, method: :add_nick
  match /add ident ([^\s]+) ([0-9]+)/, group: :add, method: :add_ident
  match /add host ([^\s]+) ([0-9]+)/,  group: :add, method: :add_host
  match /add auth ([^\s]+) ([0-9]+)/,  group: :add, method: :add_auth
  match /add.*/,                       group: :add, method: :add_help
  match /remove auth ([0-9]+)/,        group: :remove, method: :remove_auth

  listen_to :join

  def auth_help(m)
    m.reply 'To log in, try .auth, or .auth [password]. For add help, try .add help'
  end

  def auth(m)
    m.user.authorize
    m.reply "Ok. (#{m.user.level})"
  end

  def level(m, nick = nil)
    user = nick.nil? ? m.user : m.channel.get_user(nick)
    m.reply "Access level of #{nick} is: #{user.level}"
  end

  def auth_by_pass(m, password)
    m.user.authorize_by_password(password)
    m.reply "Ok. (#{m.user.level})"
  end

  def listen(m)
    if m.user.nick == @bot.nick
      m.channel.users.keys.each(&:authorize)
    else
      m.user.authorize
    end
  end

  def add_help(m)
    m.reply 'To add a user access: .add [nick|ident|host|auth] [USER_NICK] [USER_LEVEL]'
  end

  def add_nick(m, nick, level)
    if m.user.has_admin_access?
      @bot.db[:user].insert(:matchmethod => 0, :nick => nick, :accesslevel => level)
      m.reply 'Ok.'
    else
      m.reply 'Access denied.'
    end
  end

  #przetestowac
  def add_ident(m, nick, level)
    if m.user.has_admin_access?
      user = m.channel.get_user(nick)

      if user.nil?
        m.reply 'No such user here.'
      else
        address = user.mask.to_s.gsub(/[^!\s]+!~?([^@]+)@[^\.]+\.(.+)/ ,'[^s!]+!~?\1@[^.]+.\2').gsub(/\./,'\\\.')
        @bot.db[:user].insert(:matchmethod => 2,
                              :address => address,
                              :accesslevel => level,
                              :name => "IDENT #{nick} #{Time.now.to_s}")
        m.reply 'Ok.'
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

  def remove_auth(m, id)
    if m.user.has_admin_access?
      result = @bot.db[:user].where(:id => id).delete
      m.reply "Result: #{result}"
    end
  end

  def remove(m, nick)
    if m.user.has_admin_access?
      @bot.db[:user].where('name LIKE \'%? %\'', nick).delete
      m.reply 'Ok.'
    end
  end
end
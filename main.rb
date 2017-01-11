# encoding: utf-8

require 'rubygems'
require 'bundler/setup'
Bundler.require
require 'cinch/plugins/identify'

Dir.chdir(File.dirname(__FILE__))

Dir["./extensions/*.rb"].each {|file| require file }
Dir["./plugins/*.rb"].each {|file| require file }

require './config.rb'


class EvaluatePlugin
  include Cinch::Plugin
  self.prefix = '.'
  match /eval (.+)/, method: :evaluate

  def evaluate(m, arg)
    if m.user.level == 100
      m.reply eval(arg)
    end
  end
end

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

  class String
    def color(color)
      color + self.to_s + 3.chr
    end

    def bold
      2.chr + self.to_s + 2.chr
    end
  end
end

$bot = Cinch::Bot.new do
  configure do |c|
    c.nick                = CONFIG['nick']
    c.server              = CONFIG['server']
    c.messages_per_second = CONFIG['messages_per_second']
    c.messages_per_second = 100000 if c.server == 'localhost'
    c.server_queue_size   = 10000000 if c.server == 'localhost'
    c.channels            = ["#kx"]
    c.verbose             = CONFIG['verbose']
    c.shared[:database]   = DB#Sequel.connect('jdbc:sqlite:ZbojeiJureq.db')
    c.plugins.options[Cinch::Plugins::Identify] = {
        :username => CONFIG['auth']['user'],
        :password => CONFIG['auth']['password'],
        :type     => :quakenet
    }


    c.plugins.plugins = [EvaluatePlugin, TimerPlugin, AuthenticationPlugin, NotePlugin, AzPlugin,
                         TemplatePlugin, OwnPlugin, WeatherPlugin, TalkPlugin, UnoPlugin,
                         ObsoletePlugin, LoggerPlugin, ProtectPlugin, ObliczPlugin,
                         BtcPlugin, CurrencyPlugin,
                         CorePlugin,
                         Cinch::Plugins::PluginManagement, Cinch::Plugins::Identify]
  end


end

$bot.start
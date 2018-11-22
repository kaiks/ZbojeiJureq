# encoding: utf-8

require './config.rb'
require 'rubygems'
require 'bundler/setup'
Bundler.require
require 'cinch/plugins/identify'

Dir.chdir(File.dirname(__FILE__))

Dir["./extensions/*.rb"].each {|file| require file }
Dir["./plugins/*.rb"].each {|file| require file } unless CONFIG['disable_autoload']


$bot = Cinch::Bot.new do
  configure do |c|
    c.nick                = CONFIG['nick']
    c.server              = CONFIG['server']
    c.messages_per_second = CONFIG['messages_per_second']
    c.channels            = CONFIG['channels']
    c.verbose             = CONFIG['verbose']
    c.shared[:database]   = DB #Sequel.connect('jdbc:sqlite:ZbojeiJureq.db')

    c.messages_per_second = 100000    if c.server == 'localhost'
    c.server_queue_size   = 10000000  if c.server == 'localhost'

    c.plugins.options[Cinch::Plugins::Identify] = {
      username: CONFIG['auth']['user'],
      password: CONFIG['auth']['password'],
      type:     :quakenet
    }


    c.plugins.plugins = [EvaluatePlugin, TimerPlugin, AuthenticationPlugin, NotePlugin, AzPlugin,
                         TemplatePlugin, OwnPlugin, WeatherPlugin, TalkPlugin, UnoPlugin,
                         ObsoletePlugin, LoggerPlugin, ProtectPlugin, ObliczPlugin,
                         BtcPlugin, CurrencyPlugin, AntispamPlugin,
                         CorePlugin,
                         Cinch::Plugins::PluginManagement, Cinch::Plugins::Identify]
  end


end

$bot.start
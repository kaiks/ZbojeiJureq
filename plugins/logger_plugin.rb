#encoding: UTF-8
#todo: random quote
#todo: search by nick

require 'cinch'
require 'pasteit'

#based on Logging Plugin:
# == Logging Plugin Authors
# Marvin Gülker (Quintus)
# Jonathan Cran (jcran)
#
# A logging plugin for Cinch.
# Copyright © 2012 Marvin Gülker


class LoggerPlugin
  include Cinch::Plugin

  listen_to :connect,    :method => :setup
  listen_to :disconnect, :method => :cleanup
  listen_to :channel,    :method => :log_public_message
  timer 60,              :method => :check_midnight

  match /^.log old (.*)/,         method: :find_old, use_prefix: false

  def initialize(*args)
    super
    @short_format       = "%Y-%m-%d"
    @msg_format         = "%H:%M:%S"
    @filename           = "#kx.log"
        split
    @logfile            = File.open(@filename,"a+")
    @logfile_ram_cache  = File.readlines(@filename)
    @midnight_message   =  "#{@short_format}"
    @last_time_check    = Time.now
  end

  def setup(*)
    bot.debug("Opened message logfile at #{@filename}")
  end

  def cleanup(*)
    @logfile.close
    bot.debug("Closed message logfile at #{@filename}.")
  end

  ###
  ### Called every X seconds to see if we need to rotate the log
  ###
  def check_midnight
    time = Time.now
    if time.day != @last_time_check.day
      #@filename = "log-#{Time.now.strftime(@short_format)}.log"
      #@logfile = File.open(@filename,"w")
	  begin
		@logfile.puts(time.strftime(@midnight_message))
    @logfile_ram_cache = File.readlines(@filename)
    @logfile.close
      rescue
		puts 'Something went wrong with writing to log file'
	  end
      @logfile = File.open(@filename,"a+")
    end
    @last_time_check = time
  end

  ###
  ### Logs a message!
  ###
  def log_public_message(msg)
    time = Time.now.strftime(@msg_format)
    begin
      @logfile.puts(sprintf( "[%{time}] <%{nick}> %{msg}",
                           :time => time,
                           :nick => msg.user.name,
                           :msg  => msg.message))
    rescue
      File.close(@logfile)
      @logfile = nil
      @logfile = File.open(@logfile,"a+")
      @logfile.puts(sprintf( "[%{time}] <%{nick}> %{msg}",
                             :time => time,
                             :nick => msg.user.name,
                             :msg  => msg.message))
    end
  end

  def find_old(m)
    results = []
    pattern = m.message[9..400]
    timestamp = ''
    puts pattern


    #@logfile.rewind
    #@logfile.each_line do |line|
    @logfile_ram_cache.each do |line|
      ls = line.split
      if ls[0]=='Session' && (ls[1]=='Start:' || ls[1]=='Time:')
        timestamp = ls[6] + ' ' + ls[3..4].to_s
      elsif ls[0] =~ /^[0-9]{4}-[0-1][0-9]-[0-3][0-9]$/
        timestamp = ls[0] + ' '
      else
        if (line.include?(pattern)) && (!ls[0].nil?)
          #if (nick.nil?) or (ls[0].include?(nick))
            results += [timestamp + line] unless ls[0].include?('ZbojeiJureq')
          #end
        end
      end
    end
    m.reply results[0]
    m.reply 'moar: ' + Pasteit::PasteTool.new(results.join).upload! unless results.length < 2
  end

end
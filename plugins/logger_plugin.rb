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
    @logfile            = File.open(@filename,"a+")
    #@logfile_ram_cache  = File.open(@filename, 'r')
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
      get_lock
      begin
        @logfile.puts(time.strftime(@midnight_message))
        @logfile.close
      rescue
        puts 'Something went wrong with writing to log file'
        release_lock
      end
      @logfile = File.open(@filename,"a+")
      release_lock
    end
    @last_time_check = time
  end

  ###
  ### Logs a message!
  ###
  def log_public_message(msg)
    time = Time.now.strftime(@msg_format)
    get_lock
    begin
      @logfile.puts(sprintf( "[%{time}] <%{nick}> %{msg}",
                           :time => time,
                           :nick => msg.user.name,
                           :msg  => msg.message))
    rescue
      File.close(@logfile)
      @logfile = nil
      @logfile = File.open(@filename,"a+")
      @logfile.puts(sprintf( "[%{time}] <%{nick}> %{msg}",
                             :time => time,
                             :nick => msg.user.name,
                             :msg  => msg.message))
    end
    release_lock
  end

  def get_lock
    while @logfile_lock == true
      sleep(0.5)
    end
    @logfile_lock = true
  end

  def release_lock
    @logfile_lock = false
  end

  def find_old(m)
    results = []
    pattern = m.message[9..400]
    timestamp = ''
    puts pattern

    get_lock
    @logfile.rewind
    @logfile.each_line do |line|
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
    release_lock
    m.reply results[0]
    begin
      m.reply 'moar: ' + Pasteit::PasteTool.new(results.join).upload! unless results.length < 2
    rescue
      puts 'pasteit didnt work, initializing fallback'
      filename = rand(36**8).to_s(36)+'.txt'
      tmp_file = File.write('tmp_files/' + filename, results.join)
      result = @bot.send_to_ftp('tmp_files/' + filename, '/logs')
      m.reply "moar: #{result}"
    end
  end

end
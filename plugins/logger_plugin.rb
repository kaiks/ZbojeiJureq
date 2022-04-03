# frozen_string_literal: true

# TODO: random quote
# todo: search by nick

require 'cinch'
require 'digest/sha1'

# based on Logging Plugin:
# == Logging Plugin Authors
# Marvin Gülker (Quintus)
# Jonathan Cran (jcran)
#
# A logging plugin for Cinch.
# Copyright © 2012 Marvin Gülker

class LogFragment
  attr_reader :full_content
  def initialize(full_content)
    @full_content = full_content
  end

  def main_fragment
    array_middle_element(@full_content.split("\n"))
  end

  def array_middle_element(array)
    array[array.length / 2]
  end

  def to_s
    main_fragment
  end
end

class LoggerPlugin
  include Cinch::Plugin

  listen_to :connect,    method: :setup
  listen_to :disconnect, method: :cleanup
  listen_to :channel,    method: :log_public_message
  timer 60,              method: :check_midnight

  match(/^.log old (.*)/, method: :find_old, use_prefix: false)

  LOG_FILENAME = '#kx.log'
  USE_FTP = false

  def initialize(*args)
    super
    @short_format       = '%Y-%m-%d'
    @msg_format         = '%H:%M:%S'
    @filename           = LOG_FILENAME
    @logfile            = File.open("logs/#{@filename}", 'a+')
    # @logfile_ram_cache  = File.open(@filename, 'r')
    @midnight_message = @short_format.to_s
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
      rescue StandardError
        puts 'Something went wrong with writing to log file'
        release_lock
      end
      @logfile = File.open(@filename, 'a+')
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
      @logfile.puts(format('[%{time}] <%{nick}> %{msg}',
                           time: time,
                           nick: msg.user.name,
                           msg: msg.message))
    rescue StandardError
      File.close(@logfile)
      @logfile = nil
      @logfile = File.open(@filename, 'a+')
      @logfile.puts(format('[%{time}] <%{nick}> %{msg}',
                           time: time,
                           nick: msg.user.name,
                           msg: msg.message))
    end
    release_lock
  end

  def get_lock
    sleep(0.5) while @logfile_lock == true
    @logfile_lock = true
  end

  def release_lock
    @logfile_lock = false
  end

  def find_old(m)
    pattern = m.message[9..400]

    results = find_results_in_log(pattern, 2) || []
    fragments = results.split(/^--$/).map { |result| LogFragment.new(result) }
    fragments[0..3].each { |fragment| m.reply fragment }

    remaining_results_response(results, m) if results.length > 4
  end

  def find_results_in_log(pattern, context = 0)
    `tools/sift '#{pattern}' logs/#{LOG_FILENAME} --not-preceded-by=".log old" --context=#{context}`
  end

  def remaining_results_response(results, m)
    result_digest = Digest::SHA1.hexdigest(results)
    filename = "#{result_digest[0..4]}#{result_digest[-5..-1]}.txt"
    local_filepath = "tmp_files/#{filename}"

    if File.exist?(local_filepath)
      m.reply "moar: #{log_file_url(filename)}"
    else
      tmp_file = File.write("tmp_files/#{filename}", results)
      url = store_results_on_server("#{Dir.pwd}/tmp_files/", filename)
      m.reply "moar: #{url}"
    end
  end

  # returns URL to file
  def store_results_on_server(src_path = './', src_filename)
    file_path = src_path + src_filename
    if USE_FTP
      @bot.send_to_ftp(file_path, '/logs')
    else
      dest_folder = "/log_upload/"
      puts "Copy from #{file_path} to #{dest_folder}"
      puts FileUtils.cp(file_path, dest_folder + "#{src_filename}")
      log_file_url(src_filename)
    end
  end

  def log_file_url(filename)
    "#{CONFIG['ftp_result_url']}logs/#{filename}"
  end

  def find_old_deprecated(m)
    results = []
    pattern = m.message[9..400]
    timestamp = ''
    puts pattern

    get_lock
    @logfile.rewind
    @logfile.each_line do |line|
      ls = line.split
      if ls[0] == 'Session' && (ls[1] == 'Start:' || ls[1] == 'Time:')
        timestamp = "#{ls[6]} #{ls[3..4]}"
      elsif ls[0] =~ /^[0-9]{4}-[0-1][0-9]-[0-3][0-9]$/
        timestamp = "#{ls[0]} "
      elsif line.include?(pattern) && !ls[0].nil?
        results += [timestamp + line] unless ls[0].include?('ZbojeiJureq') || line.include?('> .log old')
      end
    end
    release_lock
    m.reply results[0] if results[0]
    return if results.length <= 1

    results = results.join

    result_digest = Digest::SHA1.hexdigest(results)
    filename = "#{result_digest[0..4]}#{result_digest[-5..-1]}.txt"
    filepath = "tmp_files/#{filename}"
    if File.exist?(filepath)
      m.reply "moar: #{"#{CONFIG['ftp_result_url']}logs/#{filename}"}"
    else
      tmp_file = File.write("tmp_files/#{filename}", results)
      result = @bot.send_to_ftp("tmp_files/#{filename}", '/logs')
      m.reply "moar: #{result}"
    end
  end
end

# frozen_string_literal: true

# TODO: random quote
# todo: search by nick

require 'cinch'
require 'digest/sha1'
require 'fileutils'

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

  LOG_FILENAME = '#kx.log'.freeze
  RELATIVE_RETRIEVED_LOG_DIR = "tmp_files".freeze
  USE_FTP = false

  def initialize(*args)
    super
    @short_format       = '%Y-%m-%d'
    @msg_format         = '%H:%M:%S'
    @filename           = LOG_FILENAME
    @filepath           = "logs/#{@filename}"
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
      write_to_log(time.strftime(@midnight_message))
    end
    @last_time_check = time
  end

  ###
  ### Logs a message!
  ###
  def log_public_message(msg)
    text = message_to_log_line(msg)
    write_to_log(text)
  end

  def message_to_log_line(msg)
    time = Time.now.strftime(@msg_format)
    format('[%{time}] <%{nick}> %{msg}',
      time: time,
      nick: msg.user.name,
      msg: msg.message)
  end

  def write_to_log(text)
    text.concat("\n") unless text.end_with?("\n")
    semaphore.synchronize do
      File.write(@filepath, text, mode: 'a')
    end
  end

  def semaphore
    @semaphore ||= Mutex.new
  end

  def find_old(m)
    pattern = m.message[9..400]

    results = find_results_in_log(pattern, 2) || []
    return "No results found for #{pattern}" if results.empty?

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
    local_filepath = "#{RELATIVE_RETRIEVED_LOG_DIR}/#{filename}"

    if File.exist?(local_filepath)
      m.reply "moar: #{log_file_url(filename)}"
    else
      ensure_directory_exists(RELATIVE_RETRIEVED_LOG_DIR)
      tmp_file = File.write("#{RELATIVE_RETRIEVED_LOG_DIR}/#{filename}", results)
      url = store_results_on_server("#{Dir.pwd}/#{RELATIVE_RETRIEVED_LOG_DIR}/", filename)
      m.reply "moar: #{url}"
    end
  end

  def ensure_directory_exists(directory)
    dirname = File.dirname(directory)
    FileUtils.mkdir_p(dirname) unless File.directory?(dirname)
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
end

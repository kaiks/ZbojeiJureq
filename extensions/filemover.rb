require 'fileutils'
require 'uri'
require 'net/ftp'
require './config.rb'


module Cinch
  FTP_LOGIN = CONFIG['ftp_login']
  FTP_PASSWORD = CONFIG['ftp_password']
  FTP_PATH = CONFIG['ftp_path']
  FTP_HOST = CONFIG['ftp_host']
  FTP_RESULT_URL = CONFIG['ftp_result_url']
  DROPBOX_PATH = CONFIG['dropbox_path']


  class Bot
    def upload_to_dropbox file, path = '', filename=file.split('/')[-1]
      #self.config.shared[:database]
      return unless CONFIG['dropbox_upload']
      path += '\\' unless path='' || path[-1] == '\\'
      FileUtils.cp file, DROPBOX_PATH + path + filename
    end

    def send_to_ftp(sourcefile, path = '', filename = sourcefile.split('/')[-1])
      return unless CONFIG['ftp_upload']
      ftp = Net::FTP.new(FTP_HOST)
      ftp.passive = true
      ftp.login(FTP_LOGIN, FTP_PASSWORD)
      ftp.chdir(FTP_PATH + path)
      ftp.putbinaryfile(sourcefile, filename)
      ftp.close

      FTP_RESULT_URL + path + '/' + filename

    rescue Exception => err
      puts err.message
      false
    end
  end
end
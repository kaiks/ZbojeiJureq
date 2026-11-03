require 'spec_helper'
require 'cinch'
require 'sequel'
require_relative '../../extensions/database'
require_relative '../../plugins/core_plugin'
require_relative '../../plugins/talk_plugin'
require_relative '../../plugins/uno_plugin'

RSpec.describe 'database backup paths' do
  let(:bot) { instance_double('Bot') }

  it 'uploads the connected main database' do
    plugin = CorePlugin.allocate
    plugin.instance_variable_set(:@bot, bot)
    expect(bot).to receive(:upload_to_dropbox).with(DB.opts.fetch(:database))

    plugin.upload_general_db
  end

  it 'uploads the connected talk database' do
    plugin = TalkPlugin.allocate
    talk_database = instance_double(Sequel::Database, opts: { database: '/live/talk.db' })
    plugin.instance_variable_set(:@bot, bot)
    plugin.instance_variable_set(:@talkdb, talk_database)
    expect(bot).to receive(:upload_to_dropbox).with('/live/talk.db')

    plugin.upload
  end

  it 'uploads the connected UNO database to each enabled destination' do
    plugin = UnoPlugin.allocate
    plugin.instance_variable_set(:@bot, bot)
    path = UNODB.opts.fetch(:database)
    expect(bot).to receive(:upload_to_dropbox).with(path)
    expect(bot).to receive(:send_to_ftp).with(path)

    plugin.upload_db
  end
end

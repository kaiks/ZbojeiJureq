require 'spec_helper'
require 'cinch'
require 'sequel'
require_relative '../../extensions/database'
require_relative '../../plugins/note_plugin'

RSpec.describe NotePlugin do
  let(:plugin) { described_class.allocate }

  describe '#time_parse' do
    it 'rejects an impossible date instead of scheduling it immediately' do
      expect { plugin.time_parse('12:00', '99.99.2026') }
        .to raise_error(RuntimeError, 'Wrong date format. The correct format is dd.mm.YYYY HH:MM')
    end

    it 'rejects calendar dates that Ruby Time.parse would normalize' do
      expect { plugin.time_parse('12:00', '31.02.2026') }
        .to raise_error(RuntimeError, 'Wrong date format. The correct format is dd.mm.YYYY HH:MM')
    end
  end

  describe '#notify' do
    let(:database) do
      Sequel.sqlite.tap do |db|
        db.create_table(:note) do
          primary_key :id
          String :nick_from, null: false
          String :nick_to, null: false
          DateTime :posted, null: false
          String :message, null: false
          Integer :status
          DateTime :due
        end
      end
    end
    let(:note_class) do
      Class.new(Sequel::Model(database[:note])) do
        dataset_module do
          def for(nick)
            where(Sequel.function(:lower, :nick_to) => nick.downcase)
          end

          def due
            where(Sequel.lit("due <= datetime(CURRENT_TIMESTAMP, 'localtime') OR due IS NULL"))
          end
        end
      end
    end
    let(:user) { double('User', to_s: 'Alice', nick: 'Alice') }
    let(:message) { double('Message', user: user) }

    before do
      stub_const('Note', note_class)
      note_class.create(
        nick_from: 'Bob', nick_to: 'Alice', posted: Time.now,
        message: 'hello', status: 0
      )
    end

    after do
      database.disconnect
    end

    it 'does not deliver the same notes from concurrent message handlers' do
      delivery_started = Queue.new
      release_delivery = Queue.new
      deliveries = Queue.new
      allow(plugin).to receive(:send_notes) do |_message, notes|
        deliveries << notes
        delivery_started << true
        release_delivery.pop
      end

      first = Thread.new { plugin.notify(message) }
      delivery_started.pop
      second = Thread.new { plugin.notify(message) }
      release_delivery << true
      first.join
      second.join

      expect(deliveries.size).to eq(1)
      expect(note_class.first.status).to eq(1)
    end
  end
end

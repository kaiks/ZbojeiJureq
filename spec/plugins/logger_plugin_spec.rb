require 'spec_helper'
require 'cinch'
require 'tmpdir'
require_relative '../../plugins/logger_plugin'

RSpec.describe LoggerPlugin do
  let(:plugin) { described_class.allocate }

  describe '#find_results_in_log' do
    it 'searches with ripgrep without executing shell syntax in the pattern' do
      Dir.mktmpdir do |directory|
        log_path = File.join(directory, 'channel.log')
        marker_path = File.join(directory, 'shell-command-ran')
        File.write(log_path, "before\nneedle\nafter\n")
        plugin.instance_variable_set(:@filepath, log_path)

        expect(plugin.find_results_in_log('needle', 1)).to include('before', 'needle', 'after')

        malicious_pattern = "'; touch #{marker_path}; #"
        plugin.find_results_in_log(malicious_pattern, 0)
        expect(File).not_to exist(marker_path)
      end
    end
  end

  describe '#find_old' do
    let(:message) { instance_double('Message', message: '.log old needle', reply: nil) }

    it 'uploads additional output only when there are more than four fragments' do
      results = 5.times.map { |index| "line #{index}" }.join("\n--\n")
      allow(plugin).to receive(:find_results_in_log).and_return(results)
      expect(plugin).to receive(:remaining_results_response).with(results, message)

      plugin.find_old(message)
    end

    it 'does not treat a long single result as multiple fragments' do
      results = 'a single result longer than four characters'
      allow(plugin).to receive(:find_results_in_log).and_return(results)
      expect(plugin).not_to receive(:remaining_results_response)

      plugin.find_old(message)
    end
  end

  describe '#cleanup' do
    it 'does not close a logfile that is never opened persistently' do
      bot = instance_double('Bot', debug: nil)
      allow(plugin).to receive(:bot).and_return(bot)
      plugin.instance_variable_set(:@filename, '#kx.log')

      expect { plugin.cleanup }.not_to raise_error
    end
  end
end

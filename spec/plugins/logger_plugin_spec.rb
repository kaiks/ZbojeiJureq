require 'spec_helper'
require 'cinch'
require_relative '../../plugins/logger_plugin'

RSpec.describe LoggerPlugin do
  let(:plugin) { described_class.allocate }

  describe '#find_results_in_log' do
    it 'passes untrusted patterns to ripgrep without a shell' do
      plugin.instance_variable_set(:@filepath, 'logs/#kx.log')
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      pattern = "quote'; unwanted-command"

      expect(Open3).to receive(:capture3).with(
        'rg', '-P', '--context', '2', '--',
        "(?<!\\.log old )#{pattern}", 'logs/#kx.log'
      ).and_return(["match\n", '', status])

      expect(plugin.find_results_in_log(pattern, 2)).to eq("match\n")
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

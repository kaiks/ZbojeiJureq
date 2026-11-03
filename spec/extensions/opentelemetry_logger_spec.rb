require 'spec_helper'
require 'cinch/logger'
require 'opentelemetry'
require 'opentelemetry/sdk'
require_relative '../../extensions/opentelemetry_logger'

RSpec.describe Cinch::Logger::OpenTelemetryLogger do
  let(:span) { double('OpenTelemetry span', record_exception: nil) }
  let(:tracer) { double('OpenTelemetry tracer') }
  let(:logger) { described_class.new(tracer: tracer) }

  before do
    allow(tracer).to receive(:in_span).and_yield(span)
    allow(span).to receive(:status=)
  end

  it 'exports exceptions as error spans through the OpenTelemetry SDK' do
    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
    provider.add_span_processor(processor)
    telemetry_logger = described_class.new(tracer: provider.tracer('test.cinch'))
    error = RuntimeError.new('broken handler')

    telemetry_logger.exception(error)

    exported_span = exporter.finished_spans.fetch(0)
    expect(exported_span.name).to eq('cinch.exception')
    expect(exported_span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
    expect(exported_span.status.description).to eq('broken handler')
    expect(exported_span.events.map(&:name)).to include('exception')
  end

  it 'records explicit Cinch error messages without writing to a nil IO' do
    expect(tracer).to receive(:in_span).with(
      'cinch.logger.error',
      attributes: { 'log.severity' => 'ERROR', 'log.message' => 'request failed' }
    ).and_yield(span)

    expect { logger.error('request failed') }.not_to raise_error
  end
end

# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Bot::Thetrainline do
  describe '.find' do
    let(:from)         { 'Berlin Hbf' }
    let(:to)           { 'Lisboa Santa Apolónia' }
    let(:departure_at) { DateTime.new(2025, 4, 26) }
    let(:segments)     { [{ departure_station: from, arrival_station: to }] }

    context 'with mocked dependencies' do
      let(:raw_data)     { { 'journeys' => [] } }
      let(:journey)      { instance_double(Bot::Thetrainline::Journey, to_station: segments) }

      before do
        allow(Bot::Thetrainline::Fetcher).to receive(:new)
          .with(from, to, departure_at)
          .and_return(instance_double(Bot::Thetrainline::Fetcher, fetch: raw_data))

        allow(Bot::Thetrainline::JourneyFactory).to receive(:new)
          .with(raw_data)
          .and_return(instance_double(Bot::Thetrainline::JourneyFactory, build: journey))
      end

      it 'passes from, to, and departure_at to Fetcher' do
        described_class.find(from, to, departure_at)
        expect(Bot::Thetrainline::Fetcher).to have_received(:new).with(from, to, departure_at)
      end

      it 'passes fetched data to JourneyFactory' do
        described_class.find(from, to, departure_at)
        expect(Bot::Thetrainline::JourneyFactory).to have_received(:new).with(raw_data)
      end

      it 'calls to_station on the built journey' do
        described_class.find(from, to, departure_at)
        expect(journey).to have_received(:to_station)
      end

      it 'returns the array of segment hashes' do
        expect(described_class.find(from, to, departure_at)).to eq(segments)
      end
    end

    context 'with integration test' do
      subject(:results) { described_class.find(from, to, departure_at) }

      it 'returns an Array' do
        expect(results).to be_an(Array)
      end

      it 'returns results for the requested destination' do
        expect(results).not_to be_empty
      end

      it 'all segments have the required keys' do
        results.each do |seg|
          expect(seg.keys).to match_array(%i[
                                            departure_station departure_at arrival_station arrival_at
                                            service_agencies duration_in_minutes changeovers products fares
                                          ])
        end
      end

      it 'all results arrive at the requested destination' do
        results.each do |seg|
          expect(seg[:arrival_station]).to eq('Lisboa Santa Apolónia')
        end
      end

      it 'all results depart on the requested date' do
        results.each do |seg|
          expect(seg[:departure_at].to_date).to eq(departure_at.to_date)
        end
      end

      it 'returns fewer results when departure_at is later in the day' do
        late_results = described_class.find(from, to, DateTime.new(2026, 4, 15, 22, 0, 0, '+02:00'))
        expect(late_results.size).to be < results.size
      end
    end
  end
end

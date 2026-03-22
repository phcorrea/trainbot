# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Bot::Thetrainline::Fetcher do
  subject(:fetcher) { described_class.new(from, to, departure_at) }

  let(:from)         { 'Berlin Hbf' }
  let(:to)           { 'Lisboa Santa Apolónia' }
  let(:departure_at) { DateTime.new(2026, 4, 15, 0, 0, 0) }

  describe '#fetch' do
    it 'returns parsed JSON for a known fixture' do
      expect(fetcher.fetch).to be_a(Hash)
    end

    it 'raises ArgumentError when no fixture exists' do
      bad = described_class.new('Nowhere', 'Somewhere', departure_at)
      expect { bad.fetch }.to raise_error(ArgumentError, /No fixture for 'Nowhere' -> 'Somewhere'/)
    end

    it 'raises ArgumentError with the expected path in the message' do
      bad = described_class.new('Nowhere', 'Somewhere', departure_at)
      expect { bad.fetch }.to raise_error(ArgumentError, /nowhere_somewhere\.json/)
    end

    describe 'date shifting' do
      let(:journeys) { fetcher.fetch.dig('data', 'journeySearch', 'journeys').values }

      it 'shifts all journey dates to the requested date' do
        dates = journeys.map { |j| Date.parse(j['departAt']) }.uniq
        expect(dates).to all(eq(departure_at.to_date))
      end

      it 'all returned journeys depart at or after the requested time' do
        journeys.each do |j|
          expect(DateTime.parse(j['departAt'])).to be >= departure_at
        end
      end

      it 'returns fewer journeys when departure_at is late in the day' do
        late       = DateTime.new(2026, 4, 15, 22, 0, 0, '+02:00')
        late_count = described_class.new(from, to, late).fetch.dig('data', 'journeySearch', 'journeys').size
        expect(late_count).to be < journeys.size
      end
    end
  end

  describe 'malformed journeys' do
    def fixture_with(journeys_hash)
      JSON.generate({
                      'data' => {
                        'journeySearch' => { 'journeys' => journeys_hash },
                        'locations' => {}, 'fareTypes' => {},
                        'sections' => {}, 'alternatives' => {}, 'fares' => {}, 'legs' => {}
                      }
                    })
    end

    def fetch_with(journeys_hash)
      allow(File).to receive_messages(exist?: true, read: fixture_with(journeys_hash))
      described_class.new(from, to, departure_at).fetch
    end

    it 'skips an unsellable journey missing departAt without raising' do
      result = fetch_with(
        'j1' => { 'unsellableReason' => { 'code' => 'full' }, 'departAt' => nil, 'arriveAt' => nil }
      )
      expect(result.dig('data', 'journeySearch', 'journeys')).to be_empty
    end

    it 'skips a sellable journey missing departAt without raising' do
      result = fetch_with(
        'j1' => { 'unsellableReason' => nil, 'departAt' => nil, 'arriveAt' => '2026-03-16T10:00:00+01:00' }
      )
      expect(result.dig('data', 'journeySearch', 'journeys')).to be_empty
    end

    it 'skips a sellable journey missing arriveAt without raising' do
      result = fetch_with(
        'j1' => { 'unsellableReason' => nil, 'departAt' => '2026-03-16T08:00:00+01:00', 'arriveAt' => nil }
      )
      expect(result.dig('data', 'journeySearch', 'journeys')).to be_empty
    end
  end

  describe 'DST offset correction' do
    # Fixture journeys are on 2026-03-23 (CET, +01:00).
    # Europe/Berlin springs forward on 2026-03-29, so 2026-03-30 is CEST (+02:00).

    def offsets_for(departure_at)
      journeys = described_class.new(from, to, departure_at)
                                .fetch.dig('data', 'journeySearch', 'journeys').values
      journeys.flat_map { |j| [j['departAt'], j['arriveAt']] }
              .map { |ts| ts[-6..] }
              .uniq
    end

    it 'uses +01:00 when the target date is before the DST transition' do
      expect(offsets_for(DateTime.new(2026, 3, 16, 0, 0, 0))).to eq(['+01:00'])
    end

    it 'uses +02:00 when the target date is after the DST transition' do
      expect(offsets_for(DateTime.new(2026, 4, 15, 0, 0, 0))).to eq(['+02:00'])
    end
  end

  describe 'slug construction' do
    it 'downcases and replaces non-alphanumeric runs with underscores' do
      fetcher1 = described_class.new('Berlin Hbf', 'Lisboa Santa Apolónia', departure_at)
      fetcher2 = described_class.new('berlin hbf', 'lisboa santa apolónia', departure_at)
      expect(fetcher1.fetch).to eq(fetcher2.fetch)
    end

    it 'strips leading and trailing underscores from slugs' do
      expect(fetcher.fetch).to be_a(Hash)
    end
  end
end

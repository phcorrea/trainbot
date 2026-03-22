# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Bot::Thetrainline::Journey do
  subject(:journey) { described_class.new([base_segment]) }

  let(:base_segment) do
    {
      departure_station: 'Berlin Hbf',
      departure_at: DateTime.parse('2025-01-01T10:00:00+00:00'),
      arrival_station: 'Lisboa Santa Apolónia',
      arrival_at: DateTime.parse('2025-01-01T18:00:00+00:00'),
      duration: 'PT8H',
      changeovers: 1,
      section_fares: [[{ name: 'Standard', price_in_cents: 1000, currency: 'GBP' }]]
    }
  end

  describe '#segments' do
    it 'processes raw segments into hashes with duration_in_minutes and fares' do
      expect(journey.segments.first.keys).to match_array(%i[
                                                           departure_station departure_at arrival_station arrival_at
                                                           duration_in_minutes changeovers fares
                                                         ])
    end

    it 'parses duration into minutes' do
      expect(journey.segments.first[:duration_in_minutes]).to eq(480)
    end
  end

  describe 'duration parsing' do
    def journey_with_duration(iso)
      described_class.new([base_segment.merge(duration: iso)])
    end

    {
      'PT45M' => 45,
      'PT2H' => 120,
      'PT2H30M' => 150,
      'P1DT2H' => 1560,
      'P1DT2H15M' => 1575,
      'P2DT30M' => 2910
    }.each do |iso, expected|
      it "parses #{iso} as #{expected} minutes" do
        expect(journey_with_duration(iso).segments.first[:duration_in_minutes]).to eq(expected)
      end
    end

    it 'raises ParseError for an unsupported format' do
      expect { journey_with_duration('INVALID') }
        .to raise_error(Bot::Thetrainline::ParseError, /unsupported duration format/i)
    end
  end

  describe 'fare combination' do
    it 'returns [] for empty section_fares' do
      j = described_class.new([base_segment.merge(section_fares: [])])
      expect(j.segments.first[:fares]).to eq([])
    end

    it 'returns single-section fares as-is' do
      expect(journey.segments.first[:fares]).to eq([{ name: 'Standard', price_in_cents: 1000, currency: 'GBP' }])
    end

    it 'combines two sections into a Cartesian product, sorted by price' do
      section_fares = [
        [
          { name: 'Cheap',  price_in_cents: 1000, currency: 'GBP' },
          { name: 'Pricey', price_in_cents: 3000, currency: 'GBP' }
        ],
        [{ name: 'Saver', price_in_cents: 500, currency: 'GBP' }]
      ]
      j = described_class.new([base_segment.merge(section_fares: section_fares)])
      expect(j.segments.first[:fares]).to eq([
                                               { name: 'Cheap + Saver', price_in_cents: 1500, currency: 'GBP' },
                                               { name: 'Pricey + Saver', price_in_cents: 3500, currency: 'GBP' }
                                             ])
    end

    it 'caps combinations at MAX_COMBINATIONS for large inputs' do
      s1 = (1..6).map { |i| { name: "S1-#{i}", price_in_cents: i * 100, currency: 'GBP' } }
      s2 = (1..4).map { |i| { name: "S2-#{i}", price_in_cents: i * 100, currency: 'GBP' } }
      j  = described_class.new([base_segment.merge(section_fares: [s1, s2])])

      expect(j.segments.first[:fares].length).to eq(described_class::MAX_COMBINATIONS)
      prices = j.segments.first[:fares].map { |f| f[:price_in_cents] }
      expect(prices).to eq(prices.sort)
      expect(prices.first).to eq(200)
    end

    it 'raises ParseError when sections have mixed currencies' do
      section_fares = [
        [{ name: 'GBP Fare', price_in_cents: 1000, currency: 'GBP' }],
        [{ name: 'EUR Fare', price_in_cents: 1000, currency: 'EUR' }]
      ]
      expect { described_class.new([base_segment.merge(section_fares: section_fares)]) }
        .to raise_error(Bot::Thetrainline::ParseError, /mixed currencies/i)
    end
  end

  describe '#to_station' do
    it 'returns an array of hashes' do
      expect(journey.to_station).to be_an(Array)
      expect(journey.to_station).to all(be_a(Hash))
    end

    it 'returns one entry per segment' do
      expect(journey.to_station.length).to eq(1)
    end

    it 'includes service_agencies and products' do
      expect(journey.to_station.first[:service_agencies]).to eq(['thetrainline'])
      expect(journey.to_station.first[:products]).to eq(['train'])
    end

    it 'includes all processed segment fields' do
      result = journey.to_station.first
      expect(result[:departure_station]).to eq('Berlin Hbf')
      expect(result[:duration_in_minutes]).to eq(480)
      expect(result[:fares]).not_to be_empty
    end
  end
end

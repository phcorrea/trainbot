# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Bot::Thetrainline::JourneyFactory do
  let(:fixture_path) { File.expand_path('../../../fixtures/berlin_hbf_lisboa_santa_apol_nia.json', __dir__) }
  let(:data)         { JSON.parse(File.read(fixture_path)) }
  let(:journey) { described_class.new(data).build }

  it 'returns a Journey object' do
    expect(journey).to be_a(Bot::Thetrainline::Journey)
  end

  it 'builds sellable segments' do
    expect(journey.to_station).not_to be_empty
  end

  describe 'segment structure' do
    subject(:seg) { journey.to_station.first }

    it 'has required keys' do
      expect(seg.keys).to match_array(%i[
                                        departure_station departure_at arrival_station arrival_at
                                        service_agencies duration_in_minutes changeovers products fares
                                      ])
    end

    it 'sets service_agencies to thetrainline' do
      expect(seg[:service_agencies]).to eq(['thetrainline'])
    end

    it 'sets products to train' do
      expect(seg[:products]).to eq(['train'])
    end

    it 'has datetime departure_at and arrival_at' do
      expect(seg[:departure_at]).to be_a(DateTime)
      expect(seg[:arrival_at]).to be_a(DateTime)
    end

    it 'has positive duration_in_minutes' do
      expect(seg[:duration_in_minutes]).to be > 0
    end

    it 'has non-negative changeovers' do
      expect(seg[:changeovers]).to be >= 0
    end

    it 'has at least one fare' do
      expect(seg[:fares]).not_to be_empty
    end
  end

  describe 'fares contract' do
    subject(:segment) { journey.to_station.first }

    it 'fares is a flat array of fare hashes' do
      expect(segment[:fares]).to be_an(Array)
      expect(segment[:fares]).not_to include(include(:section_fares))
    end

    it 'each fare has exactly name, price_in_cents, and currency' do
      segment[:fares].each do |fare|
        expect(fare.keys).to match_array(%i[name price_in_cents currency])
      end
    end

    it 'each fare has a non-empty string name' do
      segment[:fares].each do |fare|
        expect(fare[:name]).to be_a(String)
        expect(fare[:name]).not_to be_empty
      end
    end

    it 'each fare has a positive integer price_in_cents' do
      segment[:fares].each do |fare|
        expect(fare[:price_in_cents]).to be_a(Integer).and be > 0
      end
    end

    it 'each fare has a 3-letter currency code' do
      segment[:fares].each do |fare|
        expect(fare[:currency]).to match(/\A[A-Z]{3}\z/)
      end
    end
  end

  describe 'ParseError on malformed payloads' do
    def minimal_data
      JSON.parse(File.read(fixture_path))
    end

    it "raises ParseError when 'data' key is missing" do
      bad = minimal_data.tap { |d| d.delete('data') }
      expect { described_class.new(bad) }.to raise_error(Bot::Thetrainline::ParseError, /data/)
    end

    it "raises ParseError when 'journeySearch' key is missing" do
      bad = minimal_data.tap { |d| d['data'].delete('journeySearch') }
      expect { described_class.new(bad) }.to raise_error(Bot::Thetrainline::ParseError, /journeySearch/)
    end

    %w[journeys sections alternatives fares legs].each do |key|
      it "raises ParseError when '#{key}' is missing from journeySearch" do
        bad = minimal_data.tap { |d| d['data']['journeySearch'].delete(key) }
        expect { described_class.new(bad) }.to raise_error(Bot::Thetrainline::ParseError, /#{key}/)
      end
    end

    %w[locations fareTypes].each do |key|
      it "raises ParseError when '#{key}' is missing from data" do
        bad = minimal_data.tap { |d| d['data'].delete(key) }
        expect { described_class.new(bad) }.to raise_error(Bot::Thetrainline::ParseError, /#{key}/)
      end
    end

    it 'raises ParseError when a journey references a missing leg id' do
      bad = minimal_data
      sellable = bad['data']['journeySearch']['journeys'].find do |_, j|
        !j['unsellableReason'] && !j['sections'].empty?
      end
      sellable.last['legs'] = ['nonexistent-leg']
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /leg.*nonexistent-leg/i)
    end

    it 'raises ParseError when a leg references a missing location id' do
      bad = minimal_data
      sellable = bad['data']['journeySearch']['journeys'].find do |_, j|
        !j['unsellableReason'] && !j['sections'].empty?
      end
      first_leg_id = sellable.last['legs'].first
      bad['data']['journeySearch']['legs'][first_leg_id]['departureLocation'] = 'nonexistent-loc'
      expect do
        described_class.new(bad).build
      end.to raise_error(Bot::Thetrainline::ParseError, /location.*nonexistent-loc/i)
    end

    it 'raises ParseError when a journey references a missing section id' do
      bad = minimal_data
      journey = bad['data']['journeySearch']['journeys'].values.find do |j|
        !j['unsellableReason'] && !j['sections'].empty?
      end
      journey['sections'] = ['nonexistent-section']
      expect do
        described_class.new(bad).build
      end.to raise_error(Bot::Thetrainline::ParseError, /section.*nonexistent-section/i)
    end

    it 'raises ParseError when a section references a missing alternative id' do
      bad = minimal_data
      first_section_id = bad['data']['journeySearch']['sections'].keys.first
      bad['data']['journeySearch']['sections'][first_section_id]['alternatives'] = ['nonexistent-alt']
      expect do
        described_class.new(bad).build
      end.to raise_error(Bot::Thetrainline::ParseError, /alternative.*nonexistent-alt/i)
    end

    it 'raises ParseError when an alternative has a nil fares array' do
      bad = minimal_data
      first_alt_id = bad['data']['journeySearch']['alternatives'].keys.first
      bad['data']['journeySearch']['alternatives'][first_alt_id]['fares'] = nil
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /fares/i)
    end

    it 'raises ParseError when an alternative references a missing fare id' do
      bad = minimal_data
      first_alt_id = bad['data']['journeySearch']['alternatives'].keys.first
      bad['data']['journeySearch']['alternatives'][first_alt_id]['fares'] = ['nonexistent-fare']
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /fare.*nonexistent-fare/i)
    end

    it 'raises ParseError when a fare references a missing fare type id' do
      bad = minimal_data
      first_fare_id = bad['data']['journeySearch']['fares'].keys.first
      bad['data']['journeySearch']['fares'][first_fare_id]['fareType'] = 'nonexistent-fare-type'
      expect do
        described_class.new(bad).build
      end.to raise_error(Bot::Thetrainline::ParseError, /fare type.*nonexistent-fare-type/i)
    end

    def sellable_journey(data)
      data['data']['journeySearch']['journeys'].values.find do |j|
        !j['unsellableReason'] && j['sections'] && !j['sections'].empty?
      end
    end

    it "raises ParseError when journey is missing 'sections'" do
      bad = minimal_data
      bad['data']['journeySearch']['journeys'].values.find { |j| !j['unsellableReason'] }.delete('sections')
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /sections/)
    end

    it "raises ParseError when journey is missing 'legs'" do
      bad = minimal_data
      sellable_journey(bad).delete('legs')
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /legs/)
    end

    it "raises ParseError when journey is missing 'departAt'" do
      bad = minimal_data
      sellable_journey(bad).delete('departAt')
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /departAt/)
    end

    it "raises ParseError when journey is missing 'arriveAt'" do
      bad = minimal_data
      sellable_journey(bad).delete('arriveAt')
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /arriveAt/)
    end

    it "raises ParseError when journey is missing 'duration'" do
      bad = minimal_data
      sellable_journey(bad).delete('duration')
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /duration/)
    end

    it "raises ParseError when a leg is missing 'departureLocation'" do
      bad = minimal_data
      first_leg_id = sellable_journey(bad)['legs'].first
      bad['data']['journeySearch']['legs'][first_leg_id].delete('departureLocation')
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /departureLocation/)
    end

    it "raises ParseError when a leg is missing 'arrivalLocation'" do
      bad = minimal_data
      last_leg_id = sellable_journey(bad)['legs'].last
      bad['data']['journeySearch']['legs'][last_leg_id].delete('arrivalLocation')
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /arrivalLocation/)
    end

    it "raises ParseError when a location is missing 'name'" do
      bad = minimal_data
      journey = sellable_journey(bad)
      first_leg_id = journey['legs'].first
      dep_loc_id = bad['data']['journeySearch']['legs'][first_leg_id]['departureLocation']
      bad['data']['locations'][dep_loc_id].delete('name')
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /name/)
    end

    it "raises ParseError when a section is missing 'alternatives'" do
      bad = minimal_data
      first_section_id = sellable_journey(bad)['sections'].first
      bad['data']['journeySearch']['sections'][first_section_id].delete('alternatives')
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /alternatives/)
    end

    it "raises ParseError when an alternative is missing 'price'" do
      bad = minimal_data
      first_alt_id = bad['data']['journeySearch']['alternatives'].keys.first
      bad['data']['journeySearch']['alternatives'][first_alt_id].delete('price')
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /price/)
    end

    it "raises ParseError when an alternative price is missing 'amount'" do
      bad = minimal_data
      first_alt_id = bad['data']['journeySearch']['alternatives'].keys.first
      bad['data']['journeySearch']['alternatives'][first_alt_id]['price'] = { 'currencyCode' => 'GBP' }
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /amount/)
    end

    it "raises ParseError when an alternative price is missing 'currencyCode'" do
      bad = minimal_data
      first_alt_id = bad['data']['journeySearch']['alternatives'].keys.first
      bad['data']['journeySearch']['alternatives'][first_alt_id]['price'] = { 'amount' => 10.0 }
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /currencyCode/)
    end

    it "raises ParseError when a fare is missing 'fareType'" do
      bad = minimal_data
      first_fare_id = bad['data']['journeySearch']['fares'].keys.first
      bad['data']['journeySearch']['fares'][first_fare_id].delete('fareType')
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /fareType/)
    end

    it "raises ParseError when a fare type is missing 'name'" do
      bad = minimal_data
      first_ft_id = bad['data']['fareTypes'].keys.first
      bad['data']['fareTypes'][first_ft_id].delete('name')
      expect { described_class.new(bad).build }.to raise_error(Bot::Thetrainline::ParseError, /name/)
    end
  end
end

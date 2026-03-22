# frozen_string_literal: true

require 'date'
require_relative 'errors'
require_relative 'journey'

module Bot
  module Thetrainline
    class JourneyFactory
      def initialize(data)
        root = fetch!(data, 'data')
        js   = fetch!(root, 'journeySearch')

        @journeys     = fetch!(js,   'journeys')
        @sections     = fetch!(js,   'sections')
        @alternatives = fetch!(js,   'alternatives')
        @fares        = fetch!(js,   'fares')
        @legs         = fetch!(js,   'legs')
        @locations    = fetch!(root, 'locations')
        @fare_types   = fetch!(root, 'fareTypes')
      end

      def build
        raw_segments = @journeys.values.filter_map { |journey| build_segment(journey) }
        Journey.new(raw_segments)
      end

      private

      def build_segment(journey)
        return nil if journey['unsellableReason']

        sections = fetch!(journey, 'sections')
        return nil if sections.empty?

        leg_ids   = fetch!(journey, 'legs')
        first_leg = leg!(leg_ids.first)
        last_leg  = leg!(leg_ids.last)

        dep_loc = location!(fetch!(first_leg, 'departureLocation'))
        arr_loc = location!(fetch!(last_leg,  'arrivalLocation'))

        {
          departure_station: fetch!(dep_loc, 'name'),
          departure_at: DateTime.parse(fetch!(journey, 'departAt')),
          arrival_station: fetch!(arr_loc, 'name'),
          arrival_at: DateTime.parse(fetch!(journey, 'arriveAt')),
          duration: fetch!(journey, 'duration'),
          changeovers: leg_ids.length - 1,
          section_fares: build_section_fares(sections)
        }
      end

      def build_section_fares(section_ids)
        section_ids.map do |section_id|
          sec = section!(section_id)
          fetch!(sec, 'alternatives').map do |alt_id|
            alt       = alternative!(alt_id)
            fare_id   = fetch!(alt, 'fares').first
            fare      = fare!(fare_id)
            fare_type = fare_type!(fetch!(fare, 'fareType'))
            price     = fetch!(alt, 'price')

            {
              name: fetch!(fare_type, 'name'),
              price_in_cents: (fetch!(price, 'amount') * 100).round,
              currency: fetch!(price, 'currencyCode')
            }
          end
        end
      end

      def fetch!(hash, key)
        value = hash[key]
        raise ParseError, "Missing required key: #{key}" if value.nil?

        value
      end

      def leg!(id)
        @legs.fetch(id) { raise ParseError, "Missing leg: #{id}" }
      end

      def location!(id)
        @locations.fetch(id) { raise ParseError, "Missing location: #{id}" }
      end

      def section!(id)
        @sections.fetch(id) { raise ParseError, "Missing section: #{id}" }
      end

      def alternative!(id)
        @alternatives.fetch(id) { raise ParseError, "Missing alternative: #{id}" }
      end

      def fare!(id)
        @fares.fetch(id) { raise ParseError, "Missing fare: #{id}" }
      end

      def fare_type!(id)
        @fare_types.fetch(id) { raise ParseError, "Missing fare type: #{id}" }
      end
    end
  end
end

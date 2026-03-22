# frozen_string_literal: true

require_relative 'errors'

module Bot
  module Thetrainline
    class Journey
      DURATION_RE = /\AP(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?\z/
      MAX_COMBINATIONS = 10

      attr_reader :segments

      def initialize(raw_segments)
        @segments = raw_segments.map { |s| process(s) }
      end

      def to_station
        Presenter.new(self).to_station
      end

      private

      def process(segment)
        {
          departure_station: segment[:departure_station],
          departure_at: segment[:departure_at],
          arrival_station: segment[:arrival_station],
          arrival_at: segment[:arrival_at],
          duration_in_minutes: parse_duration(segment[:duration]),
          changeovers: segment[:changeovers],
          fares: combine_fares(segment[:section_fares])
        }
      end

      def parse_duration(iso)
        m = DURATION_RE.match(iso)
        raise ParseError, "Unsupported duration format: #{iso}" unless m

        (m[1].to_i * 1440) + (m[2].to_i * 60) + m[3].to_i
      end

      def combine_fares(section_fares)
        return [] if section_fares.empty?
        return section_fares.first if section_fares.length == 1

        section_fares.reduce do |combos, section_alts|
          merged = combos.flat_map do |combo|
            section_alts.map do |alt|
              if alt[:currency] != combo[:currency]
                raise ParseError, "Cannot combine fares: mixed currencies #{combo[:currency]} and #{alt[:currency]}"
              end

              {
                name: "#{combo[:name]} + #{alt[:name]}",
                price_in_cents: combo[:price_in_cents] + alt[:price_in_cents],
                currency: combo[:currency]
              }
            end
          end
          merged.sort_by { |f| f[:price_in_cents] }.first(MAX_COMBINATIONS)
        end
      end

      class Presenter
        def initialize(journey)
          @journey = journey
        end

        def to_station
          @journey.segments.map do |seg|
            seg.merge(service_agencies: ['thetrainline'], products: ['train'])
          end
        end
      end
    end
  end
end

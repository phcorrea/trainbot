# frozen_string_literal: true

require 'json'
require 'date'
require 'tzinfo'
require_relative 'errors'

module Bot
  module Thetrainline
    class Fetcher
      FIXTURES_DIR = File.expand_path('../../../fixtures', __dir__)
      FIXTURE_TZ   = TZInfo::Timezone.get('Europe/Berlin')

      def initialize(from, to, departure_at)
        @from = from
        @to = to
        @departure_at = departure_at
      end

      def fetch
        path = File.join(FIXTURES_DIR, fixture_filename)
        raise ArgumentError, "No fixture for '#{@from}' -> '#{@to}' (expected #{path})" unless File.exist?(path)

        data = JSON.parse(File.read(path))
        apply_departure_filter(data)
        data
      end

      private

      def apply_departure_filter(data)
        journeys = data.dig('data', 'journeySearch', 'journeys')
        return unless journeys

        journeys.each_value do |journey|
          next if journey['unsellableReason']
          next if journey['departAt'].nil? || journey['arriveAt'].nil?

          offset = @departure_at.to_date - Date.parse(journey['departAt'])
          journey['departAt'] = shift_datetime(journey['departAt'], offset)
          journey['arriveAt'] = shift_datetime(journey['arriveAt'], offset)
        end

        journeys.reject! do |_id, journey|
          journey['unsellableReason'] ||
            journey['departAt'].nil? ||
            journey['arriveAt'].nil? ||
            DateTime.parse(journey['departAt']) < @departure_at
        end
      end

      def shift_datetime(iso_str, offset_days)
        original    = DateTime.parse(iso_str)
        target_date = original.to_date + offset_days
        local_time  = Time.new(target_date.year, target_date.month, target_date.day,
                               original.hour, original.minute, original.second)

        periods = FIXTURE_TZ.periods_for_local(local_time)
        period  = periods.first || FIXTURE_TZ.period_for_utc(local_time.utc)

        utc_offset = period.utc_total_offset
        DateTime.new(target_date.year, target_date.month, target_date.day,
                     original.hour, original.minute, original.second,
                     Rational(utc_offset, 86_400))
                .strftime('%Y-%m-%dT%H:%M:%S%:z')
      end

      def fixture_filename
        "#{slugify(@from)}_#{slugify(@to)}.json"
      end

      def slugify(str)
        str.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_|_\z/, '')
      end
    end
  end
end

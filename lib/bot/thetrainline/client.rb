# frozen_string_literal: true

require_relative 'fetcher'
require_relative 'journey_factory'

module Bot
  module Thetrainline
    def self.find(from, to, departure_at)
      data = Fetcher.new(from, to, departure_at).fetch
      journey = JourneyFactory.new(data).build
      journey.to_station
    end
  end
end

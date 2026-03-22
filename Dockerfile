FROM ruby:3.4-slim

WORKDIR /app

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="" \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential \
  && rm -rf /var/lib/apt/lists/*

COPY Gemfile* ./
RUN bundle install

COPY . .


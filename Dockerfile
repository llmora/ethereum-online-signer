# Base image:
FROM ruby:2.3-slim

# Install dependencies
RUN apt-get update -qq && apt-get install -y git gcc make g++

# Set production mode for rack
ENV RACK_ROOT /var/www/api
ENV RACK_ENV production


# Set working directory, where the commands will be ran:
RUN mkdir -p $RACK_ROOT
WORKDIR $RACK_ROOT

# Gems:
COPY Gemfile Gemfile
COPY Gemfile.lock Gemfile.lock

RUN gem install bundler
RUN bundle install --deployment --without development test

# COPY config/puma.rb config/puma.rb

# Copy the main application.
COPY . .

EXPOSE 3000

# The default command that gets ran will be to start the Puma server.
CMD bundle exec rackup config.ru -p 3000

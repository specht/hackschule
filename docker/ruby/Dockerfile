FROM ruby:3-buster
MAINTAINER Dr. Michael Specht <specht@quelltextschmiede.de>

RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y curl bash ruby-dev imagemagick docker tzdata && rm -rf /var/cache/apt/*
RUN cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime && echo "Europe/Berlin" > /etc/timezone
RUN gem install bundler
ADD Gemfile /
ADD credentials.rb /
RUN bundle install
RUN useradd -u 1000 michael
RUN groupadd docker
RUN groupadd ping
RUN usermod -a -G docker michael
RUN usermod -a -G ping michael
USER michael

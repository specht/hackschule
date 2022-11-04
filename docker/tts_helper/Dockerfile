FROM ruby:3-alpine

RUN apk update && apk upgrade
RUN apk add curl bash curl-dev ruby-dev build-base tzdata sox ffmpeg youtube-dl && rm -rf /var/cache/apk/*
RUN cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime && echo "Europe/Berlin" > /etc/timezone
RUN gem install bundler
ADD Gemfile /
RUN bundle install
RUN adduser -D -u 1000 michael
USER michael

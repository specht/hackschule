FROM ruby:3-buster
MAINTAINER Dr. Michael Specht <specht@quelltextschmiede.de>

RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
RUN echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
RUN apt-get update
RUN apt-get install -y bash ruby-dev imagemagick docker-ce docker-ce-cli containerd.io tzdata && rm -rf /var/cache/apt/*
RUN cp /usr/share/zoneinfo/Europe/Berlin /etc/localtime && echo "Europe/Berlin" > /etc/timezone
RUN gem install bundler
ADD Gemfile /
ADD credentials.rb /
RUN bundle install
RUN useradd -u 1000 michael
RUN usermod -aG docker michael
RUN touch /var/run/docker.sock && chmod 666 /var/run/docker.sock
#USER michael

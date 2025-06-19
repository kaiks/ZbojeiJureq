# see https://github.com/evilmartians/fullstaq-ruby-docker
ARG RUBY_VERSION=3.4.4-jemalloc-bookworm

FROM quay.io/evl.ms/fullstaq-ruby:${RUBY_VERSION}-slim

RUN apt-get update -q \
   && apt-get install --assume-yes -q --no-install-recommends \
     curl \
     nano \
     build-essential \
     libsqlite3-dev \
     git

ENV APP_HOME /ZbojeiJureq
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

# Copy over our application code
ADD . .
RUN apt-get update -q \
   && apt-get install --assume-yes -q --no-install-recommends \
     ./tools/ripgrep_14.1.1-1_amd64.deb
RUN gem install bundler -v 2.4.22
RUN bundle install
CMD ruby main.rb

# see https://github.com/evilmartians/fullstaq-ruby-docker
ARG RUBY_VERSION=2.6.9-jemalloc-bullseye

FROM quay.io/evl.ms/fullstaq-ruby:${RUBY_VERSION}-slim

RUN apt-get update -q \
   && apt-get install --assume-yes -q --no-install-recommends \
     curl \
     nano \
     build-essential \
     libsqlite3-dev

ENV APP_HOME /ZbojeiJureq
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

# Copy over our application code
ADD . .
RUN chmod +x tools/sift
RUN gem install bundler -v 2.4.22
RUN bundle install
CMD ruby main.rb

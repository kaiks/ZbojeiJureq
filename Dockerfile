ARG RUBY_VERSION=4.0.2-slim-bookworm

FROM ruby:${RUBY_VERSION}

RUN apt-get update -q \
   && apt-get install --assume-yes -q --no-install-recommends \
     curl \
     nano \
     build-essential \
     pkg-config \
     libsqlite3-dev \
     git

ENV APP_HOME=/ZbojeiJureq
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

# Copy over our application code
ADD . .
RUN apt-get update -q \
   && apt-get install --assume-yes -q --no-install-recommends \
     ./tools/ripgrep_14.1.1-1_amd64.deb
RUN gem install bundler -v 2.3.7
RUN bundle _2.3.7_ config set build.sqlite3 --enable-system-libraries \
   && bundle _2.3.7_ install
CMD ["ruby", "main.rb"]

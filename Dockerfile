ARG RUBY_VERSION=4.0.5-slim-bookworm
ARG APP_UID=1000

FROM ruby:${RUBY_VERSION}

ARG APP_UID

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
COPY . .
RUN apt-get update -q \
   && apt-get install --assume-yes -q --no-install-recommends \
     ./tools/ripgrep_14.1.1-1_amd64.deb
RUN gem install bundler -v 2.3.7
RUN bundle _2.3.7_ config set build.sqlite3 --enable-system-libraries \
   && bundle _2.3.7_ install
RUN useradd --create-home --uid "$APP_UID" --user-group zbojeijureq \
   && chown -R zbojeijureq:zbojeijureq "$APP_HOME"
USER zbojeijureq
CMD ["ruby", "main.rb"]

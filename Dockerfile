ARG DEBIAN_IMAGE
 
FROM debian:buster
 
ARG RUBY_VERSION=2.6.7
ARG RUBY_VARIANT=jemalloc
ARG DEBIAN_VERSION=10
 
 
 
# RUN with pipe recommendation: https://github.com/hadolint/hadolint/wiki/DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update -q \
   && apt-get dist-upgrade --assume-yes \
   && apt-get install --assume-yes -q --no-install-recommends \
     curl \
     gnupg \
     apt-transport-https \
     ca-certificates \
     nano \
   && curl -SLf https://raw.githubusercontent.com/fullstaq-labs/fullstaq-ruby-server-edition/main/fullstaq-ruby.asc | apt-key add - \
   && echo "deb https://apt.fullstaqruby.org debian-${DEBIAN_VERSION} main" > /etc/apt/sources.list.d/fullstaq-ruby.list \
   && echo "deb http://deb.debian.org/debian buster main" > /etc/apt/sources.list.d/main-list.list \
   && apt-get update -q \
   && apt-get install --assume-yes -q --no-install-recommends fullstaq-ruby-${RUBY_VERSION}-${RUBY_VARIANT} \
   && apt-get install --assume-yes -q build-essential libsqlite3-dev \
   && apt-get autoremove --assume-yes \
   && rm -rf /var/lib/apt/lists \
   && rm -fr /var/cache/apt \
   && rm /etc/apt/sources.list.d/fullstaq-ruby.list
 
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_PATH="$GEM_HOME" \
   BUNDLE_SILENCE_ROOT_WARNING=1 \
   BUNDLE_APP_CONFIG="$GEM_HOME" \
   RUBY_VERSION=${RUBY_VERSION}-${RUBY_VARIANT} \
   LANG=C.UTF-8 LC_ALL=C.UTF-8
 
# path recommendation: https://github.com/bundler/bundler/pull/6469#issuecomment-383235438
ENV PATH $GEM_HOME/bin:$BUNDLE_PATH/gems/bin:/usr/lib/fullstaq-ruby/versions/${RUBY_VERSION}/bin:$PATH


ENV APP_HOME /ZbojeiJureq
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

# Copy over our application code
ADD . .
RUN gem install bundler
RUN bundle install
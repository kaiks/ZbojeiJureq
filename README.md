# ZbojeiJureq
cinch-based irc bot with many plugins

Currently runs on mri (tested on 4.0.5) and should work on all distributions on which gems run (e.g. some versions of jruby)

## Installation
Install the bundle, create the runtime database directory, and copy the
configuration and empty database templates into their expected locations:

    bundle install
    cp config.rb.template config.rb
    mkdir -p db logs
    cp ZbojeiJureq.db.template db/ZbojeiJureq.db
    cp talk.db.template db/talk.db
    cp uno.db.template db/uno.db

## Configuration
To configure, you'll need to edit config.rb

## Running
To run

    ruby main.rb


## Plugins
Some of the included plugins:

 - wunderground-based weather plugin
 - [az game plugin](https://zboje.kaiks.eu/docs/index.html#az-plugin)
 - [uno game plugin](https://zboje.kaiks.eu/docs/index.html#uno-plugin)
 - currency converting plugin
 - real-time cryptocurrency prices plugin
 - [timer](https://zboje.kaiks.eu/docs/index.html#timer-plugin)
 - [leaving notes](https://zboje.kaiks.eu/docs/index.html#note-plugin)
 - saving and looking through notes
 - authentication management
 - wolframalpha interaction
 - much more

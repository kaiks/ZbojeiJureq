# ZbojeiJureq
cinch-based irc bot with many plugins

Currently runs on JRuby (tested on JRuby 1.7.26 with option --2.0) and SQLite.

## Installation
To install, first install bundle, and then: 

    bundle install

Then delete .template file extension from all template files.

## Configuration
To configure, you'll need to edit config.rb

## Running 
To run

    jruby --2.0 -S main.rb


## Plugins
Some of the included plugins:

 - wunderground-based weather plugin
 - [az game plugin](http://kx.shst.pl/help/az.html)
 - [uno game plugin](http://kx.shst.pl/help/uno.html)
 - google-based currency converting plugin
 - btc ticker
 - timer
 - leaving notes
 - saving and looking through notes
 - authentication management

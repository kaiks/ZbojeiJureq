source 'https://rubygems.org'
if RUBY_PLATFORM == 'java'
    gem 'jdbc-sqlite3'
  else
    if RUBY_PLATFORM =~ /mingw/i
      # you might have to do this upfront
      # ridk exec pacman -Syu (repeatedly, until there's nothing left to install)
      # ridk exec pacman -S mingw-w64-x86_64-dlfcn
      # ridk exec pacman -S mingw-w64-x86_64-clang
      gem "sqlite3"
    else
      gem 'sqlite3'
    end
end

gem 'sequel'

gem 'cinch'


#Plugins:
gem 'cinch-identify'
gem 'dentaku'
gem 'money'
#gem 'google_currency'
gem 'money-oxr'
#gem 'ruby-fann'
gem 'rollbar'
gem 'http'
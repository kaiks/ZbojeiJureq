source 'https://rubygems.org'

ruby '>= 3.2'

# Use Cinch fork directly from GitHub
gem 'cinch', git: 'https://github.com/blolol/cinch.git'

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

# Game engine gem
gem 'jedna', github: 'kaiks/jedna'

# Ruby 3.4+ extracted standard libraries
gem 'base64' if RUBY_VERSION >= '3.4'
gem 'net-ftp' if RUBY_VERSION >= '3.1'

#Plugins:
gem 'cinch-identify'
gem 'dentaku'
gem 'money'
#gem 'google_currency'
gem 'money-oxr'
#gem 'ruby-fann'
gem 'rollbar'
gem 'http'

group :test do
  gem 'rspec', '~> 3.12'
  gem 'webmock', '~> 3.19'
  gem 'timecop', '~> 0.9'
end
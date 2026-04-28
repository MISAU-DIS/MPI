source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.2.0'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'activejob-uniqueness', require: 'active_job/uniqueness/sidekiq_patch'
gem 'activerecord-import'
gem 'bundler'
gem 'kramdown'
gem 'multi_json'
gem 'parallel'
gem 'rails', '~> 7.0.6'
gem 'rake'
gem 'rspec'
gem 'rswag'
gem 'sidekiq', '~> 7.3.0'
gem 'sidekiq-cron'
gem 'whenever', require: false
gem "connection_pool", "< 3.0"
# Use mysql as the database for Active Record
gem 'mysql2', '>= 0.4.4', '< 0.6.0'
# Use Puma as the app server
gem 'puma', '~> 6.3'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
# gem 'jbuilder', '~> 2.5'
# Use Redis adapter to run Action Cable in production
gem 'redis', '~> 4.0'
# Use ActiveModel has_secure_password
gem 'bcrypt', '~> 3.1.7'

gem 'rest-client'

gem 'net-ping'

# Use ActiveStorage variant
# gem 'mini_magick', '~> 4.8'

# Use Capistrano for deployment
# gem 'capistrano-rails', group: :development

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', '>= 1.1.0', require: false

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
gem 'rack-cors'

gem 'jwt'
gem 'simple_command'

#matching algorithm
gem 'whitesimilarity'

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'rspec-rails'
end

group :test do
  #gem 'simplecov', require: false
end

group :development do
  gem 'listen'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'
end


# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]

gem 'his_emr_user_management', '~> 0.1.2'
gem "turbo-rails", "~> 2.0"

gem "importmap-rails"

gem "sprockets-rails"

gem "tailwindcss-rails", "~> 2.7"

# Loads ENV vars from .env in development/test
gem 'dotenv-rails', groups: [:development, :test]

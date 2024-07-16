source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.2.0"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.0.4", ">= 7.0.4.3"

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", "~> 5.0"

# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"

# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"

# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Redis adapter to run Action Cable in production
gem "redis", "~> 4.0"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[mingw mswin x64_mingw jruby]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Sass to process CSS
# gem "sassc-rails"

gem "mongoid"

gem "org-ruby" # org-mode markup renderer
gem "redcarpet" # markdown renderer
gem "reverse_markdown"
gem "pygments.rb"
gem "meilisearch"
gem "mongodb_meilisearch"
gem "pagy", "~> 6.0"
gem "mongoid-pagination"
gem "dotenv-rails"
gem "omniauth"
gem "devise"
gem "daemons" # used by Delayed Job
# official Delayed Job https://github.com/collectiveidea/delayed_job MongoDB support
gem "delayed_job_mongoid"
# gem "delayed_job_web" # instructions here: https://github.com/ejschmitt/delayed_job_web
gem "public_suffix" # for extracting domain names from urls

gem "gemoji"

gem "whirly" # spinner for rake tasks
gem "paint"  # colorize terminal output (mostly for whirly)

gem "httparty" # for importer to check if urls are serving.

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
end

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[mri mingw x64_mingw]
  gem "rspec-rails"
  gem "standard"
  gem "rubocop-rails"
  gem "rubocop-rspec"
  gem "rubocop-factory_bot"
end

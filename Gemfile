source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "propshaft"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"

# Background jobs
gem "sidekiq", "~> 7.0"
gem "sidekiq-cron", "~> 1.12"
# connection_pool 3.0 changed pop() to keyword args; sidekiq 7.x still uses positional
gem "connection_pool", "~> 2.4"

# Audit trail on Article model
gem "audited", "~> 5.0"

# HTTP client (NewsAPI + Telegram)
gem "faraday", "~> 2.0"
gem "faraday-retry", "~> 2.0"

# AI relevance filtering
gem "ruby-openai", "~> 7.0"

gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
end

group :development do
  gem "web-console"
end

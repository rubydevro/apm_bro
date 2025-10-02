# ApmBro

Minimal APM for Rails apps. Automatically measures each controller action's total time and posts it to a remote endpoint with an API key read from your app's settings/credentials/env.

## Installation

Add to your Gemfile:

```ruby
gem "apm_bro", git: "https://github.com/your-org/apm_bro.git"
```

Or install locally for development:

```bash
bundle exec rake install
```

## Usage

By default, if Rails is present, ApmBro auto-subscribes to `process_action.action_controller` and posts metrics asynchronously.

### Configure API key and endpoint

You can set via any of the following (priority top to bottom):

- Rails `config.x.apm_bro` in `config/application.rb` or `environments/*.rb`:

```ruby
config.x.apm_bro.api_key = ENV.fetch("APM_BRO_API_KEY", nil)
config.x.apm_bro.enabled = true
```

- `config/apm_bro.yml` (via `Rails.application.config_for(:apm_bro)`):

```yml
default: &default
  api_key: <%= ENV["APM_BRO_API_KEY"] %>
  host: <%= ENV["APM_BRO_HOST"] %>

development:
  <<: *default

production:
  <<: *default
```

- Rails credentials:

```yaml
apm_bro:
  api_key: YOUR_KEY
  host: https://apm.example.com
```

- Environment variables:

- `APM_BRO_API_KEY`
- `APM_BRO_ENDPOINT_URL` (or `APM_BRO_HOST` to be combined with `/v1/metrics`)

### Manual configuration (non-Rails)

```ruby
ApmBro.configure do |cfg|
  cfg.api_key = ENV["APM_BRO_API_KEY"]
  cfg.endpoint_url = "https://apm.example.com/v1/metrics"
end

ApmBro::Subscriber.subscribe!(client: ApmBro::Client.new)
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/apm_bro.

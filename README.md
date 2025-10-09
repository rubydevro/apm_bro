# ApmBro

Minimal APM for Rails apps. Automatically measures each controller action's total time, tracks SQL queries, and posts metrics to a remote endpoint with an API key read from your app's settings/credentials/env.

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
config.x.apm_bro.track_sql_queries = true
config.x.apm_bro.max_sql_queries = 50
config.x.apm_bro.sanitize_sql_queries = true
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
  cfg.track_sql_queries = true
  cfg.max_sql_queries = 50
  cfg.sanitize_sql_queries = true
end

ApmBro::Subscriber.subscribe!(client: ApmBro::Client.new)
```

## SQL Query Tracking

ApmBro automatically tracks SQL queries executed during each request when `track_sql_queries` is enabled (default: true). The following configuration options are available:

- `track_sql_queries` (boolean, default: true) - Enable/disable SQL query tracking
- `max_sql_queries` (integer, default: 50) - Maximum number of queries to track per request
- `sanitize_sql_queries` (boolean, default: true) - Sanitize sensitive data from SQL queries

When enabled, each request payload will include a `sql_queries` array containing:
- `sql` - The SQL query (sanitized if enabled)
- `name` - Query name (e.g., "User Load", "User Update")
- `duration_ms` - Query execution time in milliseconds
- `cached` - Whether the query was cached
- `connection_id` - Database connection ID

Example payload:
```json
{
  "event": "process_action.action_controller",
  "payload": {
    "controller": "UsersController",
    "action": "show",
    "duration_ms": 150.25,
    "sql_queries": [
      {
        "sql": "SELECT * FROM users WHERE id = ?",
        "name": "User Load",
        "duration_ms": 12.5,
        "cached": false,
        "connection_id": 123
      }
    ]
  }
}
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/apm_bro.

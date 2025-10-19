# ApmBro

Minimal APM for Rails apps. Automatically measures each controller action's total time, tracks SQL queries, monitors view rendering performance, tracks memory usage and detects leaks, monitors background jobs, and posts metrics to a remote endpoint with an API key read from your app's settings/credentials/env.

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

## SQL Query Tracking

ApmBro automatically tracks SQL queries executed during each request and job. Each request payload will include a `sql_queries` array containing:
- `sql` - The SQL query (always sanitized)
- `name` - Query name (e.g., "User Load", "User Update")
- `duration_ms` - Query execution time in milliseconds
- `cached` - Whether the query was cached
- `connection_id` - Database connection ID
- `trace` - Call stack showing where the query was executed

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
        "connection_id": 123,
        "trace": [
          "app/models/user.rb:105:in `map'",
          "app/models/user.rb:105:in `agency_permissions_for'",
          "app/services/permissions_service.rb:29:in `setup'",
          "app/controllers/application_controller.rb:192:in `new'"
        ]
      }
    ]
  }
}
```

## View Rendering Tracking

ApmBro automatically tracks view rendering performance for each request. This includes:

- **Individual view events**: Templates, partials, and collections rendered
- **Performance metrics**: Rendering times for each view component
- **Cache analysis**: Cache hit rates for partials and collections
- **Slow view detection**: Identification of the slowest rendering views
- **Frequency analysis**: Most frequently rendered views

Each request payload includes:
- `view_events` - Array of individual view rendering events
- `view_performance` - Aggregated performance analysis

Example view performance data:
```json
{
  "view_performance": {
    "total_views_rendered": 15,
    "total_view_duration_ms": 45.2,
    "average_view_duration_ms": 3.01,
    "by_type": {
      "template": 1,
      "partial": 12,
      "collection": 2
    },
    "slowest_views": [
      {
        "identifier": "users/_user_card.html.erb",
        "duration_ms": 8.5,
        "type": "partial"
      }
    ],
    "partial_cache_hit_rate": 75.0,
    "collection_cache_hit_rate": 60.0
  }
}
```

## Memory Tracking & Leak Detection

ApmBro automatically tracks memory usage and detects memory leaks with minimal performance impact. This includes:

### Performance-Optimized Memory Tracking

By default, ApmBro uses **lightweight memory tracking** that has minimal performance impact:

- **Memory Usage Monitoring**: Track memory consumption per request (using GC stats, not system calls)
- **Memory Leak Detection**: Detect growing memory patterns over time
- **GC Efficiency Analysis**: Monitor garbage collection effectiveness
- **Zero Allocation Tracking**: No object allocation tracking by default (can be enabled)

### Configuration Options

```ruby
# In your Rails configuration
ApmBro.configure do |config|
  config.memory_tracking_enabled = true        # Enable lightweight memory tracking (default: true)
  config.allocation_tracking_enabled = false   # Enable detailed allocation tracking (default: false)
end
```

**Performance Impact:**
- **Lightweight mode**: ~0.1ms overhead per request
- **Allocation tracking**: ~2-5ms overhead per request (only enable when needed)

Each request payload includes:
- `memory_events` - Detailed memory tracking data
- `memory_performance` - Aggregated memory analysis

Example memory performance data:
```json
{
  "memory_performance": {
    "memory_growth_mb": 2.5,
    "total_allocations": 1250,
    "total_allocated_size_mb": 15.8,
    "allocations_per_second": 125.0,
    "top_allocating_classes": [
      {
        "class_name": "String",
        "count": 500,
        "size": 8000000,
        "size_mb": 8.0
      }
    ],
    "large_objects": {
      "count": 2,
      "total_size_mb": 3.2,
      "largest_object_mb": 2.1
    },
    "gc_efficiency": {
      "gc_count_increase": 3,
      "heap_pages_increase": 2,
      "objects_allocated": 1250
    }
  }
}
```

### Memory Helper Methods

Use `ApmBro::MemoryHelpers` for manual memory monitoring:

```ruby
# Take a memory snapshot
ApmBro::MemoryHelpers.snapshot("before_heavy_operation")

# Monitor memory during a block
ApmBro::MemoryHelpers.monitor_memory("data_processing") do
  # Your code here
  process_large_dataset
end

# Check for memory leaks
ApmBro::MemoryHelpers.check_for_leaks

# Get memory summary
ApmBro::MemoryHelpers.memory_summary
```

## Job Tracking

ApmBro automatically tracks ActiveJob background jobs when ActiveJob is available. Each job execution is tracked with:

- `job_class` - The job class name (e.g., "UserMailer::WelcomeEmail")
- `job_id` - Unique job identifier
- `queue_name` - The queue the job was processed from
- `arguments` - Sanitized job arguments (sensitive data filtered)
- `duration_ms` - Job execution time in milliseconds
- `status` - "completed" or "failed"
- `sql_queries` - Array of SQL queries executed during the job
- `exception_class` - Exception class name (for failed jobs)
- `message` - Exception message (for failed jobs)
- `backtrace` - Exception backtrace (for failed jobs)

Example successful job payload:
```json
{
  "event": "perform.active_job",
  "payload": {
    "job_class": "UserMailer::WelcomeEmail",
    "job_id": "abc123",
    "queue_name": "mailers",
    "arguments": ["user@example.com", "John Doe"],
    "duration_ms": 1250.5,
    "status": "completed",
    "sql_queries": [
      {
        "sql": "SELECT * FROM users WHERE email = ?",
        "name": "User Load",
        "duration_ms": 12.5,
        "cached": false,
        "connection_id": 123,
        "trace": [
          "app/jobs/user_mailer_job.rb:15:in `perform'",
          "app/models/user.rb:42:in `welcome_email'"
        ]
      }
    ],
    "rails_env": "production"
  }
}
```

Example failed job payload:
```json
{
  "event": "StandardError",
  "payload": {
    "job_class": "DataProcessorJob",
    "job_id": "def456",
    "queue_name": "default",
    "arguments": [123],
    "duration_ms": 500.0,
    "status": "failed",
    "sql_queries": [
      {
        "sql": "UPDATE data SET status = ? WHERE id = ?",
        "name": "Data Update",
        "duration_ms": 8.2,
        "cached": false,
        "connection_id": 123,
        "trace": [
          "app/jobs/data_processor_job.rb:15:in `perform'",
          "app/models/data.rb:42:in `process'"
        ]
      }
    ],
    "exception_class": "StandardError",
    "message": "Connection timeout",
    "backtrace": ["app/jobs/data_processor_job.rb:15", "lib/processor.rb:42"]
  },
  "error": true
}
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/apm_bro.

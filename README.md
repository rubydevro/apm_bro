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
config.x.apm_bro.sample_rate = 50  # Track 50% of requests
```

- `config/apm_bro.yml` (via `Rails.application.config_for(:apm_bro)`):

```yml
default: &default
  api_key: <%= ENV["APM_BRO_API_KEY"] %>
  host: <%= ENV["APM_BRO_HOST"] %>
  sample_rate: 100

development:
  <<: *default
  sample_rate: 50  # Track fewer requests in development

production:
  <<: *default
  sample_rate: 25  # Track 25% of requests in production
```

- Rails credentials:

```yaml
apm_bro:
  api_key: YOUR_KEY
  host: https://apm.example.com
  sample_rate: 50
  deploy_id: 2025-10-20-1
```

- Environment variables:

- `APM_BRO_API_KEY`
- `APM_BRO_ENDPOINT_URL` (or `APM_BRO_HOST` to be combined with `/v1/metrics`)
- `APM_BRO_SAMPLE_RATE` (integer 1-100)
- `APM_BRO_DEPLOY_ID` (override boot UUID for deploy tracking)

### Manual configuration (non-Rails)

```ruby
ApmBro.configure do |cfg|
  cfg.api_key = ENV["APM_BRO_API_KEY"]
  cfg.endpoint_url = "https://apm.example.com/v1/metrics"
end

ApmBro::Subscriber.subscribe!(client: ApmBro::Client.new)
```

## User Email Tracking

ApmBro can track the email of the user making requests, which is useful for debugging user-specific issues and understanding user behavior patterns.

### Configuration

Enable user email tracking in your Rails configuration:

```ruby
# In config/application.rb or environments/*.rb
ApmBro.configure do |config|
  config.user_email_tracking_enabled = true
end
```

### Default Email Extraction

By default, ApmBro will try to extract user email from these sources (in order of priority):

1. **`current_user.email`** - Most common in Rails apps with authentication
2. **Request parameters** - `user_email` or `email` in params
3. **HTTP headers** - `X-User-Email` or `HTTP_X_USER_EMAIL`
4. **Session data** - `user_email` in session

### Custom Email Extractor

For more complex scenarios, you can provide a custom extractor:

```ruby
ApmBro.configure do |config|
  config.user_email_tracking_enabled = true
  config.user_email_extractor = ->(request_data) do
    # Custom logic to extract user email
    if request_data[:current_user]&.respond_to?(:email)
      request_data[:current_user].email
    elsif request_data[:jwt_token]
      # Extract from JWT token
      JWT.decode(request_data[:jwt_token], secret)[0]["email"]
    end
  end
end
```

### Example Payload with User Email

```json
{
  "event": "process_action.action_controller",
  "payload": {
    "controller": "UsersController",
    "action": "show",
    "method": "GET",
    "path": "/users/123",
    "status": 200,
    "duration_ms": 150.25,
    "user_email": "john.doe@example.com",
    "rails_env": "production",
    "host": "myapp.com",
    "sql_queries": [...],
    "view_events": [...],
    "memory_events": [...]
  }
}
```

### Security Considerations

- User email tracking is **disabled by default** for privacy
- Only enable when necessary for debugging or analytics
- Consider your data privacy requirements and regulations
- The email is included in all request payloads sent to your APM endpoint

## Request Sampling

ApmBro supports configurable request sampling to reduce the volume of metrics sent to your APM endpoint, which is useful for high-traffic applications.

### Configuration

Set the sample rate as a percentage (1-100):

```ruby
# Track 50% of requests
ApmBro.configure do |config|
  config.sample_rate = 50
end

# Track 10% of requests (useful for high-traffic apps)
ApmBro.configure do |config|
  config.sample_rate = 10
end

# Track all requests (default)
ApmBro.configure do |config|
  config.sample_rate = 100
end
```

### How It Works

- **Random Sampling**: Each request has a random chance of being tracked based on the sample rate
- **Consistent Per-Request**: The sampling decision is made once per request and applies to all metrics for that request
- **Debug Logging**: Skipped requests are logged at debug level for monitoring
- **Error Tracking**: Errors are still tracked regardless of sampling (unless explicitly disabled)

### Use Cases

- **High-Traffic Applications**: Reduce APM data volume and costs
- **Development/Staging**: Sample fewer requests to reduce noise
- **Performance Testing**: Track a subset of requests during load testing
- **Cost Optimization**: Balance monitoring coverage with data costs

### Example

With `sample_rate = 25`, approximately 25% of requests will be tracked:

```ruby
# This request might be tracked (25% chance)
GET /users/123

# This request might be skipped (75% chance)  
GET /users/456

# Both requests will show in debug logs:
# "ApmBro sampling: skipping metric process_action.action_controller (sample rate: 25%)"
```

## Excluding Controllers and Jobs

You can exclude specific controllers and jobs from APM tracking.

### Configuration

Rails config (`config/application.rb` or environment files):

```ruby
ApmBro.configure do |config|
  config.excluded_controllers = [
    "HealthChecksController",
    "Admin::*" # wildcard supported
  ]

  config.excluded_controller_actions = [
    "UsersController#show",
    "Admin::ReportsController#index",
    "Admin::*#*" # wildcard supported for controller and action
  ]

  config.excluded_jobs = [
    "ActiveStorage::AnalyzeJob",
    "Admin::*"
  ]
end
```

YAML config (`config/apm_bro.yml`):

```yml
default: &default
  excluded_controllers:
    - HealthChecksController
    - Admin::*
  excluded_controller_actions:
    - UsersController#show
    - Admin::ReportsController#index
    - Admin::*#*
  excluded_jobs:
    - ActiveStorage::AnalyzeJob
    - Admin::*

development:
  <<: *default

production:
  <<: *default
```

Environment variables:

```bash
export APM_BRO_EXCLUDED_CONTROLLERS="HealthChecksController,Admin::*"
export APM_BRO_EXCLUDED_CONTROLLER_ACTIONS="UsersController#show,Admin::*#*"
export APM_BRO_EXCLUDED_JOBS="ActiveStorage::AnalyzeJob,Admin::*"
```

Notes:
- Wildcards `*` are supported for controller and action (e.g., `Admin::*#*`).
- Matching is done against full names like `UsersController`, `Admin::ReportsController#index`, `MyJob`.

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
  
  # Circuit breaker configuration
  config.circuit_breaker_enabled = true        # Enable circuit breaker (default: true)
  config.circuit_breaker_failure_threshold = 3 # Failures before opening circuit (default: 3)
  config.circuit_breaker_recovery_timeout = 60 # Seconds before trying to close circuit (default: 60)
  config.circuit_breaker_retry_timeout = 300   # Seconds before retry attempts (default: 300)
  
  # Sampling configuration
  config.sample_rate = 100                     # Percentage of requests to track (1-100, default: 100)
end
```

**Performance Impact:**
- **Lightweight mode**: ~0.1ms overhead per request
- **Allocation tracking**: ~2-5ms overhead per request (only enable when needed)

## Circuit Breaker Protection

ApmBro includes a circuit breaker pattern to prevent repeated failed requests when the endpoint is unavailable or returns unauthorized responses.

### How It Works

1. **Closed State**: Normal operation, requests are sent
2. **Open State**: After 3 consecutive failures, circuit opens and blocks requests
3. **Half-Open State**: After recovery timeout, allows one test request
4. **Auto-Recovery**: Automatically closes circuit when requests succeed

### Circuit Breaker States

- **Closed**: All requests pass through normally
- **Open**: All requests are blocked (returns immediately)
- **Half-Open**: One test request allowed to check if service recovered

### Benefits

- **Prevents API Spam**: Stops sending requests when endpoint is down
- **Reduces Network Traffic**: Avoids unnecessary HTTP calls
- **Improves Performance**: Failed requests return immediately
- **Auto-Recovery**: Automatically resumes when service is back

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

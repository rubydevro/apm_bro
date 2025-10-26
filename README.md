# ApmBro (Beta Version)

Minimal APM for Rails apps. Automatically measures each controller action's total time, tracks SQL queries, monitors view rendering performance, tracks memory usage and detects leaks, monitors background jobs, and posts metrics to a remote endpoint with an API key read from your app's settings/credentials/env.

To use the gem you need to have a free account with [DeadBro - Rails APM](https://www.deadbro.com)

## Installation

Add to your Gemfile:

```ruby
gem "apm_bro", git: "https://github.com/rubydevro/apm_bro.git"
```

## Usage

By default, if Rails is present, ApmBro auto-subscribes to `process_action.action_controller` and posts metrics asynchronously.

### Configuration settings

You can set via an initializer:


```ruby
ApmBro.configure do |cfg|
  cfg.api_key = ENV["APM_BRO_API_KEY"]
  cfg.enabled = true
end
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

In progress

### Security Considerations

- User email tracking is **disabled by default** for privacy
- Only enable when necessary for debugging or analytics
- Consider your data privacy requirements and regulations
- The email is included in all request payloads sent to our APM endpoint

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
- **Debug Logging**: Skipped requests do not count towards the montly limit
- **Error Tracking**: Errors are still tracked regardless of sampling

### Use Cases

- **High-Traffic Applications**: Reduce APM data volume and costs
- **Development/Staging**: Sample fewer requests to reduce noise
- **Performance Testing**: Track a subset of requests during load testing
- **Cost Optimization**: Balance monitoring coverage with data costs


## Excluding Controllers and Jobs

You can exclude specific controllers and jobs from APM tracking.

### Configuration


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

Notes:
- Wildcards `*` are supported for controller and action (e.g., `Admin::*#*`).
- Matching is done against full names like `UsersController`, `Admin::ReportsController#index`, `MyJob`.

## SQL Query Tracking

ApmBro automatically tracks SQL queries executed during each request and job. Each request will include a `sql_queries` array containing:
- `sql` - The SQL query (always sanitized)
- `name` - Query name (e.g., "User Load", "User Update")
- `duration_ms` - Query execution time in milliseconds
- `cached` - Whether the query was cached
- `connection_id` - Database connection ID
- `trace` - Call stack showing where the query was executed

## View Rendering Tracking

ApmBro automatically tracks view rendering performance for each request. This includes:

- **Individual view events**: Templates, partials, and collections rendered
- **Performance metrics**: Rendering times for each view component
- **Cache analysis**: Cache hit rates for partials and collections
- **Slow view detection**: Identification of the slowest rendering views
- **Frequency analysis**: Most frequently rendered views

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
  
  # Sampling configuration
  config.sample_rate = 100                     # Percentage of requests to track (1-100, default: 100)
end
```

**Performance Impact:**
- **Lightweight mode**: ~0.1ms overhead per request
- **Allocation tracking**: ~2-5ms overhead per request (only enable when needed)

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


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rubydevro/apm_bro.

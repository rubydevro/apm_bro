# frozen_string_literal: true

require_relative "apm_bro/version"

module ApmBro
  autoload :Configuration, "apm_bro/configuration"
  autoload :Client, "apm_bro/client"
  autoload :CircuitBreaker, "apm_bro/circuit_breaker"
  autoload :Subscriber, "apm_bro/subscriber"
  autoload :SqlSubscriber, "apm_bro/sql_subscriber"
  autoload :SqlTrackingMiddleware, "apm_bro/sql_tracking_middleware"
  autoload :CacheSubscriber, "apm_bro/cache_subscriber"
  autoload :RedisSubscriber, "apm_bro/redis_subscriber"
  autoload :ViewRenderingSubscriber, "apm_bro/view_rendering_subscriber"
  autoload :MemoryTrackingSubscriber, "apm_bro/memory_tracking_subscriber"
  autoload :MemoryLeakDetector, "apm_bro/memory_leak_detector"
  autoload :LightweightMemoryTracker, "apm_bro/lightweight_memory_tracker"
  autoload :MemoryHelpers, "apm_bro/memory_helpers"
  autoload :JobSubscriber, "apm_bro/job_subscriber"
  autoload :JobSqlTrackingMiddleware, "apm_bro/job_sql_tracking_middleware"
  begin
    require "apm_bro/railtie"
  rescue LoadError
  end

  class Error < StandardError; end

  def self.configure
    yield configuration
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.reset_configuration!
    @configuration = Configuration.new
  end
end

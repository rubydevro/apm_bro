# frozen_string_literal: true

module ApmBro
  class JobSqlTrackingMiddleware
    def self.subscribe!
      # Start SQL tracking when a job begins - use the start event, not the complete event
      ActiveSupport::Notifications.subscribe("perform_start.active_job") do |name, started, finished, _unique_id, data|
        # Clear logs for this job
        ApmBro.logger.clear
        ApmBro::SqlSubscriber.start_request_tracking

        # Start lightweight memory tracking for this job
        if defined?(ApmBro::LightweightMemoryTracker)
          ApmBro::LightweightMemoryTracker.start_request_tracking
        end

        # Start detailed memory tracking when allocation tracking is enabled
        if ApmBro.configuration.allocation_tracking_enabled && defined?(ApmBro::MemoryTrackingSubscriber)
          ApmBro::MemoryTrackingSubscriber.start_request_tracking
        end
      end
    rescue StandardError
      # Never raise from instrumentation install
    end
  end
end

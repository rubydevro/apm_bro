# frozen_string_literal: true

module ApmBro
  class JobSqlTrackingMiddleware
    def self.subscribe!
      # Start SQL tracking when a job begins - use the start event, not the complete event
      ActiveSupport::Notifications.subscribe("perform_start.active_job") do |name, started, finished, _unique_id, data|
        # Clear logs for this job
        ApmBro.logger.clear
        ApmBro::SqlSubscriber.start_request_tracking
      end
    rescue StandardError
      # Never raise from instrumentation install
    end
  end
end

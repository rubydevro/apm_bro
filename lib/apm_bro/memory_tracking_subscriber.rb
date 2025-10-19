# frozen_string_literal: true

require "active_support/notifications"

module ApmBro
  class MemoryTrackingSubscriber
    # Object allocation events
    ALLOCATION_EVENT = "object_allocations.active_support".freeze
    
    THREAD_LOCAL_KEY = :apm_bro_memory_events
    LARGE_OBJECT_THRESHOLD = 1_000_000 # 1MB threshold for large objects
    
    # Performance optimization settings
    ALLOCATION_SAMPLING_RATE = 0.1 # Only track 10% of allocations
    MAX_ALLOCATIONS_PER_REQUEST = 1000 # Limit allocations tracked per request
    ENABLE_ALLOCATION_TRACKING = false # Disabled by default for performance

    def self.subscribe!(client: Client.new)
      # Only enable allocation tracking if explicitly enabled (expensive!)
      return unless ApmBro.configuration.allocation_tracking_enabled
      
      if defined?(ActiveSupport::Notifications) && ActiveSupport::Notifications.notifier.respond_to?(:subscribe)
        begin
          # Subscribe to object allocation events with sampling
          ActiveSupport::Notifications.subscribe(ALLOCATION_EVENT) do |name, started, finished, _unique_id, data|
            # Sample allocations to reduce overhead
            next unless rand < ALLOCATION_SAMPLING_RATE
            track_allocation(data, started, finished)
          end
        rescue StandardError
          # Allocation tracking might not be available in all Ruby versions
        end
      end
    rescue StandardError
      # Never raise from instrumentation install
    end

    def self.start_request_tracking
      # Only track if memory tracking is enabled
      return unless ApmBro.configuration.memory_tracking_enabled
      
      Thread.current[THREAD_LOCAL_KEY] = {
        allocations: [],
        memory_snapshots: [],
        large_objects: [],
        gc_before: gc_stats,
        memory_before: memory_usage_mb,
        start_time: Time.now.utc.to_i
      }
    end

    def self.stop_request_tracking
      events = Thread.current[THREAD_LOCAL_KEY]
      Thread.current[THREAD_LOCAL_KEY] = nil
      
      if events
        events[:gc_after] = gc_stats
        events[:memory_after] = memory_usage_mb
        events[:end_time] = Time.now.utc.to_i
        events[:duration_seconds] = events[:end_time] - events[:start_time]
      end
      
      events || {}
    end

    def self.track_allocation(data, started, finished)
      return unless Thread.current[THREAD_LOCAL_KEY]
      
      # Only track if we have meaningful allocation data
      return unless data.is_a?(Hash) && data[:count] && data[:size]
      
      # Limit allocations per request to prevent memory bloat
      allocations = Thread.current[THREAD_LOCAL_KEY][:allocations]
      return if allocations.length >= MAX_ALLOCATIONS_PER_REQUEST
      
      # Simplified allocation tracking (avoid expensive operations)
      allocation = {
        class_name: data[:class_name] || "Unknown",
        count: data[:count],
        size: data[:size]
        # Removed expensive fields: duration_ms, timestamp, memory_usage
      }
      
      # Track large object allocations (these are rare and important)
      if data[:size] > LARGE_OBJECT_THRESHOLD
        large_object = allocation.merge(
          large_object: true,
          size_mb: (data[:size] / 1_000_000.0).round(2)
        )
        Thread.current[THREAD_LOCAL_KEY][:large_objects] << large_object
      end
      
      Thread.current[THREAD_LOCAL_KEY][:allocations] << allocation
    end

    def self.take_memory_snapshot(label = nil)
      return unless Thread.current[THREAD_LOCAL_KEY]
      
      snapshot = {
        label: label || "snapshot_#{Time.now.to_i}",
        memory_usage: memory_usage_mb,
        gc_stats: gc_stats,
        timestamp: Time.now.utc.to_i,
        object_count: object_count,
        heap_pages: heap_pages
      }
      
      Thread.current[THREAD_LOCAL_KEY][:memory_snapshots] << snapshot
    end

    def self.analyze_memory_performance(memory_events)
      return {} if memory_events.empty?
      
      allocations = memory_events[:allocations] || []
      large_objects = memory_events[:large_objects] || []
      snapshots = memory_events[:memory_snapshots] || []
      
      # Calculate memory growth
      memory_growth = 0
      if memory_events[:memory_before] && memory_events[:memory_after]
        memory_growth = memory_events[:memory_after] - memory_events[:memory_before]
      end
      
      # Calculate allocation totals
      total_allocations = allocations.sum { |a| a[:count] }
      total_allocated_size = allocations.sum { |a| a[:size] }
      
      # Group allocations by class
      allocations_by_class = allocations.group_by { |a| a[:class_name] }
                                      .transform_values { |allocs| 
                                        { 
                                          count: allocs.sum { |a| a[:count] },
                                          size: allocs.sum { |a| a[:size] }
                                        }
                                      }
      
      # Find top allocating classes
      top_allocating_classes = allocations_by_class.sort_by { |_, data| -data[:size] }.first(10)
      
      # Analyze large objects
      large_object_analysis = analyze_large_objects(large_objects)
      
      # Analyze memory snapshots for trends
      memory_trends = analyze_memory_trends(snapshots)
      
      # Calculate GC efficiency
      gc_efficiency = calculate_gc_efficiency(memory_events[:gc_before], memory_events[:gc_after])
      
      {
        memory_growth_mb: memory_growth.round(2),
        total_allocations: total_allocations,
        total_allocated_size: total_allocated_size,
        total_allocated_size_mb: (total_allocated_size / 1_000_000.0).round(2),
        allocations_per_second: memory_events[:duration_seconds] > 0 ? 
          (total_allocations.to_f / memory_events[:duration_seconds]).round(2) : 0,
        top_allocating_classes: top_allocating_classes.map { |class_name, data|
          {
            class_name: class_name,
            count: data[:count],
            size: data[:size],
            size_mb: (data[:size] / 1_000_000.0).round(2)
          }
        },
        large_objects: large_object_analysis,
        memory_trends: memory_trends,
        gc_efficiency: gc_efficiency,
        memory_snapshots_count: snapshots.count
      }
    end

    def self.analyze_large_objects(large_objects)
      return {} if large_objects.empty?
      
      {
        count: large_objects.count,
        total_size_mb: large_objects.sum { |obj| obj[:size_mb] }.round(2),
        largest_object_mb: large_objects.max_by { |obj| obj[:size_mb] }[:size_mb],
        by_class: large_objects.group_by { |obj| obj[:class_name] }
                              .transform_values(&:count)
      }
    end

    def self.analyze_memory_trends(snapshots)
      return {} if snapshots.length < 2
      
      # Calculate memory growth rate between snapshots
      memory_values = snapshots.map { |s| s[:memory_usage] }
      memory_growth_rates = []
      
      (1...memory_values.length).each do |i|
        growth = memory_values[i] - memory_values[i-1]
        time_diff = snapshots[i][:timestamp] - snapshots[i-1][:timestamp]
        rate = time_diff > 0 ? growth / time_diff : 0
        memory_growth_rates << rate
      end
      
      {
        average_growth_rate_mb_per_second: memory_growth_rates.sum / memory_growth_rates.length,
        max_growth_rate_mb_per_second: memory_growth_rates.max,
        memory_volatility: memory_growth_rates.map(&:abs).sum / memory_growth_rates.length,
        peak_memory_mb: memory_values.max,
        min_memory_mb: memory_values.min
      }
    end

    def self.calculate_gc_efficiency(gc_before, gc_after)
      return {} unless gc_before && gc_after
      
      {
        gc_count_increase: (gc_after[:count] || 0) - (gc_before[:count] || 0),
        heap_pages_increase: (gc_after[:heap_allocated_pages] || 0) - (gc_before[:heap_allocated_pages] || 0),
        objects_allocated: (gc_after[:total_allocated_objects] || 0) - (gc_before[:total_allocated_objects] || 0),
        gc_frequency: gc_after[:count] && gc_before[:count] ? 
          (gc_after[:count] - gc_before[:count]).to_f / [gc_after[:count], 1].max : 0
      }
    end

    def self.memory_usage_mb
      # Use cached memory calculation to avoid expensive system calls
      @memory_cache ||= {}
      cache_key = Process.pid
      
      # Cache memory usage for 1 second to avoid repeated system calls
      if @memory_cache[cache_key] && (Time.now - @memory_cache[cache_key][:timestamp]) < 1
        return @memory_cache[cache_key][:memory]
      end
      
      memory = if defined?(GC) && GC.respond_to?(:stat)
        # Use GC stats as a proxy for memory usage (much faster than ps)
        gc_stats = GC.stat
        # Estimate memory usage from heap pages (rough approximation)
        heap_pages = gc_stats[:heap_allocated_pages] || 0
        (heap_pages * 4 * 1024) / (1024 * 1024) # 4KB per page, convert to MB
      else
        0
      end
      
      @memory_cache[cache_key] = { memory: memory, timestamp: Time.now }
      memory
    rescue StandardError
      0
    end

    def self.gc_stats
      if defined?(GC) && GC.respond_to?(:stat)
        stats = GC.stat
        {
          count: stats[:count] || 0,
          heap_allocated_pages: stats[:heap_allocated_pages] || 0,
          heap_sorted_pages: stats[:heap_sorted_pages] || 0,
          total_allocated_objects: stats[:total_allocated_objects] || 0,
          heap_live_slots: stats[:heap_live_slots] || 0,
          heap_eden_pages: stats[:heap_eden_pages] || 0,
          heap_tomb_pages: stats[:heap_tomb_pages] || 0
        }
      else
        {}
      end
    rescue StandardError
      {}
    end

    def self.object_count
      if defined?(GC) && GC.respond_to?(:stat)
        GC.stat[:heap_live_slots] || 0
      else
        0
      end
    rescue StandardError
      0
    end

    def self.heap_pages
      if defined?(GC) && GC.respond_to?(:stat)
        GC.stat[:heap_allocated_pages] || 0
      else
        0
      end
    rescue StandardError
      0
    end

    # Helper method to take memory snapshots at specific points
    def self.snapshot_at(label)
      take_memory_snapshot(label)
    end
  end
end

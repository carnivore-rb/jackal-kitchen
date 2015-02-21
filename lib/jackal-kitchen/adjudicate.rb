require "jackal-kitchen"

module Jackal
  # Formulate kitchen output into short message
  module Kitchen
    class Adjudicate < Jackal::Callback


      # Setup the callback
      def setup(*_)

      end

      # Validity of message
      #
      # @param msg [Carnivore::Message]
      # @return [TrueClass, FalseClass]
      def valid?(msg)
        super do |payload|
          payload.get(:data, :kitchen, :test_output)
        end
      end

      # Populate payload with judgement regarding test outcome
      #
      # @param payload [Smash]
      def execute(msg)
        failure_wrap(msg) do |payload|
          [:serverspec, :teapot].each do |format|
            payload.get(:data, :kitchen, :test_output, format).each do |instance, data|
              payload.set(:data, :kitchen, :judge, instance.to_sym, metadata(data, format))
            end
          end

          payload.set(:data, :kitchen, :judge, :chefspec, metadata(
                        payload.get(:data, :kitchen, :test_output,:chefspec), :spec))

          reasons = populate_reasons_for_failure(payload)

          verdict = reasons.values.flatten.empty?
          payload.set(:data, :kitchen, :judge, :decision, verdict)
          job_completed(:kitchen, payload, msg)
        end
      end

      # Process teapot metadata to determine if any thresholds were exceeded
      #
      # @param data [Smash] the teapot data from payload
      # @return [Smash] the resulting teapot metadata
      def teapot_metadata(data) # data,kitchen,test_output,teapot ->  #return hash
        # TODO :transient_failures => [],

        duration = data["timing"].map { |d|d["time"] }.inject(:+)

        exceeded = duration > config.fetch(
                     :kitchen, :thresholds, :teapot, :total_runtime, 600
                   )

        total_runtime = { :duration => duration,
                          :threshold_exceeded => exceeded }

        sorted_resources = data["timing"].sort_by{ |x|x["time"] }
        slowest_resource = sorted_resources.last

        resources_over_threshold = sorted_resources.reject { |r|
          r["time"] < config.fetch(
            :kitchen, :thresholds, :teapot, :resource_runtime, 120
          )
        }

        Smash.new(
          :slowest_resource => slowest_resource,
          :resources_over_threshold => resources_over_threshold,
          :total_runtime => total_runtime
        )
      end

      # Process spec metadata to determine if any thresholds were exceeded
      #
      # @param data [Smash] the rspec data from payload
      # @return [Smash] the resulting rspec metadata
      def spec_metadata(data)
        duration = data["summary"]["duration"]
        sorted_tests = data["examples"].sort_by{ |x|x["run_time"] }
        slowest_test = sorted_tests.last
        tests_over_threshold = []
        threshold = config.fetch(:kitchen, :thresholds, :spec, :test_runtime, 60)

        tests_over_threshold = data["examples"].reject { |e|
          if e.key?("run_time")
            e["run_time"] < threshold
          end
        }

        Smash.new(
          :slowest_test => slowest_test,
          :tests_over_threshold => tests_over_threshold,
          :total_runtime => duration
        )
      end

      private

      # For each test category, populate a results array that indicates
      #   any test failures
      #
      # @param payload [Smash] payload data with test example info
      # @return [Hash] eg: { reasons: [teapot: ['I was born to fail'], chefspec: [], ...]}
      def populate_reasons_for_failure(payload)
        reasons = {}

        [:chefspec, :serverspec, :teapot].each do |type|
          reasons[type] = []
          examples = payload[:data][:kitchen][:test_output][type][:examples] || []
          examples.select { |h| h[:status] == 'failed' }.each do |h|
            reasons[type] << h[:description]
          end

          cond = (type == :teapot &&
                  metadata(payload, type)[:total_runtime][:threshold_exceeded])
          reasons[type] << 'Threshold exceeded' if cond
        end

        payload.set(:data, :kitchen, :judge, :reasons, Smash.new(reasons))
        reasons
      end

      # Convenience method to fetch payload metadata based on type
      #
      # @param payload [Smash] payload data with test example info
      # @return [Smash] metadata associated with test type
      def metadata(data, type)
        meth = (type == :teapot) ? :teapot_metadata : :spec_metadata
        send(meth, data)
      end

    end
  end
end

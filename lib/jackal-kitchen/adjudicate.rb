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
          test_types(payload).each do |format|
            test_output(payload, format).each do |instance, data|
              payload.set(:data, :kitchen, :judge, instance.to_sym, metadata(data, format))
            end
          end

          reasons = populate_reasons_for_failure(payload)
          verdict = reasons.all? { |k, v| v.values.flatten.empty? }

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

        exceeded = duration > config.fetch(
                     :kitchen, :thresholds, data["test_format"] , :total_runtime, 60
                   )

        tests_over_threshold = data["examples"].reject { |e|
          if e.key?("run_time")
            e["run_time"] < config.fetch(
              :kitchen, :thresholds, data["test_format"], :test_runtime, 10)
          end
        }

        total_runtime => {
          :duration => duration,
          :threshold_exceeded => exceeded
        }

        Smash.new(
          :slowest_test => slowest_test,
          :tests_over_threshold => tests_over_threshold,
          :total_runtime => total_runtime
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
        test_types(payload).each do |type|
          instances = test_output(payload, type).keys
          instances.map(&:to_sym).each do |instance|
            reasons[type] = { instance => [] }
            examples = test_output(payload, type, instance, :examples) || []
            examples.select { |h| h[:status] == 'failed' }.each do |h|
              reasons[type][instance] << h[:description]
            end
            reasons[type][instance] << msg if threshold_exceeded?(payload, type, instance)
          end
        end

        payload.set(:data, :kitchen, :judge, :reasons, Smash.new(reasons))
        reasons
      end

      # Convenience method to fetch payload metadata based on type
      #
      # @param payload [Smash] payload data with test example info
      # @return [Smash] metadata associated with test type
      def metadata(data, type)
        meth = (type.to_sym == :teapot) ? :teapot_metadata : :spec_metadata
        send(meth, data)
      end

      # Convenience method to fetch test output
      #
      # @param payload [Smash] entire payload
      # @return [Smash] test output from payload
      def test_output(payload, *args)
        payload.get(:data, :kitchen, :test_output, *args)
      end

      # Convenience method to grab test types from payloads
      #
      # @param payload [Smash] entire payload
      # @return [Array] types of tests in payload (chefspec, serverspec, etc)
      def test_types(payload)
        test_output(payload).keys
      end

      # Check metadata to see if any thresholds have been exceeded
      #
      # @param payload [Smash] entire payload
      # @param type [String] test type eg: 'chefspec'
      # @param instance [String] test instance eg: 'default_ubuntu_1204'
      # @return [TrueClass, FalseClass]
      def threshold_exceeded?(payload, type, instance)
        return false unless type == :teapot
        mdata = teapot_metadata(test_output(payload, :teapot)[instance])
        mdata[:total_runtime][:threshold_exceeded]
      end

    end
  end
end

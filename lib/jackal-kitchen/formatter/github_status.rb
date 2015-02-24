require 'jackal'

module Jackal
  module Kitchen
    module Formatter

      class GithubStatus < Jackal::Formatter

        # Source service
        SOURCE = :kitchen
        # Destination service
        DESTINATION = :github_kit

        # Format payload to provide message to slack
        #
        # @param payload [Smash]
        def format(payload)
          success = payload.get(:data, :kitchen, :judge, :decision)
          payload.set(:data, :github_kit, :status,
                      Smash.new(
                        :repository => payload.get(:data, :code_fetcher, :name),
                        :reference => payload.get(:data, :code_fetcher, :commit_sha),
                        :state => payload.get(:data, :kitchen, :judge, :decision) ? 'success' : 'failure'),
                     )
        end
      end
    end
  end
end

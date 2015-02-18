require 'jackal'

module Jackal
  module Kitchen
    module Formatter

      class SlackMessage < Jackal::Formatter

        # Source service
        SOURCE = :kitchen_judge
        # Destination service
        DESTINATION = :slack

        # Format payload to provide message to slack
        #
        # @param payload [Smash]
        def format(payload)
          ref = payload.get(:data, :github, :head_commit, :id)
          repo = payload.get(:data, :github, :repository, :full_name)
          success = payload.get(:data, :kitchen, :judge, :decision)
          payload.set(:data, :slack, :messages,
            [
              Smash.new(
                :message => payload.get(:data, :kitchen),
                :color => success ? config.fetch(:colors, :success, 'good') : config.fetch(:colors, :failure, 'danger'),
                :judgement => {:success => success}
              )
            ]
          )
        end
      end
    end
  end
end

require 'jackal'

module Jackal
  module Kitchen
    module Formatter

      class SlackMessage < Jackal::Formatter

        # Source service
        SOURCE = :kitchen
        # Destination service
        DESTINATION = :slack

        # Format payload to provide message to slack
        #
        # @param payload [Smash]
        def format(payload)
          unless payload.get(:data, :kitchen, :judge, :decision).nil?
            ref = payload.get(:data, :github, :head_commit, :id)
            repo = payload.get(:data, :github, :repository, :full_name)
            success = payload.get(:data, :kitchen, :judge, :decision)
            reasons = payload.get(:data, :kitchen, :judge, :reasons)
            if success
              message = "Carlos passed commit #{ref} for #{repo}. \o/"
            else
              message = "Carlos failed commit #{ref} for #{repo}, because #{reasons}"
            end
            payload.set(:data, :slack, :messages,
                        [
                          Smash.new(
                          :message => message,
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
end

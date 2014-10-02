require 'jackal-kitchen'

class Jackal::Kitchen::Hook < Jackal::Utils::HttpApi; end

Jackal::Kitchen::Hook.define do
  post '/kitchen' do |msg|
    begin
      Carnivore::Supervisor.supervisor[:jackal_kitchen_input].transmit(
        new_payload('kitchen', :github => msg[:message][:body])
      )
    rescue => e
      error "Error encountered #{e}"
    ensure
      msg.confirm!
    end
  end
end

require 'fileutils'
require 'jackal'
require 'jackal-assets'
require 'jackal-kitchen/adjudicate'
require 'pry'

describe Jackal::Kitchen::Adjudicate do

  before do
    @runner = run_setup(:adjudicate)
  end

  after do
    @runner.terminate if @runner && @runner.alive?
  end

  let(:kitchen) do
    Carnivore::Supervisor.supervisor[:jackal_kitchen_input]
  end

  describe 'execute' do

    it 'should contain a judgement decision' do
      kitchen.transmit(
        payload_for(:adjudicate, :raw => true)
      )
      source_wait{ !MessageStore.messages.empty? }
      result = MessageStore.messages.pop
      Carnivore::Utils.retrieve(result, :data, :kitchen, :judge, :decision).wont_be_nil
    end

  end

end

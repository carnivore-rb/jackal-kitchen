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

    it 'should contain a judge key' do
      kitchen.transmit(
        payload_for(:adjudicate_success, :raw => true)
      )
      source_wait{ !MessageStore.messages.empty? }
      result = MessageStore.messages.pop
      Carnivore::Utils.retrieve(result, :data, :kitchen, :judge).wont_be_nil
    end

    it 'should have a "true" decision for passing tests' do
      kitchen.transmit(
        payload_for(:adjudicate_success, :raw => true)
      )
      source_wait{ !MessageStore.messages.empty? }
      result = MessageStore.messages.pop
      Carnivore::Utils.retrieve(result, :data, :kitchen, :judge, :decision) == true
    end

    it 'should have a "false" decision for failing tests' do
      kitchen.transmit(
        payload_for(:adjudicate_failure, :raw => true)
      )
      source_wait{ !MessageStore.messages.empty? }
      result = MessageStore.messages.pop
      Carnivore::Utils.retrieve(result, :data, :kitchen, :judge, :decision) == false
    end

  end

end

require 'fileutils'
require 'jackal'
require 'jackal-assets'
require 'jackal-kitchen/adjudicate'
require 'pry'

describe Jackal::Kitchen::Tester do

  before do
    @runner = run_setup(:tester)
  end

  after do
    @runner.terminate if @runner && @runner.alive?
  end

  let(:kitchen) do
    Carnivore::Supervisor.supervisor[:jackal_kitchen_input]
  end

  describe 'execute' do

    it 'should contain create a chefspec test_output key' do
      kitchen.transmit(
        payload_for(:tester, :raw => true)
      )
      source_wait 200
      result = MessageStore.messages.pop
      Carnivore::Utils.retrieve(result, :data, :kitchen, :test_output, :chefspec).wont_be_nil
    end

    it 'should contain create a serverspec test_output key' do
      kitchen.transmit(
        payload_for(:tester, :raw => true)
      )
      source_wait 200
      result = MessageStore.messages.pop
      Carnivore::Utils.retrieve(result, :data, :kitchen, :test_output, :serverspec).wont_be_nil
    end

  end

end
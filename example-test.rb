require 'fileutils'
require 'jackal'
require 'jackal-assets'
require 'jackal-kitchen/adjudicate'
require 'pry'

describe Jackal::Kitchen::Adjudicate do

  before do
    @runner = run_setup(:test)
    FileUtils.mkdir_p('/tmp/.jackal-kitchen-test')
  end

  after do
    FileUtils.rm_rf('/tmp/.jackal-kitchen-test')
    @runner.terminate if @runner && @runner.alive?
  end

  let(:kitchen) do
    Carnivore::Supervisor.supervisor[:jackal_kitchen_input]
  end

  describe 'format' do

    it 'should contain the kitchen key' do
      kitchen.transmit(
        Jackal::Utils.new_payload(
          :test, :kitchen => {:action => :toucher}
        )
      )
      source_wait(1) do
  #      binding.pry
      end
      File.exists?('/tmp/').must_equal true
    end

    it 'should contain the kiitchen key laoded from payload' do
      kitchen.transmit(
        payload_for(:initial)
      )
      binding.pry
      source_wait{ !MessageStore.messages.empty? }
      result = MessageStore.messages.pop
      Carnivore::Utils.retrieve(result, :data, :kitchen).wont_be_nil
    end


  end

end

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
      result.get(:data, :kitchen, :judge).wont_equal nil
    end

    it 'should have a "true" decision for passing tests' do
      kitchen.transmit(
        payload_for(:adjudicate_success, :raw => true)
      )
      source_wait{ !MessageStore.messages.empty? }
      result = MessageStore.messages.pop
      result.get(:data, :kitchen, :judge, :decision).must_equal true
    end

    it 'should have a "false" decision for failing tests' do
      kitchen.transmit(
        payload_for(:adjudicate_failure, :raw => true)
      )
      source_wait{ !MessageStore.messages.empty? }
      result = MessageStore.messages.pop
      result.get(:data, :kitchen, :judge, :decision).must_equal false
    end

    it 'failure reasons should reflect failing tests' do
      kitchen.transmit(
        payload_for(:adjudicate_failure, :raw => true)
      )
      source_wait{ !MessageStore.messages.empty? }

      result   = MessageStore.messages.pop
      reasons  = result.get(:data, :kitchen, :judge, :reasons)
      expected = {
        "chefspec"   => { "chefspec" => ["includes a broken recipe"] },
        "serverspec" => { "default-ubuntu-1204" => ["is listening on port 79"]},
        "teapot"     => { "default-ubuntu-1204" => [] }
      }
      reasons.must_equal expected
    end

  end

end

require 'fileutils'
require 'jackal'
require 'jackal-assets'
require 'jackal-kitchen/adjudicate'
require 'pry'

describe Jackal::Kitchen::Tester do

  before do
    @runner = run_setup(:tester)
    fname = 'hw-labs-teapot-test-cookbook-8f4ec29b8d1704cd524218665f7ae9daee5275b0.zip'
    fpath = File.join('.', 'test', 'specs', 'files', 'bucket_name', fname)
    bucket_name     = Carnivore::Config[:jackal][:assets][:bucket]
    obj_store_root  = Carnivore::Config[:jackal][:assets][:connection][:credentials][:object_store_root]
    FileUtils.mkdir(File.join(obj_store_root, bucket_name))
    FileUtils.cp(fpath, File.join(obj_store_root, bucket_name, fname))
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

      source_wait 30
      result = MessageStore.messages.pop
      Carnivore::Utils.retrieve(result, :data, :kitchen, :test_output, :chefspec).wont_be_nil
    end

    it 'should contain create a serverspec test_output key' do
      kitchen.transmit(
        payload_for(:tester, :raw => true)
      )
      source_wait 600
      result = MessageStore.messages.pop
      Carnivore::Utils.retrieve(result, :data, :kitchen, :test_output, :serverspec).wont_be_nil
    end

    it 'creates a netrc file with relevant github credentials' do
      kitchen.transmit(
        payload_for(:tester, :raw => true)
      )

      source_wait 5
      f = File.read(File.expand_path('~/.netrc')) rescue nil
      assert_match(/^machine +github\.com$/, f)
      assert_match(/ *login #{ENV['JACKAL_GITHUB_ACCESS_TOKEN']}/, f)
      assert_match(/ *password x-oauth-basic/, f)
    end

  end

end

require 'jackal-kitchen'
require 'fileutils'
require 'kitchen'
require 'tmpdir'
require 'rye'

module Jackal
  module Kitchen
    # Kitchen runner
    class Tester < Jackal::Callback

      # Setup the callback
      def setup(*_)
        require 'childprocess'
        require 'tmpdir'
        require 'shellwords'
      end

      # Validity of message
      #
      # @param msg [Carnivore::Message]
      # @return [TrueClass, FalseClass]
      def valid?(msg)
        super do |payload|
          payload.get(:data, :code_fetcher, :asset) &&
            payload.get(:data, :kitchen, :test_output).nil?
        end
      end

      # Execute action (test kitchen run)
      #
      # @param msg [Carnivore::Message]
      def execute(msg)
        failure_wrap(msg) do |payload|
          mkdir = ->(name) { FileUtils.mkdir_p(name).first }
          working_dir = mkdir.(app_config.fetch(:kitchen, :working_dir, Dir.mktmpdir))
          bundle_dir  = mkdir.(app_config.fetch(:kitchen, :bundle_vendor_dir, File.join(working_dir, '.jackal-kitchen-vendor')))
          debug "Working path: #{working_dir}"

          begin
            maybe_clean_bundle do
              asset_key = payload.get(:data, :code_fetcher, :asset)
              object = asset_store.get(asset_key)
              asset_filename = File.join(working_dir, asset_key)
              asset = File.open(asset_filename, 'w')
              asset.write object.read
              asset.close
              asset_store.unpack(asset, working_dir)
              insert_kitchen_miasma(working_dir)
              update_spec_helpers(working_dir)

              bundle_install_cmd = config.fetch(:vendor_bundle, true) ? "bundle install --path #{bundle_dir}" : 'bundle install'

              run_commands(
                [
                  bundle_install_cmd,
                  'bundle exec rspec'
                ],
                {},
                working_dir,
                payload
              )

              chefspec_data = File.open(File.join(working_dir, 'output', 'chefspec.json')).read.to_s
              format_test_output(payload, Smash.new(
                :format => :chefspec, :data => JSON.parse(chefspec_data)
              ))

              insert_kitchen_local(working_dir)
              instances = kitchen_instances(working_dir)
              payload.set(:data, :kitchen, :instances, instances)

              instances.each do |instance|

                kitchen_exit_code = run_commands(["bundle exec kitchen verify #{instance}"], {}, working_dir, payload)[2]

                unless kitchen_exit_code == 0
                  warn("kitchen exited with unexpected return code: #{kitchen_exit_code}")
                end

                state = read_instance_state(working_dir, instance)

                debug("Instance state for #{instance}: #{state.inspect}")

                remote_ssh = Rye::Box.new(
                  state[:hostname],
                  :port => state.fetch(:port, 22) ,
                  :user => state[:username],
                  :keys => state.fetch(:ssh_key, nil),
                  :password => 'invalid',
                  :password_prompt => false
                )

                %w(teapot serverspec).each do |format|
                  begin
                    output = StringIO.new
                    output_dir = '/tmp'
                    remote_ssh.file_download(File.join(output_dir, "#{format}.json"), output)

                    format_test_output(payload, Smash.new(
                      :format => format.to_sym, :data => JSON.parse(output.string), :instance => instance
                    ))
                  rescue => e
                    warn("could not load #{format} result (#{e.class}): #{e}")
                  end
                end

              end
            end
          rescue => e
            error "Command failed! #{e.class}: #{e}"
          ensure
            run_commands(['bundle exec kitchen destroy'], {}, working_dir, payload)
            FileUtils.rm_rf(working_dir)
          end

          teapot = payload.fetch(:data, :kitchen, :test_output, :teapot, {})

          if teapot.empty?
            error "No teapot test output data found"
            raise
          end

          failures = teapot.any? do |instance, h|
            h.get(:run_status, :http_failure, :permanent) == false
          end
          retry_count = payload.fetch(:data, :kitchen, :retry_count, 0)
          retry_count += 1

          payload.set(:data, :kitchen, :retry_count, retry_count) if failures


          if failures && retry_count <= app_config.fetch(:kitchen, :config, :retries, 0)
            payload[:data][:kitchen].delete(:test_output)
          end

          completed(payload, msg)
        end
      end

      # Write .kitchen.local.yml overrides into specified path
      #
      # @param path [String]
      # @param instance [Miasma::Compute::Server]
      def insert_kitchen_local(path)
        File.open(File.join(path, '.kitchen.local.yml'), 'w') do |file|
          file.puts '---'
          file.puts 'driver:'
          file.puts '  name: miasma'
          file.puts "  ssh_key_name: #{config.get(:ssh, :key_name)}"
          file.puts "  ssh_key_path: #{config.get(:ssh, :key_path)}" if config.get(:ssh, :key_path)
        end
      end

      # Read kitchen instance state from disk and return as hash
      #
      # @param path [String] working directory (not including .kitchen directory)
      # @param instance [String] name of instance
      def read_instance_state(path, instance)
        instance_state = ::Kitchen::StateFile.new(path, instance)
        instance_state.read
      end

      # Load kitchen config and return an array of instances
      #
      # @param path [String] directory containing .kitchen.yml
      # @returns [Array] array of strings representing test-kitchen instances
      def kitchen_instances(path)
        yaml_path = File.join(path, '.kitchen.yml')
        kitchen_config = ::Kitchen::Config.new(
          :loader => ::Kitchen::Loader::YAML.new(:project_config => yaml_path)
        )
        return kitchen_config.instances.map(&:name)
      end

      # Update gemfile to include kitchen-miasma driver
      #
      # @param path [String] working directory
      def insert_kitchen_miasma(path)
        gemfile = File.join(path, 'Gemfile')
        if(File.exists?(gemfile))
          content = File.readlines(gemfile)
        else
          content = ['source "https://rubygems.org"']
        end
        content << 'gem "kitchen-miasma", :git => "https://github.com/cwjohnston/kitchen-miasma.git"'
        File.open(gemfile, 'w') do |file|
          file.puts content.join("\n")
        end
      end

      def update_spec_helpers(path)
        Dir.glob("#{path}/**/spec_helper.rb").each do |file|
          File.open(file, 'a') do |f|
            # whitespace here is important if spec_helper lacks trailing newline
            f.write <<-STR

RSpec.configure do |config|
  config.log_level = :fatal
  output_dir = 'output'
  Dir.new(output_dir)
  if defined?(ChefSpec)
    config.output_stream = File.open(File.join(output_dir,'chefspec.json'), 'w')
  elsif defined?(ServerSpec)
    config.output_stream = File.open(File.join(output_dir,'serverspec.json'), 'w')
  end
  config.formatter = 'json'
end
STR
          end
        end
      end

      # Run collection of commands
      #
      # @param commands [Array<String>] commands to execute
      # @param env [Hash] environment variables for process
      # @param payload [Smash]
      # @return [Array<Smash>] command results ({:start_time, :stop_time, :exit_code, :logs, :timed_out})
      def run_commands(commands, env, cwd, payload)
        results = []
        commands.each do |command|
          debug "running command: #{command}"
          process_manager.process(payload[:id], command) do |process|
            result = Smash.new
            stdout = process_manager.create_io_tmp(Celluloid.uuid, 'stdout')
            stderr = process_manager.create_io_tmp(Celluloid.uuid, 'stderr')
            process.io.stdout = stdout
            process.io.stderr = stderr
            process.environment.replace(env.dup)
            process.leader = true
            process.cwd = cwd
            result[:start_time] = Time.now.to_i
            process.start
            begin
              process.poll_for_exit(config.fetch(:max_execution_time, 600))
            rescue ChildProcess::TimeoutError
              process.stop
              result[:timed_out] = true
            end
            result[:stop_time] = Time.now.to_i
            result[:exit_code] = process.exit_code
            command_key = command.gsub!(/[^0-9A-Za-z.\-]/, '_')
            [stdout, stderr].each do |io|
              key = "kitchen/#{File.basename(io.path)}"
              type = io.path.split('-').last
              io.rewind
              asset_store.put(key, io)
              result.set(:logs, command_key, type, key)
              io.close
              File.delete(io.path)
            end
            results << result
            payload.set(:data, :kitchen, :result, command_key.to_sym, :exit_code, process.exit_code)
          end
        end
        results
      end

      # Format test output and add it to the payload
      #
      # @param payload, [Smash] the payload
      # @param output, [Smash] expects test output hash, format, optional instance name
      def format_test_output(payload, output = {})
        have_data = output.fetch(:data, false).is_a?(Enumerable)
        raise "Output did not contain enumerable data" unless have_data

        format = output.fetch(:format, nil)
        raise "Unknown test output format #{format}" unless %i( chefspec serverspec teapot ).include?(format)

        begin
          output[:instance] = format if format == :chefspec
          payload.set(:data, :kitchen, :test_output, format, output[:instance], output[:data])
          msg = "Please pass an instance name in config"
          raise msg unless output[:instance]
        rescue => e
          error "Processing #{format} output failed: #{e.inspect}"
          raise
        end
      end

      # Clean environment of bundler variables
      # if bundler is in use
      #
      # @yield block to execute
      # @return [Object] result of yield
      def maybe_clean_bundle
        if(defined?(Bundler))
          Bundler.with_clean_env do
            yield
          end
        else
          yield
        end
      end

    end
  end
end

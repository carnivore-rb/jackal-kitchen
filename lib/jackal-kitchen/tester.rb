require 'jackal-kitchen'
require 'fileutils'
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
        write_netrc
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
              insert_kitchen_ssh(working_dir)
              insert_kitchen_local(working_dir)

              run_commands(
                [
                  "bundle install --path #{bundle_dir}",
                  'bundle exec rspec',
                ],
                {},
                working_dir,
                payload
              )

              chefspec_data = File.open(File.join(working_dir, 'output', 'chefspec.json')).read.to_s
              format_test_output(payload, Smash.new(
                :format => :chefspec, :data => JSON.parse(chefspec_data)
              ))

              instances = kitchen_instances(working_dir)
              payload.set(:data, :kitchen, :instances, instances)
              instances.each do |instance|
                run_commands(["bundle exec kitchen verify #{instance}"], {}, working_dir, payload)
                remote = provision_instance
                connection = Rye::Box.new(
                  remote[:host],
                  :port => remote[:port],
                  :user => remote[:user],
                  :keys => remote[:key],
                  :password => 'invalid',
                  :password_prompt => false
                )

                %w(teapot serverspec).each do |format|

                  output = StringIO.new
                  connection.file_download("/tmp/output/#{format}.json", output)

                  format_test_output(payload, Smash.new(
                    :format => format.to_sym, :data => JSON.parse(output.string), :instance => instance
                  ))
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

      # Create a remote instance and return information for accessing it via SSH
      # TODO: Actually provision instances. For now, read ssh connection params from config.
      #
      # @param instance_config [Hash, Smash]
      # @returns [Smash]
      def provision_instance(instance_config = {})
        Smash.new(
          :host => config[:ssh][:host],
          :port => config[:ssh][:port],
          :user => config[:ssh][:username],
          :key => config[:ssh][:key],
        )
      end

      # Write .kitchen.local.yml overrides into specified path
      #
      # @param path [String]
      # @param instance [Hash]
      def insert_kitchen_local(path, instance = {})
        File.open(File.join(path, '.kitchen.local.yml'), 'w') do |file|
          file.puts '---'
          file.puts 'driver:'
          file.puts '  name: ssh'
          file.puts "  hostname: #{instance[:host]}"
          file.puts "  username: #{instance[:user]}"
          file.puts "  port: #{instance[:port]}"
          file.puts "  ssh_key: #{instance[:key]}"
        end
      end

      # Attempt to write .netrc in user directory for github auth
      #
      # @
      # @returns [NilClass]
      def write_netrc
        begin
          token    = app_config.get(:github, :access_token)
          gh_token = config.fetch(:github, :access_token, token)

          uri      = app_config.fetch(:github, :uri, 'github.com')
          git_host = config.fetch(:github, :uri, uri)

          File.open(File.expand_path('~/.netrc'), 'w') do |f|
            f.puts("machine #{git_host}\n  login #{gh_token}\n  password x-oauth-basic")
          end
        rescue
          warn "Could not write .netrc file"
        end
      end

      # Load kitchen config and return an array of instances
      #
      # @param path [String] working directory
      # @returns [Array] array of strings representing test-kitchen instances
      def kitchen_instances(path)
        require 'kitchen'
        yaml_path = File.join(path, '.kitchen.yml')
        kitchen_config = ::Kitchen::Config.new(
          :loader => ::Kitchen::Loader::YAML.new(:project_config => yaml_path)
        )
        return kitchen_config.instances.map(&:name)
      end

      # Update gemfile to include kitchen-ssh driver
      #
      # @param path [String] working directory
      def insert_kitchen_ssh(path)
        gemfile = File.join(path, 'Gemfile')
        if(File.exists?(gemfile))
          content = File.readlines(gemfile)
        else
          content = ['source "https://rubygems.org"']
        end
        content << 'gem "kitchen-ssh"'
        File.open(gemfile, 'w') do |file|
          file.puts content.join("\n")
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

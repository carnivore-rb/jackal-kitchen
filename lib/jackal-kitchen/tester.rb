require 'jackal-kitchen'
require 'fileutils'
require 'tmpdir'

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
            (payload.get(:data, :kitchen, :test_output).nil? || payload.get(:data, :kitchen, :retry))
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
              insert_kitchen_lxc(working_dir) unless ENV['JACKAL_DISABLE_LXC']
              insert_kitchen_local(working_dir) unless ENV['JACKAL_DISABLE_LXC']

              run_commands(
                [
                  "bundle install --path #{bundle_dir}",
                  'bundle exec rspec',
                ],
                {},
                working_dir,
                payload
              )

              output_path = File.join(working_dir, 'output')
              parse_test_output(payload, {:format => :chefspec, :cwd => output_path})
              instances = kitchen_instances(working_dir)
              payload.set(:data, :kitchen, :instances, instances)
              instances.each do |instance|
                run_commands(["bundle exec kitchen test #{instance}"], {}, working_dir, payload)
                %w(teapot serverspec).each do |format|
                  parse_test_output(payload, {
                    :format => format.to_sym, :cwd => output_path, :instance => instance
                  })
                end
              end

            end
          rescue => e
            error "Command failed! #{e.class}: #{e}"
          ensure
            run_commands(['bundle exec kitchen destroy'], {}, working_dir, payload)
            FileUtils.rm_rf(working_dir)
          end

          failures = payload.get(:data, :kitchen, :test_output, :teapot).any? do |instance, h|
            h[:run_status][:http_failure][:permanent] == false
          end
          retry_count = payload.fetch(:data, :kitchen, :retry_count, 0)
          retry_count += 1

          payload.set(:data, :kitchen, :retry_count, retry_count) if failures

          cond = failures && retry_count <= app_config.fetch(:kitchen, :config, :retries, 0)
          payload.set(:data, :kitchen, :retry, cond)

          completed(payload, msg)
        end
      end

      def insert_kitchen_local(path)
        File.open(File.join(path, '.kitchen.local.yml'), 'w') do |file|
          file.puts '---'
          file.puts 'driver:'
          file.puts '  name: lxc'
          file.puts '  use_sudo: false'
          if(config[:ssh_key])
            file.puts "  ssh_key: #{config[:ssh_key]}"
          end
        end
      end

      # Attempt to write .netrc in user directory for github auth
      #
      # @
      # @returns [NilClass]
      def write_netrc
        begin
          gh_token = config.fetch(:github, :access_token,
                                  app_config.get(:github, :access_token))
          git_host = config.fetch(config.fetch(:github, :uri,
                                  app_config.get(:github, :uri)), 'github.com')

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
        config = ::Kitchen::Config.new(
          :loader => ::Kitchen::Loader::YAML.new(:project_config => yaml_path)
        )
        return config.instances.map(&:name)
      end

      # Update gemfile to include kitchen-lxc driver
      #
      # @param path [String] working directory
      def insert_kitchen_lxc(path)
        gemfile = File.join(path, 'Gemfile')
        if(File.exists?(gemfile))
          content = File.readlines(gemfile)
        else
          content = ['source "https://rubygems.org"']
        end
        content << 'gem "kitchen-lxc"'
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

      # Parse test output json and add it to the payload
      #
      # @param format, [Symbol, String] test output format name (:chefspec, :serverspec, :teapot)
      # @param cwd, [String] test output directory path

      def parse_test_output(payload, config = {})
        fmt = config[:format].to_sym

        msg = "Please pass the cwd in config when parsing #{fmt} test output"
        raise msg unless config[:cwd]

        msg = "Unknown test output format #{fmt}"
        raise msg unless %i( chefspec serverspec teapot ).include?(fmt)

        begin
          file_path = File.join(config[:cwd], "#{fmt}.json")
          debug "processing #{fmt} from #{file_path}"

          output = JSON.parse(File.open(file_path).read)
          output[:test_format] = fmt

          config[:instance] = fmt if fmt == :chefspec
          payload.set(:data, :kitchen, :test_output, fmt, config[:instance], output)

          msg = "Please pass an instance name in config when parsing #{fmt} test output"
          raise msg unless config[:instance]
        rescue => e
          error "Processing #{fmt} output failed: #{e.inspect}"
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

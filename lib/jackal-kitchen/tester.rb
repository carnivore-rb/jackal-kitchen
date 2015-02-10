require 'jackal-kitchen'

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
          payload.get(:data, :github, :ref)
        end
      end

      # Execute action (test kitchen run)
      #
      # @param msg [Carnivore::Message]
      def execute(msg)
        failure_wrap(msg) do |payload|
          working_dir = working_path = Dir.mktmpdir
          debug "Working path: #{working_path}"

          begin
            maybe_clean_bundle do
              asset_key = payload.get(:data, :code_fetcher, :asset)
              object = asset_store.get(asset_key)
              asset_filename = File.join(working_path, asset_key)
              asset = File.open(asset_filename, 'w')
              asset.write object.read
              asset.close
              asset_store.unpack(asset, working_path)
              insert_kitchen_lxc(working_path) unless ENV['JACKAL_DISABLE_LXC']
              insert_kitchen_local(working_path) unless ENV['JACKAL_DISABLE_LXC']
              run_commands(
                [
                  'bundle install --path /tmp/.kitchen-jackal-vendor',
                  'bundle exec rspec',
                  'bundle exec kitchen test'
                ],
                {},
                working_path,
                payload
              )

              working_path = File.join(working_path, 'output')
              parse_test_output(working_path, payload)
            end
          rescue => e
            error "Command failed! #{e.class}: #{e}"
          ensure
            FileUtils.rm_rf(working_dir)
          end
          job_completed(:kitchen, payload, msg)
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
              [stdout, stderr].each do |io|
              key = "kitchen/#{File.basename(io.path)}"
              type = io.path.split('-').last
              io.rewind
              asset_store.put(key, io)
              command_key = command.gsub!(/[^0-9A-Za-z.\-]/, '_')
              result.set(:logs, command_key, type, key)
              io.close
              File.delete(io.path)
            end
            results << result
            unless(process.exit_code == 0)
              payload.set(:data, :kitchen, :result, :failed, true)
            end
          end
        end
        results
      end

      def spec_command(command, working_path, payload)
        cmd_input = Shellwords.shellsplit(command)
        process = ChildProcess.build(*cmd_input)
        stdout = File.open(File.join(working_path, 'stdout'), 'w+')
        stderr = File.open(File.join(working_path, 'stderr'), 'w+')
        process.io.stdout = stdout
        process.io.stderr = stderr
        process.cwd = working_path
        process.start
        status = process.wait
        if status == 0
          info "Spec command '#{command}' completed sucessfully"
          payload.set(:data, :kitchen, :result, command, :success)
          true
        else
          error "Command '#{command}' failed"
          payload.set(:data, :kitchen, :result, command, :fail)
        end
      end

      def kitchen_command(command, working_path, payload)
        cmd_input = Shellwords.shellsplit(command)
        process = ChildProcess.build(*cmd_input)
        stdout = File.open(File.join(working_path, 'stdout'), 'w+')
        stderr = File.open(File.join(working_path, 'stderr'), 'w+')
        process.io.stdout = stdout
        process.io.stderr = stderr
        process.cwd = working_path
        process.start
        status = process.wait
        if status == 0
          info "Command '#{command}' completed sucessfully"
          payload.set(:data, :kitchen, :result, command, :success)
          true
        else
          error "Command '#{command}' failed"
          stderr.rewind
          payload.set(:data, :kitchen, :result, command, :fail)
          payload.set(:data, :kitchen, :error, stderr.read)
          stdout.rewind
          stderr.rewind
          error "Command failure! (#{command}). STDOUT: #{stdout.read} STDERR: #{stderr.read}"
        end
      end

      def parse_test_output(cwd, payload)
        # TODO make formats configurable
        # e.g. formats = config.fetch(:kitchen, :config, :test_formats, %w(chefspec serverspec teapot))
        %w(chefspec serverspec teapot).each do |format|
          begin
            file_path = File.join(cwd, "#{format}.json")
            debug "processing #{format} from #{file_path}"
            file = File.open(file_path).read
            output = JSON.parse(file)
            payload.set(:data, :kitchen, :test_output, format.to_sym, output)
          rescue => e
            error "Processing #{format} output failed: #{e.inspect}"
            raise
          end
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

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
          user = payload.get(:data, :github, :repository, :owner, :name)
          ref = payload.get(:data, :github, :head_commit, :id)
          repo = payload.get(:data, :github, :repository, :url)
          working_dir = working_path = Dir.mktmpdir
          begin
            maybe_clean_bundle do
              setup_command("git clone #{repo} cookbook", working_path, payload)
              working_path = File.join(working_path, 'cookbook')
              setup_command("git checkout #{ref}", working_path, payload)
              setup_command("bundle install", working_path, payload)
              kitchen_command("bundle exec kitchen test", working_path, payload)
            end
          rescue => e
            raise
          ensure
            FileUtils.rm_rf(working_dir)
          end
          job_completed(:kitchen, payload, msg)
        end
      end

      # Run a command
      #
      # @param command [String] command to execute
      # @param working_path [String] local working path
      # @param payload [Smash] current payload
      # @return [TrueClass]
      def setup_command(command, working_path, payload)
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
          info "Setup command '#{command}' completed sucessfully"
          payload.set(:data, :kitchen, :result, command, :success)
          true
        else
          error "Command '#{command}' failed"
          payload.set(:data, :kitchen, :result, command, :fail)
          raise "Failed to execute setup command '#{command}'"
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
          payload.set(:data, :kitchen, :result, command, :fail)
          raise "Failed to execute command '#{command}'"
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

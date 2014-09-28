require 'jackal-kitchen'
require 'pry'
## check out jackal commander & target commit hook stuff
## check out jackal commander tests

module Jackal
  module Kitchen
    class Tester < Jackal::Callback
      
      def setup(*_)
        require 'childprocess'
        require 'tmpdir'
        require 'shellwords'
      end

      def valid?(msg)
        super do |payload|
          payload.get(:data, :github, :ref)
        end
      end

      def execute(msg)
        failure_wrap(msg) do |payload|
          user = payload.get(:data, :github, :repository, :owner, :name)
          ref = payload.get(:data, :github, :head_commit, :id)
          repo = payload.get(:data, :github, :repository, :url)
          working_dir = working_path = Dir.mktmpdir
          begin
            Bundler.with_clean_env do
              run_command("git clone #{repo} cookbook", working_path, payload)
              working_path = File.join(working_path, 'cookbook')
              run_command("git checkout #{ref}", working_path, payload)
              run_command("bundle install", working_path, payload)
              run_command("bundle exec kitchen test", working_path, payload)
            end
          rescue => e
            binding.pry
            raise
          ensure
            FileUtils.rm_rf(working_dir)
          end
          job_completed(:kitchen, payload, msg)
        end
      end

      def run_command(command, working_path, payload)
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
        else
          error "Command '#{command}' failed"
          payload.set(:data, :kitchen, :result, command, :fail)
          raise "Failed to execute command '#{command}'"
        end
      end

    end
  end
end

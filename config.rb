Configuration.new do
  jackal do
    require [
      "carnivore-actor",
      "carnivore-unixsocket",
      "carnivore-http",
      "jackal-assets",
      "jackal-kitchen",
      "pry"
    ]
    assets do
      bucket ENV['ASSET_STORE_BUCKET']
      connection do
        provider 'aws'
        credentials do
          aws_access_key_id ENV['ASSET_STORE_AWS_ACCESS_KEY_ID']
          aws_secret_access_key ENV['ASSET_STORE_AWS_SECRET_ACCESS_KEY']
          aws_region ENV['ASSET_STORE_REGION']
          aws_bucket_region ENV['ASSET_STORE_REGION']
        end
      end
    end
    kitchen do
      config do
        rescue_before_destroy true
        vendor_bundle false
        test_formats [ "chefspec", "serverspec" ]
        compute_provider do
          name 'aws'
          aws_access_key_id ENV['AWS_ACCESS_KEY_ID']
          aws_secret_access_key ENV['AWS_SECRET_ACCESS_KEY']
          aws_region ENV['AWS_REGION']
        end
        ssh do
          key_name ENV.fetch('KITCHEN_SSH_KEY_NAME', nil)
          key_path File.expand_path(ENV.fetch('KITCHEN_SSH_KEY_PATH', '~/.ssh/id_rsa'))
        end
      end
      sources do
        input do
          type :http_paths
          args do
            port ENV.fetch('KITCHEN_PORT', 9999)
            path '/v1/github/kitchen'
            method :post
          end
        end
        output do
          type :http
          args do
            method :post
            endpoint ENV['HTTP_OUTPUT_ENDPOINT']
            auto_process false
            enable_processing false
          end
        end
        error do
          type :http
          args do
            method :post
            endpoint ENV['HTTP_OUTPUT_ENDPOINT']
            auto_process false
            enable_processing false
          end
        end
      end
      callbacks [
        "Jackal::Kitchen::Tester",
        "Jackal::Kitchen::Adjudicate"
      ]
      formatters [
        "Jackal::Kitchen::Formatter::SlackMessage",
        "Jackal::Kitchen::Formatter::GithubStatus"
      ]
    end
  end
end

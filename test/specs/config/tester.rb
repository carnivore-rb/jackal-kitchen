Configuration.new do
  verbosity :error
  jackal do
    require [ 'carnivore-actor', 'jackal-assets', 'jackal-kitchen' ]

    assets do
      bucket 'bucket_name'
      connection do
        provider 'local'
        credentials do
          object_store_root Dir.mktmpdir
        end
      end
    end

    github do
      uri 'github.com'
      access_token ENV['JACKAL_GITHUB_ACCESS_TOKEN']
    end

    kitchen do
      working_dir '/tmp/jackal-kitchen'
      bundle_vendor_dir '/tmp/jackal-kitchen-bundle'

      sources do
        input do
          type 'actor'
        end
        output do
          type 'spec'
        end
      end
      callbacks [ 'Jackal::Kitchen::Tester' ]
    end
  end
end

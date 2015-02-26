Configuration.new do
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

      github do
        access_token 'foo'
      end

      kitchen do
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
end

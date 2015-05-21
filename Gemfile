source 'https://rubygems.org'

gem 'pry'
gem 'minitest'
gem 'carnivore-actor'

%w(
  jackal
  jackal-assets
).each do |component|
  gem component, :path => File.join(ENV['JACKAL_WORKING_DIR'], component)
end

gemspec

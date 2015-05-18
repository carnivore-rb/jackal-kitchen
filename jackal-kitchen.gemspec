$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__)) + '/lib/'
require 'jackal-kitchen/version'
Gem::Specification.new do |s|
  s.name = 'jackal-kitchen'
  s.version = Jackal::Kitchen::VERSION.version
  s.summary = 'Test Kitchen executor'
  s.author = 'Anthony Goddard'
  s.email = 'anthony@hw-ops.com'
  s.homepage = 'https://github.com/carnivore-rb/jackal-kitchen'
  s.description = 'Command helpers'
  s.require_path = 'lib'
  s.license = 'Apache 2.0'
  s.add_dependency 'jackal'
  s.add_dependency 'childprocess'
  s.add_dependency 'carnivore-http'
  s.add_dependency 'carnivore-actor'
  s.add_dependency 'test-kitchen', '~> 1.4.0'
  s.add_dependency 'kitchen-miasma', '~> 0.0.1'
  s.add_dependency 'rye', '~> 0.9.13'
  s.files = Dir['lib/**/*'] + %w(jackal-kitchen.gemspec README.md CHANGELOG.md CONTRIBUTING.md LICENSE)
end

require 'jackal'
require 'jackal-kitchen/version'
require 'jackal-kitchen/formatter/slack_message'

module Jackal
  module Kitchen
    autoload :Tester, 'jackal-kitchen/tester'
    autoload :Adjudicate, 'jackal-kitchen/adjudicate'
  end
end

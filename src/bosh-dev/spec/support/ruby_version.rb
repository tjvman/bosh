require 'yaml'

module Bosh::Dev
  class RubyVersion
    class << self
      def versions
        ['2.6.3']
      end

      def supported?(version)
        versions.include?(version)
      end

      def to_s
        versions.join(', ')
      end
    end
  end
end

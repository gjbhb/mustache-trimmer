require 'tilt'

module Tilt
  class MustacheJsTemplate < Template
    self.default_mime_type = 'application/javascript'

    def initialize_engine
      require_template_library 'mustache/js'
    end

    def prepare
    end

    def evaluate(scope, locals, &block)
      Mustache.to_javascript(data)
    end
  end
end

require "pygments"

module Hubdown
  class PygmentsRenderer < Redcarpet::Render::HTML
    def block_code(code, language)
      Pygments.highlight(code, lexer: language)
    end
  end
end

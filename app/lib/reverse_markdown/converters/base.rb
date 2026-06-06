# lib/base.rb

# Problem
# ReverseMarkdown escapes all underscores so that they won't be
# considered the start or end of an italic section.
# However, it *shouldn't* do that when it's part of an url
# This captures the output of the original escape_keychars
# method, looks for URLs in it, and unescapes the underscores
# and asterisks in them before passing it back to the user.

require "reverse_markdown"

# Ensure the gem's own base.rb is loaded before our override.
# Since our file is also named 'reverse_markdown/converters/base.rb' and is in
# app/lib (which Rails adds to the $LOAD_PATH), a standard require of that
# path might resolve to our local file first. To prevent infinite recursion
# or the gem's base.rb being skipped, we load the gem's file by its absolute path.
gem_spec = Gem.loaded_specs["reverse_markdown"]
if gem_spec
  require File.join(gem_spec.full_gem_path, "lib/reverse_markdown/converters/base.rb")
end

module ReverseMarkdown
  module Converters
    class Base
      # Only apply the alias and override if escape_keychars is defined and we haven't already aliased it
      if method_defined?(:escape_keychars) && !method_defined?(:orig_escape_keychars)
        alias_method :orig_escape_keychars, :escape_keychars

        def escape_keychars(string)
          escaped = orig_escape_keychars(string)
          # Match HTTP/HTTPS URLs and restore escaped underscores/asterisks within them
          escaped.gsub(%r{https?://[^\s<>]+}) do |url|
            url.gsub('\\_', "_").gsub('\\*', "*")
          end
        end
      end
    end
  end
end

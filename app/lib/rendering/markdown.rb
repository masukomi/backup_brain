module Rendering
  class Markdown
    include Singleton

    attr_accessor :renderer
    def initialize
      # html_renderer = Redcarpet::Render::HTML.new
      Hubdown::PygmentsRenderer.new({hard_wrap: false})
      @md_options = {
        autolink: true,
        no_intra_emphasis: true,
        fenced_code_blocks: true,
        tables: true,
        strikethrough: true,
        lax_spacing: true,
        space_after_headers: true,
        superscript: true
      }
    end

    def render(raw_markdown)
      spoiler_escaped = pre_escape_spoilers(raw_markdown)
      rendered = if !/``` *mermaid/.match(spoiler_escaped)
        Redcarpet::Markdown.new(
          Hubdown::PygmentsRenderer.new({hard_wrap: false}),
          @md_options
        ).render(spoiler_escaped)
      else
        fallback_render(spoiler_escaped)
      end
      handle_spoilers(rendered)
    rescue MentosError => e # ClassNotFound => e
      simplified_message = e.message.sub(/.*?no lexer for alias '/m, "no lexer for alias '")
      # this will happen if someone specifies a language in codefences that
      # Pygments doesn't have a lexer for
      Rails.logger.error(simplified_message)
      fallback_render(raw_markdown)
    rescue => e
      "<h2>unable to render markdown</h2><br /><pre><tt>#{e}</tt></pre>"
    end

    def fallback_render(raw_markdown)
      Redcarpet::Markdown.new(
        Redcarpet::Render::HTML.new,
        @md_options
      ).render(raw_markdown)
    end

    def pre_escape_spoilers(raw_markdown)
      # this fuckery because >! interacts badly with markdown blockquotes
      # >!
      # > blockquote
      # !<
      #
      # produces
      # <p<span class="blurred></p>
      # <blockquote>
      # blockquote
      # </blockquote>
      # </p</span>
      #
      # or something stupid like that.
      raw_markdown.gsub(">!", "&gt;!").gsub("!<", "!&lt;").gsub(/&gt;!\n>(\s+)/m, "&gt;!\n\n>\\1").gsub(/\n!&lt;(\n|$)/m, "\n\n!&lt;\n")
    end

    def handle_spoilers(html)
      html
        .gsub(/&gt;!(?<spoiler>.*?)!&lt;/m, "<spoiler>\\k<spoiler></spoiler>")
        .gsub(/<p><(\/?)spoiler><\/p>/, "<\\1spoiler>")
        .gsub("<p><spoiler>", "<spoiler><p>")
    end
  end
end

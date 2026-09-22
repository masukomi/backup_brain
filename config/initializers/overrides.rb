# Load the reverse_markdown URL underscore escaping monkeypatch
require Rails.root.join("app/lib/reverse_markdown/converters/text")

if Rails.env.development?
  # Annotates rendered html with the partial each chunk came from,
  # to make it easy to find the template responsible for something.
  #
  # Prepended (rather than redefining the method) so the original
  # implementation is still reachable via super for non-html formats.
  # Annotating json, md, or rss would corrupt the response - and
  # html-escape it, because these comments are html_safe and the
  # content being wrapped isn't.
  module PartialBoundaryComments
    private

    def build_rendered_template(content, template)
      return super unless template.format == :html

      start_comment = "\n<!-- START PARTIAL #{template.short_identifier} -->\n".html_safe
      end_comment = "\n<!-- END PARTIAL #{template.short_identifier} -->\n".html_safe
      super(start_comment + content + end_comment, template)
    end
  end

  ActionView::AbstractRenderer.prepend(PartialBoundaryComments)
end

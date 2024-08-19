if Rails.env.development?
  module ActionView
    class AbstractRenderer
      private

      def build_rendered_template(content, template)
        start_comment = "\n<!-- START PARTIAL #{template.short_identifier} -->\n".html_safe
        end_comment = "\n<!-- END PARTIAL #{template.short_identifier} -->\n".html_safe
        content = start_comment + content + end_comment
        RenderedTemplate.new content, template
      end
    end
  end
end

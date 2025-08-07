require "action_controller/metal/renderers"

Mime::Type.register "text/markdown", :md, %w[text/x-markdown], %w[mdn markdn markdown mdown]
# note: text/x-markdown is deprecated but who knows,
# maybe someone's old code will request that.
#
# reference this new mime-type with
# Mime::Type.lookup_by_extension(:md)

ActionController::Renderers.add :md do |obj, options|
  options[:filename] || "markdown"
  str = obj.respond_to?(:to_md) ? obj.to_md(options) : obj
  self.content_type  = Mime::Type.lookup_by_extension(:md)
  self.response_body = str
end

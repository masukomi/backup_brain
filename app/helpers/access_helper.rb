module AccessHelper
  def model_path_string(klass)
    klass.name.titlecase.pluralize.downcase.gsub(" ", "_")
  end

  def api_key_permissions_for(klass)
    path = model_path_string(klass)
    ["read:#{path}", "write:#{path}"]
  end
end

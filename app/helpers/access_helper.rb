module AccessHelper
  def model_path_string(klass)
    BackupBrain::ModelPaths.path_string(klass)
  end

  def api_key_permissions_for(klass)
    path = model_path_string(klass)
    ["read:#{path}", "write:#{path}"]
  end
end

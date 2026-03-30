Rails.application.config.after_initialize do
  BackupBrain::RequestHeaders.instance
end

Rails.application.config.after_initialize do
  BackupBrain::ToolDispatcher.instance
end

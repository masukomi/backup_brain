Rails.application.config.after_initialize do
  BackupBrain::ToolDispatcher.instance
  BackupBrain::UnarchivableDomainsChecker.instance
end

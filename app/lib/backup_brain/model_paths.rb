module BackupBrain
  # Single source of truth for the path-ish string used to identify
  # a model in ApiKey permission strings ("read:bookmarks").
  # AccessHelper builds the permissions the user checks off in the
  # key form; ApiKey#permits? has to produce the exact same strings.
  module ModelPaths
    module_function

    def path_string(klass)
      klass.name.titlecase.pluralize.downcase.gsub(" ", "_")
    end
  end
end

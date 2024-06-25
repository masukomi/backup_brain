require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
# require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module BackupBrain
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # let folks add backupbrain to their /etc/hosts file
    config.hosts << 'backupbrain'

    # Use delayed_job for ActiveJob
    config.active_job.queue_adapter = :delayed_job

    begin
      latest_tag = `git tag --sort=v:refname | tail -1`.strip
      latest_tag = "no parent tag" if latest_tag.blank?
      latest_commit = `git log -n1 --pretty='%h'`.strip
      config.x.git_version = "#{latest_tag} -> #{latest_commit}"
    rescue => e
      config.x.git_version = "UNKNOWN: #{e.message}"
    end
  end
end

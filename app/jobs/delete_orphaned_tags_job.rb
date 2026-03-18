class DeleteOrphanedTagsJob < ApplicationJob
  def self.schedule_unless_pending
    already_queued = Delayed::Backend::Mongoid::Job
      .exists?(failed_at: nil, handler: /job_class: DeleteOrphanedTagsJob\n/)
    perform_later unless already_queued
  end

  def perform
    Tag.delete_orphaned_tags!
    true
  rescue => e
    Rails.logger.warn("Problems killing orphaned tags - #{e.message}")
    false
  end
end

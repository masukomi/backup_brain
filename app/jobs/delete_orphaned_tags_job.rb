class DeleteOrphanedTagsJob < ApplicationJob
  def perform
    Tag.delete_orphaned_tags!
    true
  rescue => e
    Rails.logger.warn("Problems killing orphaned tags - #{e.message}")
    false
  end
end

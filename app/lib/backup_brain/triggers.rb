# lib/domains.rb

module BackupBrain
  module Triggers
    def apply_to(mongoid_doc)
      apply_mark_to_read(mongoid_doc)
      apply_mark_private(mongoid_doc)
      apply_mark_as_sensitive(mongoid_doc)
      apply_tags(mongoid_doc)
    end

    # Applies changes and attempts to save the document
    def apply_to!(mongoid_doc)
      apply_to(mongoid_doc)
      mongoid_doc.save!
    end

    protected

    def apply_mark_to_read(mongoid_doc)
      if self&.mark_to_read && mongoid_doc.has_attribute?(:to_read)
        mongoid_doc.to_read = true
      end
    end

    def apply_mark_private(mongoid_doc)
      if self&.mark_as_private && mongoid_doc.has_attribute?(:private)
        mongoid_doc.private = true
      end
    end

    def apply_mark_as_sensitive(mongoid_doc)
      if self&.mark_as_sensitive && mongoid_doc.has_attribute?(:sensitive)
        mongoid_doc.sensitive = true
      end
    end

    def apply_tags(mongoid_doc)
      if self&.tags&.present? && mongoid_doc.has_attribute?(:tags)
        mongoid_doc.tags = mongoid_doc.tags + (tags - mongoid_doc.tags)
      end
    end
  end
end

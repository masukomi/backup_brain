class Tag
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String

  validates :name, presence:   true
  validates :name, uniqueness: true
  validate  :single_tag_only

  before_save :downcase_name
  before_destroy { |tag| Bookmark.remove_tag!(tag.name) }

  # BEGIN CLASS METHODS
  class << self
    # splits a string of tags, downcases them,
    # replaces spaces with underscores, and returns an array
    def split_tags(tags)
      return [] if tags.blank?
      tags.strip.split(/,?\s+|,/)
        .compact_blank
        .uniq
        .map { |t| t.strip.downcase.gsub(/\s+/, "_") }
    end

    # @return Boolean - true or false  indicating if the array of
    #                    tag strings are all valid
    def valid_tags?(array_o_strings)
      valid_tags(array_o_strings).size == array_o_strings.size
    end

    # @return [Array[String]] - returns the subset of tag
    #                           strings that are valid
    def valid_tags(array_o_strings)
      array_o_strings.select { |t|
        t.present? && t.downcase == t && !/\s+/.match?(t)
      }
    end

    # recreates tags from source data
    def regenerate_all!
      all_source_tags = Bookmark.pluck(:tags).flatten.uniq
      # When we have new things with tags they'll be added
      # to all_source_tags

      all_tag_names = Tag.pluck(:name)
      missing_tags = all_source_tags - all_tag_names
      invalid_tag_names = missing_tags - valid_tags(missing_tags)
      if invalid_tag_names.size > 0
        raise BackupBrain::Errors::InvalidTag.new(
          I18n.t("tags.errors.invalid_tag_names", names: invalid_tag_names.join(", "))
        )
      end
      obsolete_tags = all_tag_names - all_source_tags
      # alas, "Transactions are not supported for the cluster: standalone topology"
      Tag.create_many_by_name(missing_tags)
      Tag.where(name: obsolete_tags).destroy_all
      true
    end

    # compares the provided tag names to the
    # existing tags and creates any new ones that are
    # missing - skips callbacks
    def create_many_by_name_if_needed(names)
      return if names.empty?
      extant_tags = Tag.where(:name.in => names).pluck(:name)
      missing = names - extant_tags
      Tag.create_many_by_name(missing)
    end

    # Inserts many new tag objects WITHOUT callbacks or uniqueness validation
    def create_many_by_name(names)
      raise "can't create many tags because some are invalid" unless valid_tags? names
      return true if names.empty?
      Tag.collection.insert_many(names.map { |n| {name: n} })
    end

    def delete_orphaned_tags!
      bookmark_tags = Bookmark.pluck(:tags).flatten.uniq
      # Insert tags of other models here
      extant_tags = Tag.where(:name.in => names).pluck(:name)

      orphaned_tags = extant_tags - bookmark_tags
      Tag.where(:name.in => orphaned_tags).destroy_all
    end
  end

  # END CLASS METHODS

  def rename!(new_name)
    existing_tag = Tag.where(name: new_name).first
    if !existing_tag
      old_name = name.dup
      save! # don't proceed if this doesn't work

    else
      destroy! # dun dun DUUUUNNNNN!
    end

    # Yes, this is less efficient than
    # just using has_and_belongs_to_many
    # See Bookmark#update_central_tags_list
    # for why it is this way.

    # NOTE: replace will handle deletion just fine
    Bookmark.replace_tag!(old_name, new_name)
    # INSERT OTHER TAGGABLE MODELS HERE
  end

  private

  # THOU SHALT NOT USE UPPER CASE IN THINE TAGS!!! 😉
  def downcase_name
    name&.downcase
  end

  def single_tag_only
    if Tag.split_tags(name).size != 1
      errors.add(:name, I18n.t("tags.errors.invalid_tag_name"))
    end
  end
end

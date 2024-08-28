module BackupBrain
  # Unlike most Taggable libraries this module is working under the assumption
  # of a DEnormalized system of tags.
  # The model should have an embedded array of strings called "tags"
  # AND there is a centralized collection (MongoDB lingo) of Tag
  # models.
  #
  # The Tag class contains methods for finding tagged things across models,
  # and for working with "tag" input and other generic taggy things.
  #
  # NOTE: unit tests for these modules can be found in bookmark_spec.rb
  module Taggable
    module ClassMethods
      # Finds a list of things that contain the tag passed in
      def tagged_with_all(tag_or_tags)
        if tag_or_tags.is_a? String
          where(:tags.in => [tag_or_tags])
        else
          where(:tags.all => tag_or_tags)
        end
      end

      alias_method :tagged_with, :tagged_with_all

      def tagged_with_any(tags)
        raise ArgumentError.new("tags must be an array of strings") \
          unless tags.is_a? Array
        where("tags.0" => {"$exists": true}).not(:tags.nin => tags)
        # the array contains something
        # AND NOT the array contains none of the tags supplied
      end

      def replace_tag!(old, new)
        tagged_with_all([old]).each do |b|
          b.replace_tag!(old, new)
        end
      end

      def remove_tag!(tag_name)
        tagged_with_all([tag_name]).each do |b|
          b.remove_tag!(tag_name)
        end
      end
    end

    module InstanceMethods
      def clean_tags!
        self.tags = valid_tags(tags).uniq
      end

      # Replaces a tag
      #
      # ⚠️ WARNING: this does NOT effect Tag models
      # Instead it is expected that it will be called
      # by Tag#rename! - Bookmark.replace_tag!
      def replace_tag!(old, new)
        unless Tag.valid_tags?([new])
          raise BackupBrain::Errors::InvalidTag.new(
            I18n.t("tags.errors.invalid_tag", name: new)
          )
        end
        self.tags ||= []
        self.tags = (tags - [old] + [new]).uniq
        save!
        self.tags
      end

      def remove_tag!(tag_name)
        new_tags = self.tags.present? ? (self.tags - [tag_name]) : []
        self.tags = new_tags
        save!
        self.tags
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
          t.present? || t.downcase == t
        }
      end

      ## HOOKS

      # Call me after_save
      # The Central tag list is used as an easy way to
      # know what ALL the tags are, and (eventually) to
      # retrieve all the items with a tag
      # across models
      def update_central_tags_list
        # NOTE: we _could_ do a has_and_belongs_to_many
        # relationship here, but we don't need it YET
        # and there are multiple advantages to having the raw
        # string array embedded in the document
        #  - faster loading of lists
        #  - easier to pass the tags to Meilisearch

        Tag.create_many_by_name_if_needed(tags)
        Tag.ensure_no_orphans!
      end
    end
  end
end

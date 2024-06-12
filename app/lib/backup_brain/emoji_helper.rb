# BackupBrain::EmojiHelper provides methods to translate
# slack style emoji text like ":ambulance:" into 🚑
#
module BackupBrain
  module EmojiHelper
    # Finds and replaces any slack style emoji in a given text
    #
    # @param [String] the string to replace slack emoji in
    def emojify(content)
      return content if content.blank?
      content.gsub(/:([\w-]+):/) do |match|
        # rubocop:disable Rails/DynamicFindBy
        if (emoji = Emoji.find_by_alias($1))
          emoji.raw
        else
          match
        end
        # rubocop:enable Rails/DynamicFindBy
      end
    end

    # Given a list of attributes (fields) in your model it
    # this will replace the values of each with an emojified version
    # of their initial value.
    #
    # @param [Array] fields - an array of field names to emojify. Each should be a symbol
    def emojify_fields(fields)
      fields.each do |field|
        next if field.blank?
        send("#{field}=".to_sym, emojify(send(field)))
      end
    end

    # Leverages the optional EMOJIFIABLE_FIELDS constant
    # to find the fields in your model that should all
    # be emojified by default, and then proceeds to emojify them.
    def emojify_default_fields
      if self.class.constants.include?(:EMOJIFIABLE_FIELDS)
        emojify_fields(self.class::EMOJIFIABLE_FIELDS)
      end
    end
  end
end

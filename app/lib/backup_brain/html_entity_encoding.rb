# lib/html_entity_encoding.rb

module BackupBrain
  module HtmlEntityEncoding
    # Code here
    #   def decode_entities(text)
    def coder
      @@html_entities ||= HTMLEntities.new
    end
    alias_method :decoder, :coder
    alias_method :encoder, :coder

    delegate :decode, to: :decoder

    delegate :encode, to: :encoder

    def contains_html_entities?(text)
      # https://regexper.com/#%26%28%3F%3A%5Ba-z%5D%7B2%2C%7D%7C%23%5Cd%7B2%2C4%7D%29%3B
      # tests for
      # - an ampersand
      # followed by either
      # - 2 or more letters
      # - an octothorpe (#) followed by 2-4 digits
      # and then
      # - a semicolon;
      /&(?:[a-z]{2,}|#\d{2,4});/.match? text
    end

    # if text is encoded already then we don't want to
    # double encode it: e.g. don't make &amp; into &amp;amp;
    #
    # This method looks for html entities and encodes it
    # if none are found. Most of the time this won't change
    # the string.
    def encode_unless_encoded(text)
      return text if contains_html_entities?(text)
      encode(text)
    end
  end
end

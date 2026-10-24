# a collection of custom errors for the application
module BackupBrain
  module Errors
    class UnarchivableUrl < StandardError; end

    # The remote server answered, but with an empty body. A zero-byte
    # archive file is never useful, so callers substitute the
    # missing-image / missing-audio placeholder instead of linking to it.
    class EmptyDownload   < UnarchivableUrl; end

    class StorageError    < StandardError; end

    class InvalidTag      < StandardError; end

    class UnknownSetting  < StandardError; end

    class InvalidSetting  < StandardError; end

    class UnsupportedDocumentType < StandardError; end
  end
end

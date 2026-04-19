# a collection of custom errors for the application
module BackupBrain
  module Errors
    class UnarchivableUrl < StandardError; end

    class StorageError    < StandardError; end

    class InvalidTag      < StandardError; end

    class UnknownSetting  < StandardError; end

    class InvalidSetting  < StandardError; end

    class UnsupportedDocumentType < StandardError; end
  end
end

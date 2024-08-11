# a collection of custom errors for the application
module BackupBrain
  module Errors
    class UnarchivableUrl < StandardError; end

    class InvalidTag      < StandardError; end
  end
end

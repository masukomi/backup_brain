# lib/upload_importer.rb

module BackupBrain
  class UploadImporter
    def self.get_text(maybe_file)
      raw_text = nil
      if maybe_file.is_a? String
        raw_text = maybe_file
      elsif maybe_file.respond_to?(:read)
        raw_text = maybe_file.read
      elsif maybe_file.respond_to?(:path)
        raw_text = File.read(maybe_file.path)
      elsif raw_text.nil?
        raise ArgumentError.new("can't read data from maybe_file file")
      end
      raw_text
    end
  end
end

# lib/executables.rb

module BackupBrain
  module Executables
    # @return [String|nil] the memoized path to the executable or nil
    def executable_path(name)
      return _binaries[name] if _binaries.has_key?(name)
      _binaries[name] = find_executable(name)
      _binaries[name]
    end

    # @return [String|nil] the path to the executable or nil
    def find_executable(name)
      out, status = Open3.capture2("which", name)
      return out.strip if status.success? && out.strip.present?
      # binaries in local bin directory trump path ones
      [Rails.root.join("bin"), "/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"].each do |dir|
        candidate = File.join(dir, name)
        return candidate if File.executable?(candidate)
      end
      nil
    end

    # memoized hash of
    # executable_name => path or nil
    # ⚠️ only executable_path(name) should call this
    def _binaries
      @binaries ||= {}
    end
  end
end

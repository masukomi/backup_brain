require "uri"
require "open3"
require "shellwords"
require "yaml"

module BackupBrain
  # Dispatches to the configured CLI extraction tool based on the URL's hostname.
  # Configuration is loaded from config/archive_tools.yml at startup.
  #
  # Each tool entry must have:
  #   name:    (string) human-readable identifier used in log/error messages
  #   command: (string) shell command template; {TEMPFILE} and {URL} are substituted
  #   default: (boolean, optional) true for the fallback tool
  #   domains: (array, optional) hostnames this tool handles (subdomain-matched)
  #
  # The first tool whose domains list matches the request URL's hostname is used.
  # If no tool matches, the default tool is used.
  class ToolDispatcher
    CONFIG_PATH = Rails.root.join("config/archive_tools.yml")

    class Tool
      attr_reader :name, :domains, :command

      def initialize(config)
        @name             = config["name"]
        @domains          = Array(config["domains"]).map(&:downcase)
        @command          = config["command"]
        @default          = config["default"] == true
        @handles_download = config["handles_download"] == true
      end

      def default? = @default
      def handles_download? = @handles_download

      def matches_host?(host)
        @domains.any? { |d| host == d || host.end_with?(".#{d}") }
      end
    end

    def self.instance
      @instance ||= new
    end

    # Force a reload from disk (useful after config changes in development).
    def self.reload!
      @instance = new
    end

    def initialize(config_path = CONFIG_PATH)
      if File.exist?(config_path)
        raw   = YAML.safe_load_file(config_path)
        tools = raw.fetch("tools", []).map { |t| Tool.new(t) }
      else
        Rails.logger.warn("config/archive_tools.yml not found; falling back to default reader invocation")
        tools = [Tool.new("name" => "reader", "default" => true,
                          "command" => "bin/reader -o --image-mode none {TEMPFILE}")]
      end

      @default_tool = tools.find(&:default?) || tools.last
      @domain_tools = tools.reject(&:default?)
    end

    # Returns true if the default tool's binary exists and is executable.
    def viable_install?
      return false unless @default_tool
      executable_path?(Shellwords.split(@default_tool.command).first)
    end

    # Returns true if the tool matched for +url+ handles its own download,
    # meaning the caller should not download the URL to a tempfile first.
    def handles_download?(url)
      find_tool_for(url).handles_download?
    end

    # Finds the appropriate tool for +url+, runs it against +tempfile+,
    # and returns the resulting markdown string.
    # +tempfile+ may be nil when the tool has handles_download: true.
    # Raises BackupBrain::Errors::UnarchivableUrl on non-zero exit.
    def run(url, tempfile)
      tool = find_tool_for(url)
      invoke(tool, url, tempfile)
    end

    private

    def find_tool_for(url)
      host = URI.parse(url).host.downcase
      @domain_tools.find { |t| t.matches_host?(host) } || @default_tool
    end

    def invoke(tool, url, tempfile)
      args = Shellwords.split(tool.command).map do |arg|
        arg.gsub("{TEMPFILE}", tempfile ? tempfile.path : "").gsub("{URL}", url)
      end
      _, stdout, stderr, wait_thr = Open3.popen3(*args)
      markdown = stdout.gets(nil)&.chomp
      stdout.close
      error_string = stderr.gets(nil)&.chomp
      stderr.close
      exit_code = wait_thr.value
      return markdown if exit_code == 0
      raise BackupBrain::Errors::UnarchivableUrl.new(
        "problems invoking #{tool.name}: (Exit Code: #{exit_code}) #{error_string}"
      )
    end

    def executable_path?(cmd)
      path = cmd.start_with?("/") ? Pathname.new(cmd) : Rails.root.join(cmd)
      File.executable?(path)
    end
  end
end

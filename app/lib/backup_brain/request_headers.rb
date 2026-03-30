require "uri"
require "yaml"

module BackupBrain
  # Provides per-domain HTTP request headers for archiving requests.
  # Configuration is loaded from config/archive_request_headers.yml at startup.
  #
  # Each entry must have:
  #   name:    (string) human-readable identifier
  #   headers: (hash)   HTTP header name/value pairs
  #   default: (boolean, optional) true for the fallback header set
  #   domains: (array, optional)   hostnames this entry applies to (subdomain-matched)
  #
  # Per-domain headers are merged on top of the default headers, so domain entries
  # only need to specify what differs.
  class RequestHeaders
    CONFIG_PATH = Rails.root.join("config/archive_request_headers.yml")

    FALLBACK_USER_AGENT = ENV.fetch(
      "USER_AGENT_STRING",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.5112.79 Safari/537.36"
    )

    class HeaderSet
      attr_reader :name, :domains, :headers

      def initialize(config)
        @name    = config["name"]
        @domains = Array(config["domains"]).map(&:downcase)
        @headers = config["headers"] || {}
        @default = config["default"] == true
      end

      def default? = @default

      def matches_host?(host)
        @domains.any? { |d| host == d || host.end_with?(".#{d}") }
      end
    end

    def self.instance
      @instance ||= new
    end

    def self.reload!
      @instance = new
    end

    def initialize(config_path = CONFIG_PATH)
      if File.exist?(config_path)
        raw  = YAML.safe_load_file(config_path)
        sets = raw.fetch("headers", []).map { |h| HeaderSet.new(h) }
      else
        Rails.logger.warn("config/archive_request_headers.yml not found; using built-in default headers")
        sets = [HeaderSet.new("name" => "default", "default" => true,
                              "headers" => {"User-Agent" => FALLBACK_USER_AGENT})]
      end

      @default_set  = sets.find(&:default?) || sets.last
      @domain_sets  = sets.reject(&:default?)
    end

    # Returns the merged headers hash for +url+.
    # Domain-specific headers are merged on top of the default headers.
    def headers_for(url)
      host       = URI.parse(url).host.to_s.downcase
      domain_set = @domain_sets.find { |s| s.matches_host?(host) }
      return @default_set.headers unless domain_set
      @default_set.headers.merge(domain_set.headers)
    end
  end
end

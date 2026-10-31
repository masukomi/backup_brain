require "uri"
require "yaml"

module BackupBrain
  # A singleton class that checks the hostname of an url
  # to see if it is in the list of domains known to be unarchivable.
  # Subdomains of a listed domain match automatically, so listing
  # reddit.com also covers www.reddit.com and old.reddit.com.
  class UnarchivableDomainsChecker
    CONFIG_PATH = Rails.root.join("config/unarchivable_domains.yml")

    def self.instance
      @instance ||= new
    end

    # Force a reload from disk (useful after config changes in development).
    def self.reload!
      @instance = new
    end

    def initialize(config_path = CONFIG_PATH)
      if File.exist?(config_path)
        raw = YAML.safe_load_file(config_path)
        @domains = Set.new(Array(raw).map { |d| d.to_s.strip.downcase.delete_prefix("www.") })
      else
        Rails.logger.warn("#{config_path} not found; all domains considered potentially archivable")
        @domains = Set.new
      end
    end

    # @param url [String, URI::Generic]
    # @return [Boolean] false if the url is unparseable, has no host,
    #   or is on a domain known to be unarchivable
    def maybe_archivable?(url)
      return false if url.blank?
      uri = url.is_a?(URI::Generic) ? url : URI.parse(url.to_s.strip)
      hostname = uri.hostname&.downcase
      return false if hostname.blank?

      # check the host and every parent domain:
      # old.reddit.com → old.reddit.com, reddit.com
      segments = hostname.split(".")
      segments_minimum = segments.size - 1
      segments.each_index.none? { |i|
        i < segments_minimum ? @domains.include?(segments[i..].join(".")) : false
      }
    rescue URI::InvalidURIError
      false
    end
  end
end

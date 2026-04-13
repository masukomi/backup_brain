# lib/domains.rb

module BackupBrain
  module Domains
    VALID_DOMAIN_REGEXP = /(?:\w+\.)+\w+$/
    # downcases all the domains, and makes sure the list
    # doesn't contain duplicates
    def clean_domains!
      return if domains.blank?
      self.domains = domains.map { |item| clean_domain(item) }
        .compact
        .sort
        .uniq
    end

    # extracts the domain portion of an item
    # if it looks like an URL
    def clean_domain(item)
      return item unless item.include?("://")
      begin
        PublicSuffix.domain(URI.parse(item).host)
      rescue
        item
      end
    end

    def validate_domain
      return if domain.blank?
      # presuming presence validation will handle
      # things if blank isn't ok.
      unless domain.match?(VALID_DOMAIN_REGEXP)
        errors.add(:domain, :invalid, invalid_domain: domain)
      end
    end

    # validates that all the domains are strings that
    # at least vagualy resemble domains
    def validate_domains
      return if domains.blank?
      invalid = domains.reject { |d| d.match?(VALID_DOMAIN_REGEXP) }
      return if invalid.empty?
      errors.add(:domains, :invalid, invalid_domains: invalid.join(", "))
    end
  end
end

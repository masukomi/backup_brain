# lib/domains.rb

module BackupBrain
  class Domains
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

    # validates that all the domains are strings that
    # at least vagualy resemble domains
    def validate_domains
      return if domains.blank?
      invalid = domains.reject { |d| d.match?(/(?:\w+\.)+\w+$/) }
      return if invalid.empty?
      errors.add(:domains, :invalid, invalid_domains: invalid.join(", "))
    end
  end
end

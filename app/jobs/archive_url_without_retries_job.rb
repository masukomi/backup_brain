class ArchiveUrlWithoutRetriesJob < ArchiveUrlJob
  def max_attempts
    1
  end
end

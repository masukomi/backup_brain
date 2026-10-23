# Moves the local archives/ folder to the S3 compatible bucket configured
# in Settings (enable_s3_storage and the s3_* settings).
#
#   bundle exec rails runner scripts/upload_archives_to_s3.rb [options]
#
# What it does, in order:
#   1. Offers to back up the database with scripts/export.sh.
#   2. Uploads every file under archives/ (skipping objects that are already
#      present with the right size, so it's safe to re-run after a failure).
#   3. Verifies every file: HEAD the object, compare sizes, then fetch its
#      first byte through a presigned URL exactly as a browser would.
#   4. Points the url of every MediaObject whose file was verified at
#      its new s3://<bucket>/<key> location.
#   5. Optionally deletes the local copies of verified files.
#
# Options:
#   --yes           answer "yes" to the backup and "continue anyway" prompts
#   --no-backup     skip the backup prompt
#   --delete-local  delete local copies of verified files without asking
#   --keep-local    never delete local copies (and don't ask)
#   --dry-run       report what would happen; upload and change nothing
#
# Exit codes: 0 success, 1 some files failed, 78 (EX_CONFIG) S3 not enabled.

require "paint"
require "ruby-progressbar"
require "httparty"
require "set"

options = {
  yes: ARGV.include?("--yes"),
  backup: !ARGV.include?("--no-backup"),
  delete_local: ARGV.include?("--delete-local"),
  keep_local: ARGV.include?("--keep-local"),
  dry_run: ARGV.include?("--dry-run")
}
unknown = ARGV.reject { |a| %w[--yes --no-backup --delete-local --keep-local --dry-run].include?(a) }
unless unknown.empty?
  warn Paint["Unknown option(s): #{unknown.join(" ")}", :red]
  exit 64 # EX_USAGE
end

def ask?(question, default_yes: true, auto_yes: false)
  return true if auto_yes
  suffix = default_yes ? "[Y/n]" : "[y/N]"
  print "#{question} #{suffix} "
  answer = $stdin.gets.to_s.strip.downcase
  return default_yes if answer.empty?
  answer.start_with?("y")
end

def progress_bar(title, total)
  ProgressBar.create(
    total: total,
    format: "%t |%B| %c/%C  %E  elapsed: %a",
    title: title,
    output: $stdout,
    projector: {type: "smoothing", strength: 0.5}
  )
end

# ── preflight ──────────────────────────────────────────────────────────
unless BackupBrain::S3Storage.enabled?
  warn Paint["S3 storage isn't enabled.", :red]
  warn "Fill in the s3_* settings and turn on enable_s3_storage at /settings first."
  exit 78 # EX_CONFIG
end

storage = BackupBrain::S3Storage.instance
archives_root = Rails.root.join(BackupBrain::ArchiveTools::ARCHIVES_FOLDER)
unless archives_root.directory?
  puts "Nothing to do: #{archives_root} doesn't exist."
  exit 0
end

local_files = Dir.glob(archives_root.join("**", "*").to_s, File::FNM_DOTMATCH)
  .select { |f| File.file?(f) }
  .reject { |f| File.basename(f) == ".DS_Store" }
  .sort

puts "Bucket:       #{storage.bucket}"
puts "Key prefix:   #{storage.key_prefix.presence || "(none)"}"
puts "Local files:  #{local_files.size} under #{archives_root}"
puts "Total size:   #{(local_files.sum { |f| File.size(f) } / 1024.0 / 1024.0).round(1)} MB"
puts Paint["DRY RUN: nothing will be uploaded, changed or deleted.", :yellow] if options[:dry_run]
puts

begin
  storage.client.head_bucket(bucket: storage.bucket)
rescue => e
  warn Paint["Can't reach bucket #{storage.bucket}: #{e.class}: #{e.message}", :red]
  exit 78
end

if local_files.empty?
  puts "No local archive files found. Nothing to upload."
  exit 0
end

# ── backup ─────────────────────────────────────────────────────────────
if options[:backup] && !options[:dry_run]
  if ask?("Create a backup of the database with scripts/export.sh before continuing?", auto_yes: options[:yes])
    export_script = Rails.root.join("scripts", "export.sh").to_s
    puts "Running #{export_script} …"
    unless system(export_script)
      warn Paint["Backup script exited with an error.", :red]
      exit 1 unless ask?("Continue without a backup?", default_yes: false, auto_yes: options[:yes])
    end
    puts
  end
end

# ── upload ─────────────────────────────────────────────────────────────
uploaded = []
already_present = []
upload_failures = {} # path => message

bar = progress_bar("Uploading", local_files.size)
local_files.each do |path|
  key = storage.key_for_local_path(path)
  begin
    existing = storage.head(key)
    if existing && existing.content_length == File.size(path)
      already_present << path
    elsif options[:dry_run]
      uploaded << path
    else
      storage.upload(path, key)
      uploaded << path
    end
  rescue => e
    upload_failures[path] = "#{e.class}: #{e.message}"
    bar.log Paint["  ✗ #{key}: #{upload_failures[path]}", :red]
  end
  bar.increment
end
puts
puts "Uploaded #{uploaded.size}, already present #{already_present.size}, failed #{upload_failures.size}"
puts

# ── verify ─────────────────────────────────────────────────────────────
# Every file, uploaded now or earlier, gets checked: HEAD for presence and
# size, then a 1-byte ranged GET through a presigned URL to prove the serving
# path works end-to-end.
verified_keys = Set.new
verify_failures = {} # path => message

candidates = (uploaded + already_present).sort
bar = progress_bar("Verifying", candidates.size)
candidates.each do |path|
  key = storage.key_for_local_path(path)
  begin
    if options[:dry_run] && !already_present.include?(path)
      verified_keys << key # would be uploaded; can't verify what isn't there
      next
    end
    head = storage.head(key)
    raise "not found after upload" unless head
    if head.content_length != File.size(path)
      raise "size mismatch (remote #{head.content_length}, local #{File.size(path)})"
    end
    response = HTTParty.get(storage.presigned_url(key, expires_in: 300),
      headers: {"Range" => "bytes=0-0"}, timeout: 30)
    unless [200, 206].include?(response.code)
      raise "presigned URL returned HTTP #{response.code}"
    end
    verified_keys << key
  rescue => e
    verify_failures[path] = e.message
    bar.log Paint["  ✗ #{key}: #{e.message}", :red]
  ensure
    bar.increment
  end
end
puts
puts "Verified #{verified_keys.size}, failed #{verify_failures.size}"
puts

# ── repoint MediaObject urls ───────────────────────────────────────────
web_prefix = "/#{BackupBrain::ArchiveTools::ARCHIVES_FOLDER}/"
updated = 0
skipped_unverified = []
already_s3 = 0

bookmarks = Bookmark.where(:archives.exists => true)
bar = progress_bar("MediaObjects", bookmarks.count)
bookmarks.no_timeout.each do |bookmark|
  bookmark.archives.each do |archive|
    archive.media_objects.each do |mo|
      if mo.stored_in_s3?
        already_s3 += 1
        next
      end
      next unless mo.url.to_s.start_with?(web_prefix)
      key = storage.key_for_web_path(mo.url)
      unless verified_keys.include?(key)
        skipped_unverified << "#{bookmark._id} #{mo.url}"
        next
      end
      # `set` writes just this field, without running Bookmark callbacks
      # (search reindex, archive generation, …).
      mo.set(url: storage.s3_url_for_key(key)) unless options[:dry_run]
      updated += 1
    end
  end
  bar.increment
end
puts
puts "MediaObjects repointed #{updated}, already on S3 #{already_s3}, left alone (file not verified) #{skipped_unverified.size}"
puts

# ── delete local copies ────────────────────────────────────────────────
deletable = candidates.select { |path| verified_keys.include?(storage.key_for_local_path(path)) }
deleted = 0
if options[:dry_run]
  puts "Would offer to delete #{deletable.size} verified local file(s)."
elsif options[:keep_local]
  puts "Keeping all local copies (--keep-local)."
elsif deletable.any? && (options[:delete_local] ||
    ask?("Delete the #{deletable.size} local file(s) that were verified on S3? This cannot be undone.", default_yes: false))
  deletable.each do |path|
    File.delete(path)
    deleted += 1
  rescue => e
    warn Paint["  couldn't delete #{path}: #{e.message}", :red]
  end
  # prune directories left empty
  Dir.glob(archives_root.join("**", "*").to_s).select { |d| File.directory?(d) }.sort.reverse_each do |dir|
    Dir.rmdir(dir) if Dir.empty?(dir)
  end
  puts "Deleted #{deleted} local file(s)."
else
  puts "Local copies kept."
end
puts

# ── summary ────────────────────────────────────────────────────────────
puts Paint["Summary", :bold]
puts "  files on S3 and verified:  #{verified_keys.size} / #{local_files.size}"
puts "  media object urls updated: #{updated}"
puts "  local files deleted:       #{deleted}"
failures = upload_failures.merge(verify_failures)
if failures.any?
  puts Paint["  #{failures.size} file(s) failed; re-run this script to retry them:", :red]
  failures.each { |path, message| puts "    #{path.delete_prefix("#{Rails.root}/")} — #{message}" }
end
if skipped_unverified.any?
  puts Paint["  #{skipped_unverified.size} media object(s) still point at local paths (bookmark id, url):", :yellow]
  skipped_unverified.first(20).each { |line| puts "    #{line}" }
  puts "    …" if skipped_unverified.size > 20
end
exit(failures.any? ? 1 : 0)

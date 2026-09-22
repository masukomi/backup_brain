json.query @query
json.tags  @query_tags
json.total @bookmarks.count
json.results @bookmarks do |bookmark|
  json.id bookmark.id.to_s
  json.extract! bookmark, :title, :description, :tags, :created_at, :updated_at
  json.url bookmark.url
  json.app_url bookmark_url(bookmark)
  json.private bookmark.private
  json.to_read bookmark.to_read
  json.sensitive bookmark.sensitive
  json.archived bookmark.archives.any?
end

json.extract! bookmark, :id, :title, :url, :description, :tags, :created_at, :updated_at
json.url bookmark_url(bookmark, format: :json)

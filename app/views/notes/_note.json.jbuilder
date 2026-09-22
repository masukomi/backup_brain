json.id note.id.to_s
json.extract! note, :title, :string_data, :tags, :mime_type, :created_at, :updated_at
json.app_url note_url(note)
json.private note.private
json.sensitive note.sensitive

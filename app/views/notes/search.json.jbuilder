json.query @query
json.tags  @query_tags
json.total @notes.count
json.results @notes, partial: "notes/note", as: :note

# Register audio MIME types that Rails/Rack don't include by default.
# Used for forward (ext → MIME) lookups in content negotiation.
# Reverse lookups (MIME → ext) use Archive::AUDIO_MIME_EXTENSION_MAP instead.
#
# Uses ||= so we don't override any type Rack already knows about.
[
  [".aac",  "audio/aac"],
  [".flac", "audio/flac"],
  [".m4a",  "audio/mp4"],
  [".mp3",  "audio/mpeg"],
  [".oga",  "audio/ogg"],
  [".ogg",  "audio/ogg"],
  [".opus", "audio/opus"],
  [".wav",  "audio/wav"],
  [".webm", "audio/webm"],
].each do |ext, mime|
  Rack::Mime::MIME_TYPES[ext] ||= mime
end

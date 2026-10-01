class TodoUpload
  MAX_BYTES = 10.megabytes
  TYPES = { "image/png" => ".png", "image/jpeg" => ".jpg", "image/gif" => ".gif", "image/webp" => ".webp" }.freeze

  def self.allowed_blob?(blob)
    blob.metadata["sidecar_todo_upload"] == true && TYPES.key?(blob.content_type) && blob.byte_size.between?(1, MAX_BYTES)
  end

  def self.create!(upload)
    raise ArgumentError, "Choose a PNG, JPEG, GIF or WebP image (up to 10 MB)." unless upload.is_a?(ActionDispatch::Http::UploadedFile)
    raise ArgumentError, "Images must be between 1 byte and 10 MB." unless upload.size.between?(1, MAX_BYTES)
    type = Marcel::MimeType.for(upload.tempfile)
    raise ArgumentError, "Only PNG, JPEG, GIF and WebP image bytes are accepted." unless TYPES.key?(type)
    upload.tempfile.rewind
    # Strip paths/control characters; the filename is display-only, never a disk path.
    name = File.basename(upload.original_filename.to_s.tr("\\", "/")).gsub(/[^\p{L}\p{N}_. -]/, "_")[0, 120]
    name = "screenshot#{TYPES.fetch(type)}" if name.blank?
    ActiveStorage::Blob.create_and_upload!(io: upload.tempfile, filename: name, content_type: type,
      identify: false, metadata: { sidecar_todo_upload: true })
  end
end

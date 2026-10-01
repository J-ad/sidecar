class TodoAttachmentsController < ApplicationController
  def create
    blob = TodoUpload.create!(params[:file])
    render json: { sgid: blob.attachable_sgid, url: todo_attachment_path(blob.signed_id),
      filename: blob.filename.to_s, filesize: blob.byte_size, contentType: blob.content_type }, status: :created
  rescue ArgumentError => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def show
    blob = ActiveStorage::Blob.find_signed!(params[:id])
    return head :not_found unless TodoUpload.allowed_blob?(blob)
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Security-Policy"] = "default-src 'none'; sandbox"
    send_data blob.download, type: blob.content_type, filename: blob.filename.to_s, disposition: "inline"
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound, ActiveStorage::FileNotFoundError
    head :not_found
  end
end

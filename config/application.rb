require_relative "boot"
require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "active_job/railtie"
require "active_storage/engine"
require "action_text/engine"
require "rails/test_unit/railtie"
Bundler.require(*Rails.groups)
module Sidecar
  class Application < Rails::Application
    config.load_defaults 8.1
    config.eager_load = false
    # Signed rich-text attachment IDs must remain valid across local restarts.
    secret_path = File.expand_path("../storage/.secret_key_base", __dir__)
    FileUtils.mkdir_p(File.dirname(secret_path))
    begin
      File.open(secret_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(SecureRandom.hex(64)) }
    rescue Errno::EEXIST
      # Another local boot may have created it first.
    end
    config.secret_key_base = File.read(secret_path).strip
    config.active_storage.service = Rails.env.test? ? :test : :local
    config.active_storage.draw_routes = false
    config.active_storage.analyzers = []
    config.active_storage.previewers = []
    config.filter_parameters += [:notes, :checklist_text, :file]
    config.hosts = ["localhost", "127.0.0.1"]
    config.action_controller.forgery_protection_origin_check = true
    config.action_controller.allow_forgery_protection = !Rails.env.test?
    config.action_dispatch.show_exceptions = :none
    config.public_file_server.enabled = true
    config.active_record.schema_format = :ruby
    config.filter_parameters += [:evidence, :title, :next_action, :status, :answers, :questions, :request_payload, :context]
  end
end

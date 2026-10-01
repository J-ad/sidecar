require_relative "boot"
require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"
Bundler.require(*Rails.groups)
module Sidecar
  class Application < Rails::Application
    config.load_defaults 8.1
    config.eager_load = false
    config.secret_key_base = SecureRandom.hex(64)
    config.hosts = ["localhost", "127.0.0.1"]
    config.action_controller.forgery_protection_origin_check = true
    config.action_controller.allow_forgery_protection = !Rails.env.test?
    config.action_dispatch.show_exceptions = :none
    config.public_file_server.enabled = true
    config.active_record.schema_format = :ruby
    config.filter_parameters += [:evidence, :title, :next_action, :status]
  end
end

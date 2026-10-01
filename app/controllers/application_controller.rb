class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  before_action :loopback_only
  private
  def loopback_only
    head :forbidden unless %w[127.0.0.1 ::1].include?(request.remote_ip)
  end
end

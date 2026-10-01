Rails.application.routes.draw do
  root "panel#index"
  get "/sync-status", to: "panel#sync_status"
  post "/refresh", to: "panel#refresh"
  patch "/items/:id", to: "panel#update", as: :item
  get "/health", to: proc { [200, { "content-type" => "text/plain" }, ["ok"]] }
end

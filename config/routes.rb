Rails.application.routes.draw do
  root "panel#index"
  get "/questions", to: "questions#index", as: :questions
  post "/questions/:id/reply", to: "questions#reply", as: :question_reply
  get "/sync-status", to: "panel#sync_status"
  post "/refresh", to: "panel#refresh"
  patch "/items/:id", to: "panel#update", as: :item
  get "/health", to: proc { [200, { "content-type" => "text/plain" }, ["ok"]] }
end

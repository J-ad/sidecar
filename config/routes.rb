Rails.application.routes.draw do
  root "panel#index"
  get "/questions", to: "questions#index", as: :questions
  post "/questions/:id/reply", to: "questions#reply", as: :question_reply
  post "/questions/:id/suggestion", to: "questions#suggest", as: :question_suggestion
  get "/questions/:id/suggestion", to: "questions#suggestion_status"
  post "/questions/:id/suggestion/cancel", to: "questions#cancel_suggestion", as: :cancel_question_suggestion
  get "/sync-status", to: "panel#sync_status"
  post "/refresh", to: "panel#refresh"
  patch "/items/:id", to: "panel#update", as: :item
  get "/health", to: proc { [200, { "content-type" => "text/plain" }, ["ok"]] }
end

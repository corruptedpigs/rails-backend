Rails.application.routes.draw do
  # Sidekiq web UI (mount only in development for safety)
  require "sidekiq/web"
  require "sidekiq/cron/web"
  mount Sidekiq::Web => "/sidekiq" if Rails.env.development?

  # Health check
  get "/up", to: proc { [200, {}, ["OK"]] }

  # Article preview pages — the short-URL destination
  # Constraint ensures this never swallows /rails/... or /up
  get "/:public_id", to: "articles#show", as: :article,
    constraints: { public_id: /[a-z0-9]{8}/ }

  # Root redirects to the main corruptedpigs site
  root to: redirect("https://corruptedpigs.com", status: 302)
end

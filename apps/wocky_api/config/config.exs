# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# General application configuration

config :phoenix, :json_library, Jason

config :wocky_api,
  namespace: WockyAPI,
  ecto_repos: [Wocky.Repo],
  max_graphql_complexity: 8000,
  max_local_bots_search_radius:
    {:system, :integer, "WOCKY_MAX_LOCAL_BOTS_SEARCH_RADIUS", 50_000}

config :wocky_api, :generators,
  context_app: :wocky,
  binary_id: true

# Configures the endpoint
config :wocky_api, WockyAPI.Endpoint,
  http: [port: 4000],
  url: [host: "localhost", port: 4000],
  secret_key_base:
    "teo9ScPXCxIsZm9KWkEsAub4XqnAhp7FvQLGCVe9f3Bmvn9iyzt5Jkz/ZtxPUY8F",
  render_errors: [view: WockyAPI.ErrorView, accepts: ~w(json)],
  pubsub: [name: WockyAPI.PubSub, adapter: Phoenix.PubSub.PG2]

config :wocky_api, WockyAPI.MetricsEndpoint, http: [port: 8082]

config :wocky_api, :redlock,
  pool_size: 2,
  drift_factor: 0.01,
  max_retry: 10,
  retry_interval_base: 300,
  retry_interval_max: 3_000,
  reconnection_interval_base: 500,
  reconnection_interval_max: 5_000,
  servers: [
    [
      host: {:system, :string, "REDIS_HOST", "localhost"},
      port: {:system, :integer, "REDIS_PORT", 6379},
      ssl: {:system, :boolean, "REDIS_SSL", false},
      auth: {:system, :string, "REDIS_PASSWORD", nil},
      database: {:system, :integer, "REDIS_DB", 0}
    ]
  ]

config :prometheus, WockyAPI.PhoenixInstrumenter,
  controller_call_labels: [:controller, :action],
  duration_buckets: [
    10,
    25,
    50,
    100,
    250,
    500,
    1000,
    2500,
    5000,
    10_000,
    25_000,
    50_000,
    100_000,
    250_000,
    500_000,
    1_000_000,
    2_500_000,
    5_000_000,
    10_000_000
  ],
  registry: :default,
  duration_unit: :microseconds

config :prometheus, WockyAPI.PipelineInstrumenter,
  labels: [:status_class, :method, :host, :scheme, :request_path],
  duration_buckets: [
    10,
    100,
    1_000,
    10_000,
    100_000,
    300_000,
    500_000,
    750_000,
    1_000_000,
    1_500_000,
    2_000_000,
    3_000_000
  ],
  registry: :default,
  duration_unit: :microseconds

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"

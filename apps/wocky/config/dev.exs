use Mix.Config

config :wocky,
  start_watcher: {:system, :boolean, "WOCKY_START_WATCHER", true}

config :wocky, Wocky.User.GeoFence,
  enter_debounce_seconds: 0,
  exit_debounce_seconds: 0

config :wocky, Wocky.Repo,
  database: "wocky_dev",
  pool_size: 10

# Config for wocky_db_watcher to allow us to run it in tests to test the client
config :wocky_db_watcher, :db,
  database: {:system, :string, "WOCKY_DB_NAME", "wocky_dev"},
  username: {:system, :string, "WOCKY_DB_USER", "postgres"},
  password: {:system, :string, "WOCKY_DB_PASSWORD", "password"},
  hostname: {:system, :string, "WOCKY_DB_HOST", "localhost"},
  port: {:system, :integer, "WOCKY_DB_PORT", 5432},
  pool_size: {:system, :integer, "WOCKY_DB_POOL_SIZE", 15}

config :exometer_core,
  report: [reporters: [{:exometer_report_prometheus, [:enable_httpd]}]]

config :elixometer,
  reporter: :exometer_report_prometheus,
  env: Mix.env()

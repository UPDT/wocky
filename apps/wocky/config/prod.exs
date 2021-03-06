use Mix.Config

alias Wocky.Config.VaultAdapter

config :wocky,
  tros_backend: {:system, :module, "WOCKY_TROS_STORE", Wocky.TROS.Store.S3},
  dynamic_link_backend:
    {:system, :module, "WOCKY_DYN_LINK_BACKEND",
     Wocky.UserInvite.DynamicLink.Firebase},
  country_code_lookup_method:
    {:system, :atom, "WOCKY_CC_LOOKUP_METHOD", :twilio},
  goth_private_key: {{:via, VaultAdapter}, "firebase-private-key"},
  slack_token: {{:via, VaultAdapter}, "slack-token"},
  client_jwt_signing_key: {{:via, VaultAdapter}, "client-jwt-signing-key"},
  server_jwt_signing_key: {{:via, VaultAdapter}, "server-jwt-signing-key"},
  location_share_end_self: true

config :wocky, Wocky.Repo,
  password: {{:via, VaultAdapter}, "db-password"},
  ssl: true,
  ssl_opts: [cacertfile: 'etc/ssl/rds-ca-2019-root.pem']

config :wocky, Wocky.Location.GeoFence, visit_timeout_enabled: false

config :wocky, Wocky.Notifier.Email.Mailer,
  api_key: {{:via, VaultAdapter}, "mandrill-api-key", ""}

config :wocky, :pigeon,
  apns: [
    key:
      {{:via, VaultAdapter}, "apns-key",
       """
       -----BEGIN PRIVATE KEY-----
       XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
       XXXXXXXX
       -----END PRIVATE KEY-----
       """},
    key_identifier: {:system, :string, "APNS_KEY_IDENTIFIER", "NBJ9A4785H"},
    team_id: {:system, :string, "APNS_TEAM_ID", "W6M2PMRSBT"},
    mode: :prod
  ],
  fcm: [
    key: {{:via, VaultAdapter}, "fcm-key", ""}
  ]

config :dawdle, backend: Dawdle.Backend.SQS

config :exometer_core,
  report: [reporters: [{:exometer_report_prometheus, [:enable_httpd]}]]

config :elixometer,
  env: "${WOCKY_INST}"

config :ex_aws,
  access_key_id: :instance_role,
  secret_access_key: :instance_role

config :wocky, :redis, password: {{:via, VaultAdapter}, "redis-password", nil}

config :wocky, :redlock,
  servers: [
    [
      host: {:system, :string, "REDIS_HOST", "localhost"},
      port: {:system, :integer, "REDIS_PORT", 6379},
      ssl: {:system, :boolean, "REDIS_SSL", false},
      auth: {{:via, VaultAdapter}, "redis-password", nil},
      database: {:system, :integer, "REDIS_DB", 0}
    ]
  ]

config :fun_with_flags, :redis,
  password: {{:via, VaultAdapter}, "redis-password", nil}

config :honeybadger,
  api_key: {{:via, VaultAdapter}, "honeybadger-api-key"},
  breadcrumbs_enabled: true

config :ex_twilio,
  auth_token: {{:via, VaultAdapter}, "twilio-auth-token", nil}

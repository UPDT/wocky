# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :wocky,
  ecto_repos: [Wocky.Repo],

  # TROS file storage in test storage system
  tros_backend: {:system, :module, "WOCKY_TROS_STORE", Wocky.TROS.Store.Test},
  tros_s3_bucket: {:system, "WOCKY_TROS_S3_BUCKET", "wocky-tros-test"},
  tros_s3_region: {:system, "WOCKY_S3_REGION", "us-west-2"},
  tros_s3_server: {:system, "WOCKY_S3_SERVER", "s3.amazonaws.com"},
  tros_s3_access_key_id: {:system, "AWS_ACCESS_KEY_ID"},
  tros_s3_secret_key: {:system, "AWS_SECRET_ACCESS_KEY"},

  # Deployment notifications
  slack_token: {:system, :string, "SLACK_TOKEN"},

  # Authentication
  token_expiry_days: {:system, :integer, "WOCKY_TOKEN_EXPIRY_DAYS", 60},
  enable_auth_bypass: {:system, :boolean, "WOCKY_ENABLE_BYPASS", true},
  auth_bypass_prefixes: ["+1555"],
  client_jwt_signing_key:
    {:system, "WOCKY_CLIENT_JWT_SIGNING_KEY",
     "CgKG3D0OfVBMh3JiJfQGkS0SyTrBaaGfrl1MozWnjesSuhVLnMTHDwyXDC/f2dtu"},
  server_jwt_signing_key:
    {:system, "WOCKY_SERVER_JWT_SIGNING_KEY",
     "+K+XxznYgxCGLa5hZo9Qyb7QtpmmRPOgNXM4UYfKViYnuiIjTySItwSk7rH+Uv2g"},

  # Welcome email
  send_welcome_email: {:system, :boolean, "SEND_WELCOME_EMAIL", false},
  welcome_email_template: "official_tr_welcome_email",
  welcome_email_from: {"tinyrobot support", "support@tinyrobot.com"},
  welcome_email_subject: "Welcome to tinyrobot!",
  welcome_field_mappings: [{"user_handle", :handle}],

  # SMS messaging
  sms_backend: {:system, :module, "WOCKY_SMS_BACKEND", Wocky.SMS.Sandbox},
  twilio_number: "+12133401134",
  max_sms_per_user: {:system, :integer, "WOCKY_MAX_SMS_PER_USER", 100},

  # Country code
  country_code_lookup_method:
    {:system, :atom, "WOCKY_CC_LOOKUP_METHOD", :hardwire},
  country_code_hardwire_value:
    {:system, :string, "WOCKY_CC_HARDWIRE_VAL", "US"},

  # Dynamic links
  dynamic_link_backend:
    {:system, :module, "WOCKY_DYN_LINK_BACKEND", Wocky.DynamicLink.Sandbox},
  app_store_id: "1295678402",
  ios_bundle_id: "com.hippware.tinyrobot",
  firebase_domain_url_prefix: "https://tinyrobot.page.link",
  firebase_link_prefix: "https://tinyrobot.com/?inviteCode=",

  # Diagnostics
  log_traffic: {:system, :boolean, "WOCKY_LOG_TRAFFIC", true}

config :wocky, :redis,
  host: {:system, :string, "REDIS_HOST", "localhost"},
  port: {:system, :integer, "REDIS_PORT", 6379},
  db: {:system, :integer, "REDIS_DB", 0}

config :wocky, :redlock,
  pool_size: 2,
  drift_factor: 0.01,
  max_retry: 3,
  retry_interval_base: 300,
  retry_interval_max: 3_000,
  reconnection_interval_base: 500,
  reconnection_interval_max: 5_000,
  servers: [
    [
      host: {:system, :string, "REDIS_HOST", "localhost"},
      port: {:system, :integer, "REDIS_PORT", 6379}
    ]
  ]

# location processing
config :wocky, Wocky.User.GeoFence,
  enable_notifications: true,
  async_processing: false,
  debounce: true,
  enter_debounce_seconds:
    {:system, :integer, "WOCKY_ENTER_DEBOUNCE_SECONDS", 30},
  exit_debounce_seconds: {:system, :integer, "WOCKY_EXIT_DEBOUNCE_SECONDS", 30},
  max_accuracy_threshold:
    {:system, :integer, "WOCKY_GEOFENCE_MAX_ACCURACY_THRESHOLD", 90},
  max_slow_speed: {:system, :integer, "WOCKY_GEOFENCE_MAX_SLOW_SPEED", 2},
  max_exit_distance:
    {:system, :integer, "WOCKY_GEOFENCE_MAX_EXIT_DISTANCE", 200},
  stale_update_seconds:
    {:system, :integer, "WOCKY_GEOFENCE_STALE_UPDATE_SECONDS", 300},
  save_locations: {:system, :boolean, "WOCKY_GEOFENCE_SAVE_LOCATIONS", true}

# Push notifications
config :wocky, Wocky.Push,
  enabled: {:system, :boolean, "WOCKY_PUSH_ENABLED", false},
  sandbox: {:system, :boolean, "WOCKY_PUSH_SANDBOX", false},
  reflect: {:system, :boolean, "WOCKY_PUSH_REFLECT", false},
  topic: {:system, :string, "WOCKY_PUSH_TOPIC", "app"},
  uri_prefix: {:system, :string, "WOCKY_PUSH_URI_PREFIX", "tinyrobot"},
  timeout: {:system, :integer, "WOCKY_PUSH_TIMEOUT", 60_000},
  log_payload: {:system, :boolean, "WOCKY_PUSH_LOG_PAYLOAD", true}

config :wocky, Wocky.Repo,
  adapter: Ecto.Adapters.Postgres,
  types: Wocky.Repo.PostgresTypes,
  database: {:system, :string, "WOCKY_DB_NAME", "wocky"},
  username: {:system, :string, "WOCKY_DB_USER", "postgres"},
  password: {:system, :string, "WOCKY_DB_PASSWORD", "password"},
  hostname: {:system, :string, "WOCKY_DB_HOST", "localhost"},
  port: {:system, :integer, "WOCKY_DB_PORT", 5432},
  pool_size: {:system, :integer, "WOCKY_DB_POOL_SIZE", 15},
  migration_timestamps: [type: :utc_datetime_usec]

config :wocky, Wocky.Mailer,
  adapter: {:system, :module, "BAMBOO_ADAPTER", Bamboo.TestAdapter},
  api_key: {:system, :string, "MANDRILL_API_KEY", ""}

config :wocky_db_watcher,
  backend: WockyDBWatcher.Backend.Direct,
  channel: "wocky_db_watcher_notify"

config :email_checker, validations: [EmailChecker.Check.Format]

config :ex_aws,
  access_key_id: [
    {:system, "AWS_ACCESS_KEY_ID"},
    {:awscli, "default", 30},
    :instance_role
  ],
  secret_access_key: [
    {:system, "AWS_SECRET_ACCESS_KEY"},
    {:awscli, "default", 30},
    :instance_role
  ]

config :pigeon, :debug_log, true

config :pigeon, :apns,
  apns_default: %{
    cert: {:wocky, "certs/testing.crt"},
    key: {:wocky, "certs/testing.key"},
    mode: :dev
  }

config :ex_twilio,
  account_sid: {:system, "TWILIO_ACCOUNT_SID"},
  auth_token: {:system, "TWILIO_AUTH_TOKEN"}

config :goth,
  json: """
  {
    "type": "service_account",
    "project_id": "my-project-1480497595993",
    "private_key_id": "b9d64bc1a6d8edda824eb2ab984c8238701818ea",
    "private_key": "#{System.get_env("FIREBASE_PRIVATE_KEY") || "dummy_key"}",
    "client_email": "firebase-adminsdk-xrj66@my-project-1480497595993.iam.gserviceaccount.com",
    "client_id": "107308386875224786877",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-xrj66%40my-project-1480497595993.iam.gserviceaccount.com"
  }
  """

import_config "#{Mix.env()}.exs"

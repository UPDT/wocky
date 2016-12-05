use Mix.Config

config :schemata,
  cluster: [
    username: 'cassandra',
    password: 'cassandra',
    seed_hosts: [
      {'127.0.0.1', 9042}
    ],
    keyspaces: [
      wocky_shared: [
        strategy: :simple,
        factor: 1,
        clients: 10
      ],
      wocky_localhost: [
        strategy: :simple,
        factor: 1,
        clients: 10
      ]
    ]
  ]

config :lager,
  extra_sinks: [
    error_logger_lager_event: [
      handlers: [
        lager_file_backend: [file: 'error_logger.log', level: :info]
      ]
    ]
  ]

config :honeybadger,
  environment_name: "Development"

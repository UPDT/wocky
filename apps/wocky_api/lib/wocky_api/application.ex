defmodule WockyAPI.Application do
  @moduledoc false

  use Application

  alias WockyAPI.Callbacks
  alias WockyAPI.Endpoint
  alias WockyAPI.Middleware.Instrumenter, as: AbsintheInstrumenter
  alias WockyAPI.PhoenixInstrumenter
  alias WockyAPI.PipelineInstrumenter
  alias WockyAPI.PrometheusExporter

  def start(_type, _args) do
    import Supervisor.Spec

    PhoenixInstrumenter.setup()
    PipelineInstrumenter.setup()
    PrometheusExporter.setup()
    AbsintheInstrumenter.install(WockyAPI.Schema)

    # Define workers and child supervisors to be supervised
    children = [
      # Start the endpoints when the application starts
      supervisor(WockyAPI.Endpoint, []),
      supervisor(Absinthe.Subscription, [WockyAPI.Endpoint]),
      supervisor(WockyAPI.MetricsEndpoint, [])
    ]

    opts = [strategy: :one_for_one, name: WockyAPI.Supervisor]

    Callbacks.register()

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end

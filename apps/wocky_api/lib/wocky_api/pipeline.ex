defmodule WockyAPI.Pipeline do
  @moduledoc "Custom logging pipeline for GraphQL"

  alias Absinthe.Phoenix.Channel
  alias Absinthe.Pipeline
  alias Absinthe.Plug
  alias WockyAPI.PipelineLog

  def pipeline(config, opts) do
    config
    |> Plug.default_pipeline(opts)
    |> add_logger(opts)
  end

  def channel_pipeline(schema_mod, opts) do
    schema_mod
    |> Channel.default_pipeline(opts)
    |> add_logger(opts)
  end

  def add_logger(pipeline, opts) do
    pipeline
    |> Pipeline.insert_before(Absinthe.Phase.Parse, [
      {PipelineLog, [{:phase, :request} | opts]}
    ])
    |> Pipeline.insert_after(Absinthe.Phase.Document.Result, [
      {PipelineLog, [{:phase, :response} | opts]}
    ])
  end
end
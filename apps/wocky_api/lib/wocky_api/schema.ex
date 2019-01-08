defmodule WockyAPI.Schema do
  @moduledoc "GraphQL schema for the Wocky API"

  use Absinthe.Schema
  use Absinthe.Relay.Schema, :modern

  alias WockyAPI.Middleware.Auth
  alias WockyAPI.Middleware.Instrumenter

  import_types Absinthe.Type.Custom
  import_types Kronky.ValidationMessageTypes
  import_types WockyAPI.Schema.AuthTypes
  import_types WockyAPI.Schema.BlockTypes
  import_types WockyAPI.Schema.BotTypes
  import_types WockyAPI.Schema.LocationTypes
  import_types WockyAPI.Schema.MediaTypes
  import_types WockyAPI.Schema.MessageTypes
  import_types WockyAPI.Schema.NotificationTypes
  import_types WockyAPI.Schema.UserTypes
  import_types WockyAPI.Types.AInt
  import_types WockyAPI.Types.UUID

  query do
    import_fields :bot_queries
    import_fields :media_queries
    import_fields :notification_queries
    import_fields :user_queries
  end

  mutation do
    import_fields :auth_mutations
    import_fields :block_mutations
    import_fields :bot_mutations
    import_fields :contact_mutations
    import_fields :push_notifications_mutations
    import_fields :location_mutations
    import_fields :media_mutations
    import_fields :message_mutations
    import_fields :user_invite_code_mutations
    import_fields :user_mutations
  end

  subscription do
    import_fields :bot_subscriptions
    import_fields :message_subscriptions
    import_fields :notification_subscriptions
    import_fields :user_subscriptions
  end

  def middleware(middleware, field, object) do
    middleware
    |> Auth.middleware(field, object)
    |> Instrumenter.instrument(field, object)
    |> Enum.into([ApolloTracing.Middleware.Tracing])
  end
end

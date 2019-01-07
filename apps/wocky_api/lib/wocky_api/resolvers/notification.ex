defmodule WockyAPI.Resolvers.Notification do
  @moduledoc "GraphQL resolver for bot objects"

  alias Wocky.User.Notification
  alias WockyAPI.Resolvers.Utils

  def get_notifications(parent, args, %{context: %{current_user: requestor}}) do
    requestor
    |> Notification.user_query(args[:before_id], args[:after_id])
    |> Utils.connection_from_query(parent, args)
    |> Utils.map_edges(&to_graphql/1)
  end

  def to_graphql(%Notification{id: id, created_at: created_at} = n),
    do: %{data: n, id: id, created_at: created_at}

  def resolve_type(%{type: type}, _) do
    case type do
      :bot_item -> :bot_item_notification
      :geofence_event -> :geofence_event_notification
      :bot_invitation -> :bot_invitation_notification
      :bot_invitation_response -> :bot_invitation_response_notification
      :user_follow -> :user_follow_notification
      :user_invitation -> :user_invitation_notification
    end
  end

  def resolve_update_type(%{data: _}, _), do: :notification

  def resolve_update_type(_, _), do: :notification_deleted
end

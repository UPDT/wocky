defmodule Wocky.Callbacks.Relationship do
  @moduledoc "DB callback handler for location shares"

  use DawdleDB.Handler, type: Wocky.Contacts.Relationship

  alias Wocky.Contacts
  alias Wocky.Contacts.Relationship
  alias Wocky.Contacts.Share
  alias Wocky.Events.LocationShare
  alias Wocky.Events.LocationShareEnd
  alias Wocky.Events.LocationShareEndSelf
  alias Wocky.Events.UserBefriend
  alias Wocky.Notifier
  alias Wocky.Repo.Hydrator

  @impl true
  def handle_insert(%Relationship{} = new) do
    _ = Contacts.refresh_share_cache(new.user_id)

    if new.state == :friend do
      notify_befriend(new)
    end

    check_share_notification(new.share_type, :disabled, new.state, nil, new)
  end

  @impl true
  def handle_update(%Relationship{} = new, %Relationship{} = old) do
    _ = Contacts.refresh_share_cache(new.user_id)

    if new.state == :friend and old.state != :friend do
      notify_befriend(new)
    end

    check_share_notification(
      new.share_type,
      old.share_type,
      new.state,
      old.state,
      new
    )
  end

  @impl true
  def handle_delete(%Relationship{} = old) do
    _ = Contacts.refresh_share_cache(old.user_id)

    check_share_notification(:disabled, old.share_type, nil, old.state, old)
  end

  # Existing friends, just look at share types
  defp check_share_notification(new_type, old_type, :friend, :friend, rec),
    do: handle_share_notification(new_type, old_type, rec)

  # New friendship - treat previous share state as disabled
  defp check_share_notification(
         new_type,
         _old_type,
         :friend,
         _non_friend,
         rec
       ),
       do: handle_share_notification(new_type, :disabled, rec)

  # Users have un-friended. Treat current share type as disabled.
  defp check_share_notification(
         _new_type,
         old_type,
         _non_friend,
         :friend,
         rec
       ),
       do: handle_share_notification(:disabled, old_type, rec)

  # Users weren't friends and still aren't - nothing to do
  defp check_share_notification(
         _new_type,
         _old_type,
         _non_friend,
         _old_state,
         _rec
       ),
       do: :ok

  # Share type is unchanged
  defp handle_share_notification(t, t, _rec), do: :ok

  # Always share mode has been newly enabled from either disabled or nearby mode
  defp handle_share_notification(:always, _, rec),
    do: notify_share_start(rec)

  # Nearby mode has been enabled. The notification will be generated by the next
  # location update if the users are nearby - no need to do anything here.
  defp handle_share_notification(:nearby, _, _rec), do: :ok

  # Share has been disabled
  defp handle_share_notification(:disabled, _, rec), do: notify_share_end(rec)

  defp notify_share_start(share) do
    Hydrator.with_assocs(share, [:user, :contact], fn rec ->
      %LocationShare{
        to: rec.contact,
        from: rec.user,
        expires_at: Share.make_expiry(),
        share_id: rec.share_id,
        share_type: rec.share_type,
        other_user_share_type: Contacts.cached_share_type(rec.contact, rec.user)
      }
      |> Notifier.notify()
    end)
  end

  defp notify_share_end(share) do
    Hydrator.with_assocs(share, [:user, :contact], fn rec ->
      %LocationShareEnd{
        to: rec.contact,
        from: rec.user,
        share_id: share.share_id
      }
      |> Notifier.notify()

      if Confex.get_env(:wocky, :location_share_end_self) do
        %LocationShareEndSelf{
          to: rec.user,
          from: rec.contact,
          share_id: share.share_id
        }
        |> Notifier.notify()
      end
    end)
  end

  defp notify_befriend(relationship) do
    Hydrator.with_assocs(relationship, [:user, :contact], fn rec ->
      %UserBefriend{
        to: rec.user,
        from: rec.contact
      }
      |> Notifier.notify()
    end)
  end
end

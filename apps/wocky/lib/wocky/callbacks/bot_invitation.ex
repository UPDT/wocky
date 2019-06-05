defmodule Wocky.Callbacks.BotInvitation do
  @moduledoc """
  DB Callback handler for bot invitations
  """

  use DawdleDB.Handler, type: Wocky.Bot.Invitation

  alias Wocky.Bot.Invitation
  alias Wocky.Events.BotInvitation
  alias Wocky.Events.BotInvitationResponse
  alias Wocky.Notifier
  alias Wocky.Repo.Hydrator

  def handle_insert(new) do
    Hydrator.with_assocs(new, [:user, :invitee, :bot], fn rec ->
      %BotInvitation{
        to: rec.invitee,
        from: rec.user,
        bot: rec.bot,
        invitation: rec
      }
      |> Notifier.notify()
    end)
  end

  def handle_update(
        %Invitation{accepted: accepted?} = new,
        %Invitation{accepted: nil}
      )
      when not is_nil(accepted?) do
    Hydrator.with_assocs(new, [:user, :invitee, :bot], fn rec ->
      %BotInvitationResponse{
        to: rec.user,
        from: rec.invitee,
        bot: rec.bot,
        invitation: rec
      }
      |> Notifier.notify()
    end)
  end

  def handle_update(_new, _old), do: :ok
end

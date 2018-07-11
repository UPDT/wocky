defmodule WockyAPI.Callbacks.Bot do
  @moduledoc """
  Callbacks for DB bot changes
  """

  import Ecto.Query

  alias Wocky.{Bot, Repo, Roster}
  alias Wocky.Watcher.Client
  alias WockyAPI.Resolvers.Bot, as: BotResolver
  alias WockyDBWatcher.Event

  def register do
    Client.subscribe(Bot, :insert, &handle_insert/1)
    Client.subscribe(Bot, :update, &handle_update/1)
    Client.subscribe(Bot, :delete, &handle_delete/1)
  end

  def handle_update(%Event{
        action: :update,
        old: %Bot{public: false},
        new: %Bot{public: true} = bot
      }) do
    notify_subscribers(bot, :publicized)
  end

  def handle_update(%Event{
        action: :update,
        old: %Bot{public: true} = bot,
        new: %Bot{public: false}
      }) do
    notify_subscribers(bot, :privatized)
  end

  def handle_update(_), do: :ok

  def handle_insert(%Event{action: :insert, new: %Bot{public: true} = bot}) do
    notify_subscribers(bot, :created)
  end

  def handle_insert(_), do: :ok

  def handle_delete(%Event{action: :delete, old: %Bot{public: true} = bot}) do
    notify_subscribers(bot, :deleted)
  end

  def handle_delete(_), do: :ok

  defp notify_subscribers(bot, action) do
    bot.user_id
    |> Roster.followers_query(bot.user_id, false)
    |> select([u], u.id)
    |> Repo.all()
    |> BotResolver.notify_discover_subscriptions(bot, action)
  end
end
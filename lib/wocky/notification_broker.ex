defmodule Wocky.PushNotificationBroker do
  @moduledoc """
  Using a GenStage for implementing a GenEvent manager
  replacement where each handler runs as a separate process.

  This GenEvent-style system provides event publish/subscription
  functionality for the push notification system.
  """

  use GenStage

  @timeout 5000

  @type jid :: :ejabberd.jid

  @doc """
  Starts the broadcaster.
  """
  def start_link() do
    GenStage.start_link(__MODULE__, :ok, name: PushNotifications)
  end

  @doc """
  Sends an event and returns only after the event is dispatched.
  """
  @spec send(PushNotificaiton.t) :: :ok
  def send(notification) do
    GenStage.call(__MODULE__, {:notify, notification}, @timeout)
  end

  ## Callbacks

  def init(:ok) do
    {:producer, {:queue.new, 0}, dispatcher: GenStage.BroadcastDispatcher}
  end

  def handle_call({:notify, event}, from, {queue, demand}) do
    dispatch_events(:queue.in({from, event}, queue), demand, [])
  end

  def handle_demand(incoming_demand, {queue, demand}) do
    dispatch_events(queue, incoming_demand + demand, [])
  end

  ## Helpers

  defp dispatch_events(queue, demand, events) do
    with d when d > 0 <- demand,
         {{:value, {from, event}}, queue} <- :queue.out(queue) do
      GenStage.reply(from, :ok)
      dispatch_events(queue, demand - 1, [event | events])
    else
      _ -> {:noreply, Enum.reverse(events), {queue, demand}}
    end
  end
end

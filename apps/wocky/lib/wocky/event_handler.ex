defmodule Wocky.EventHandler do
  @moduledoc """
  Using a GenStage for implementing a GenEvent manager
  replacement where each handler runs as a separate process.

  This GenEvent-style system provides event publish/subscription
  functionality for the push notification system.
  """

  use GenStage

  @timeout 5000

  @type state :: {:queue.queue, non_neg_integer}

  @doc """
  Starts the broadcaster.
  """
  @spec start_link :: {:ok, pid}
  def start_link do
    GenStage.start_link(__MODULE__, :ok, name: EventHandler)
  end

  @doc """
  Broadcasts an event and returns only after the event is dispatched.
  """
  @spec broadcast(map) :: :ok
  def broadcast(event) do
    GenStage.call(EventHandler, {:broadcast, event}, @timeout)
  end

  ## Callbacks

  @spec init(:ok) :: {:producer, state, Keyword.t}
  def init(:ok) do
    {:producer, {:queue.new, 0}, dispatcher: GenStage.BroadcastDispatcher}
  end

  @spec handle_call({:broadcast, term}, term, state) :: {:noreply, list, state}
  def handle_call({:broadcast, event}, from, {queue, demand}) do
    dispatch_events(:queue.in({from, event}, queue), demand, [])
  end

  @spec handle_demand(non_neg_integer, state) :: {:noreply, list, state}
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
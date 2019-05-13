defmodule Wocky.User.Location.Handler do
  @moduledoc """
  This is the per-user location update handler process
  """

  use GenServer

  alias Wocky.{GeoUtils, Location, Repo, User}
  alias Wocky.User.{BotEvent, GeoFence, Location}
  alias Wocky.User.CurrentLocation
  alias Wocky.User.Location.Supervisor

  require Logger

  defmodule State do
    @moduledoc false

    defstruct [:user, :subscriptions, :events]
  end

  @spec start_link(User.t()) :: {:ok, pid()}
  def start_link(user), do: GenServer.start_link(__MODULE__, user)

  def get_handler(user) do
    {:ok, pid} =
      Swarm.whereis_or_register_name(
        handler_name(user),
        Supervisor,
        :start_child,
        [user],
        5000
      )

    pid
  end

  def init(user) do
    Logger.debug(fn -> "Swarm initializing worker with user #{user.id}" end)
    subscriptions = User.get_subscriptions(user)
    events = BotEvent.get_last_events(user.id)

    {:ok, %State{user: user, subscriptions: subscriptions, events: events}}
  end

  def handle_call(
        {:set_location, location, current?},
        _from,
        %{user: user, subscriptions: subscriptions, events: events} = state
      ) do
    Logger.debug(fn -> "Swarm set location with user #{user.id}" end)

    with {:ok, loc} = result <- prepare_location(user, location, current?) do
      {:ok, _, new_events} =
        GeoFence.check_for_bot_events(loc, user, subscriptions, events)

      {:reply, result, Map.put(state, :events, new_events)}
    else
      error ->
        {:reply, error, state}
    end
  end

  def handle_call(
        {:set_location_for_bot, location, bot},
        _from,
        %{user: user, events: events} = state
      ) do
    Logger.debug(fn -> "Swarm set location for bot with user #{user.id}" end)

    with {:ok, loc} = result <- prepare_location(user, location, true) do
      {:ok, _, new_events} =
        GeoFence.check_for_bot_event(bot, loc, user, events)

      {:reply, result, Map.put(state, :events, new_events)}
    else
      error ->
        {:reply, error, state}
    end
  end

  # called when a handoff has been initiated due to changes
  # in cluster topology, valid response values are:
  #
  #   - `:restart`, to simply restart the process on the new node
  #   - `{:resume, state}`, to hand off some state to the new process
  #   - `:ignore`, to leave the process running on its current node
  #
  def handle_call({:swarm, :begin_handoff}, _from, user) do
    Logger.debug(fn -> "Swarm handing off state with user #{user.id}" end)
    {:reply, :restart, user}
  end

  # called when a network split is healed and the local process
  # should continue running, but a duplicate process on the other
  # side of the split is handing off its state to us. You can choose
  # to ignore the handoff state, or apply your own conflict resolution
  # strategy
  def handle_cast({:swarm, :resolve_conflict, _state}, state) do
    {:noreply, state}
  end

  # this message is sent when this process should die
  # because it is being moved, use this as an opportunity
  # to clean up
  def handle_info({:swarm, :die}, state), do: {:stop, :shutdown, state}

  defp handler_name(user), do: "location_handler_" <> user.id

  defp prepare_location(user, location, current?) do
    with nloc <- normalize_location(location),
         {:ok, loc} <- maybe_save_location(user, nloc),
         :ok <- maybe_save_current_location(current?, user, nloc) do
      {:ok, loc}
    end
  end

  defp normalize_location(location) do
    {nlat, nlon} = GeoUtils.normalize_lat_lon(location.lat, location.lon)
    captured_at = normalize_captured_at(location)
    %Location{location | lat: nlat, lon: nlon, captured_at: captured_at}
  end

  defp normalize_captured_at(%Location{captured_at: time})
       when not is_nil(time),
       do: time

  defp normalize_captured_at(_), do: DateTime.utc_now()

  defp maybe_save_location(user, location) do
    if should_save_location?(user) do
      save_location(user, location)
    else
      {:ok, location}
    end
  end

  defp should_save_location?(user) do
    GeoFence.save_locations?() || User.hippware?(user)
  end

  def save_location(user, location) do
    user
    |> Ecto.build_assoc(:locations)
    |> Location.changeset(Map.from_struct(location))
    |> Repo.insert()
  end

  defp maybe_save_current_location(false, _user, _location), do: :ok

  defp maybe_save_current_location(true, user, location) do
    if GeoFence.should_process?(location, GeoFence.get_config()) do
      CurrentLocation.set(user, location)
    else
      :ok
    end
  end
end

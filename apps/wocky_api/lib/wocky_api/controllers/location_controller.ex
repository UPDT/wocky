defmodule WockyAPI.LocationController do
  use WockyAPI, :controller

  alias Wocky.User
  alias Wocky.User.Location

  action_fallback WockyAPI.FallbackController

  def create(conn, params) do
    with {:ok, l, device} <- extract_values(params) do
      user = conn.assigns.current_user
      loc = make_location(l, device)

      {:ok, _} = User.set_location(user, loc)

      send_resp(conn, :created, "")
    end
  end

  defp extract_values(params) do
    {
      normalize_location(params["location"]),
      params["device"]
    }
    |> check_required_keys()
  end

  defp normalize_location([location | _]), do: location
  defp normalize_location(location), do: location

  defp check_required_keys({location, device}) do
    if has_required_keys(location, device) do
      {:ok, location, device}
    else
      {:error, :missing_keys}
    end
  end

  defp has_required_keys(%{"coords" => coords}, device) do
    Map.get(coords, "latitude") && Map.get(coords, "longitude") &&
      Map.get(coords, "accuracy") && device
  end

  defp has_required_keys(_, _), do: false

  defp make_location(%{"coords" => c} = l, device) do
    %Location{
      lat: c["latitude"],
      lon: c["longitude"],
      accuracy: c["accuracy"],
      speed: c["speed"],
      heading: c["heading"],
      altitude: c["altitude"],
      altitude_accuracy: c["altitude_accuracy"],
      captured_at: l["timestamp"],
      uuid: l["uuid"],
      odometer: l["odometer"],
      is_moving: l["is_moving"],
      device: device
    }
    |> maybe_add_activity(l["activity"])
    |> maybe_add_battery(l["battery"])
  end

  defp maybe_add_activity(l, %{} = a) do
    %Location{l | activity: a["type"], activity_confidence: a["confidence"]}
  end

  defp maybe_add_activity(l, _), do: l

  defp maybe_add_battery(l, %{} = b) do
    %Location{l | battery_level: b["level"], battery_charging: b["is_charging"]}
  end

  defp maybe_add_battery(l, _), do: l
end

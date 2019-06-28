defmodule WockyAPI.GraphQLHelper do
  @moduledoc """
  Helper functions for Wocky API GraphQL tests
  """

  alias Wocky.Account.User
  alias Wocky.GeoUtils
  alias Wocky.POI.Bot
  alias Wocky.Repo.Timestamp

  def run_query(query, user \\ nil, variables \\ %{}) do
    Absinthe.run!(
      query,
      WockyAPI.Schema,
      variables: variables,
      context: build_context(user)
    )
  end

  defp build_context(%User{} = user), do: %{current_user: user}
  defp build_context(_), do: %{}

  def has_data(result) do
    Map.has_key?(result, :data)
  end

  def has_errors(result) do
    Map.has_key?(result, :errors)
  end

  def error_count(result) do
    result |> Map.get(:errors, []) |> length()
  end

  def error_msg(result, idx \\ 0) do
    error =
      result
      |> Map.get(:errors, [])
      |> Enum.at(idx, %{})

    error[:message]
  end

  def successful?(%{"successful" => successful}), do: successful

  def failure_msg(%{"messages" => [%{"message" => message} | _]}),
    do: message

  def stringify_keys(map) do
    Enum.into(map, %{}, fn {k, v} -> {to_string(k), v} end)
  end

  def bot_create_fields do
    [
      :title,
      :server,
      :lat,
      :lon,
      :radius,
      :description,
      :shortname,
      :geofence
    ]
  end

  def add_bot_lat_lon(%Bot{location: location} = bot) do
    {lat, lon} = GeoUtils.get_lat_lon(location)
    bot |> Map.put(:lat, lat) |> Map.put(:lon, lon)
  end

  def sharing_expiry(days \\ 5) do
    Timestamp.shift(days: days)
    |> DateTime.truncate(:second)
    |> Timestamp.to_string!()
  end
end

defmodule WockyAPI.Controllers.AlertsController do
  use Elixometer
  use WockyAPI, :controller

  alias Plug.Conn
  alias Wocky.Alerts

  action_fallback WockyAPI.Controllers.FallbackController

  @spec create(Conn.t(), Keyword.t()) :: Conn.t() | {:error, any()}
  def create(conn, params) do
    alert = %{
      source: conn.path_params["source"],
      source_id: conn.path_params["source_id"],
      title: params["title"],
      summary: params["summary"],
      link: params["link"],
      expires_at: params["expires_at"],
      data: params["data"] || %{},
      geometry: params["geometry"],
      geometry_source_ids: params["geometry_source_ids"]
    }

    with {:ok, _} <- Alerts.insert_alert(alert) do
      send_resp(conn, :created, "")
    end
  end
end

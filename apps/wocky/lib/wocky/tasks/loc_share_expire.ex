defmodule Wocky.Tasks.LocShareExpire do
  @moduledoc "Clean up expired location shares"

  require Logger

  alias Wocky.User.LocationShare

  def run do
    {:ok, _} = Application.ensure_all_started(:wocky)

    expire_loc_shares()

    :init.stop()
  end

  def expire_loc_shares do
    {time, {count, nil}} = :timer.tc(&LocationShare.clean_expired/0)

    Logger.info("Deleted #{count} expired shares in #{time}ms")
  end
end

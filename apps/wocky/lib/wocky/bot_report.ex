defmodule Wocky.BotReport do
  @moduledoc "Generate a report of active bots and post to Slack"

  import Ecto.Query

  alias Slack.File
  alias Timex.Duration
  alias Wocky.Bot
  alias Wocky.Bot.Item
  alias Wocky.Repo

  @header ~w(
    ID Title Owner Created Updated Address Latitude Longitude
    Visibility Subscribers ImageItems Description
  )

  @spec run :: nil | binary
  def run do
    {:ok, _} = Application.ensure_all_started(:wocky)
    if Confex.get_env(:wocky, :enable_bot_report) do
      days = Confex.get_env(:wocky, :bot_report_days)
      report = generate_report(days)

      server = Confex.get_env(:wocky, :wocky_host)
      channel = Confex.get_env(:wocky, :bot_report_channel)

      :wocky
      |> Confex.get_env(:slack_token)
      |> Slack.client
      |> File.upload(content: report,
                     filename: "weekly_bot_report_#{server}.csv",
                     title: "Weekly Bot Report for #{server}",
                     filetype: "csv",
                     channels: channel)
    end
  end

  @spec generate_report(non_neg_integer) :: binary
  def generate_report(days) do
    {:ok, csv} =
      Repo.transaction fn ->
        days
        |> since()
        |> get_bot_data()
        |> add_header()
        |> Enum.join
      end

    csv
  end

  defp add_header(data) do
    [@header]
    |> CSV.encode
    |> Stream.concat(data)
  end

  defp since(days) do
    Timex.now
    |> Timex.subtract(Duration.from_days(days))
    |> Timex.to_naive_datetime
  end

  defp get_bot_data(since) do
    Bot
    |> where([b], b.created_at > ^since and not b.pending)
    |> Repo.stream
    |> Stream.map(&format_bot/1)
    |> CSV.encode
  end

  defp format_bot(%Bot{} = bot) do
    [
      bot.id,
      word_count(bot.title),
      owner_handle(bot),
      bot.created_at,
      bot.updated_at,
      bot.address,
      Bot.lat(bot),
      Bot.lon(bot),
      vis_string(bot.public),
      Bot.subscriber_count(bot),
      Item.get_image_count(bot),
      word_count(bot.description)
    ]
    |> Enum.map(&to_string/1)
  end

  defp owner_handle(bot), do: Bot.owner(bot).handle

  defp vis_string(true), do: "public"
  defp vis_string(_), do: "private"

  defp word_count(words), do: words |> String.split |> Enum.count
end

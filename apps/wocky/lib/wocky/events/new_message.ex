defmodule Wocky.Events.NewMessage do
  @moduledoc false

  alias Wocky.Account.User

  defstruct [
    :to,
    :from,
    :content,
    :image_url,
    :conversation_id,
    :unread_count
  ]

  @type t :: %__MODULE__{
          to: User.t(),
          from: User.t(),
          content: nil | String.t(),
          image_url: nil | String.t(),
          conversation_id: String.t(),
          unread_count: non_neg_integer()
        }

  use ExConstructor
end

defimpl Wocky.Notifier.Push.Event, for: Wocky.Events.NewMessage do
  import Wocky.Notifier.Push.Utils

  def notify?(_), do: true

  def recipient(%{to: to}), do: to

  def message(%{from: from, content: content}) do
    if blank?(content) do
      get_handle(from) <> " sent you an image"
    else
      "From: #{get_handle(from)}\n#{content}"
    end
  end

  def uri(%{from: from}), do: make_uri(:conversation, from.id)

  def ignore_block?(_event), do: false

  def opts(%{unread_count: unread}) do
    [sound: "default", android_channel_id: "chat", badge: unread]
  end
end

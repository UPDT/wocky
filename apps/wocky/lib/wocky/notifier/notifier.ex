defmodule Wocky.Notifier do
  @moduledoc "Send notifications to the user via several channels"

  @callback notify(struct()) :: :ok

  @known_notifiers [
    {Wocky.Notifier.Push.Event, Wocky.Notifier.Push},
    {Wocky.Notifier.InBand.Event, Wocky.Notifier.InBand},
    {Wocky.Notifier.Mailer.Event, Wocky.Notifier.Mailer}
  ]

  alias Wocky.Block

  def notify(event) do
    for {type, notifier} <- @known_notifiers do
      if type.notify?(event) && deliverable?(event) do
        notifier.notify(event)
      end
    end
  end

  defp deliverable?(%{to: to, from: from}), do: !Block.blocked?(to.id, from.id)
  defp deliverable?(_), do: true
end

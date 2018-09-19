defmodule Wocky.Push.Events do
  @moduledoc false

  alias Wocky.Bot
  alias Wocky.Bot.Item
  alias Wocky.Push.Event
  alias Wocky.User

  defmodule Utils do
    @moduledoc false

    alias Wocky.User

    @doc false
    def blank?(nil), do: true
    def blank?(""), do: true
    def blank?(_), do: false

    @doc false
    def get_handle(obj) do
      case do_get_handle(obj) do
        nil -> "Someone"
        "" -> "Someone"
        handle -> "@" <> handle
      end
    end

    defp do_get_handle(nil), do: nil
    defp do_get_handle(%User{} = user), do: user.handle

    @doc false
    def get_title(obj) do
      case do_get_title(obj) do
        nil -> "Somewhere"
        "" -> "Somewhere"
        title -> title
      end
    end

    defp do_get_title(nil), do: nil
    defp do_get_title(%Bot{} = bot), do: bot.title

    @doc false
    def make_uri(type, id \\ nil, server? \\ true, suffix \\ "") do
      "#{uri_prefix()}://#{type}"
      |> maybe_add_server(server?)
      |> maybe_append(id)
      |> maybe_append(suffix)
    end

    defp maybe_add_server(uri, false), do: uri
    defp maybe_add_server(uri, true), do: uri <> "/" <> server()

    defp maybe_append(uri, nil), do: uri
    defp maybe_append(uri, id), do: uri <> "/" <> id

    defp server do
      Confex.get_env(:wocky, :wocky_host)
    end

    defp uri_prefix do
      Confex.get_env(:wocky, Wocky.Push)[:uri_prefix]
    end
  end

  defmodule BotPerimeterEvent do
    @moduledoc false

    defstruct [:user, :bot, :event]

    @type t :: %__MODULE__{
            user: User.t(),
            bot: Bot.t(),
            event: :enter | :exit
          }

    use ExConstructor
  end

  defimpl Event, for: BotPerimeterEvent do
    import Wocky.Push.Events.Utils

    def message(%BotPerimeterEvent{user: user, bot: bot, event: event}) do
      case event do
        :enter -> "#{get_handle(user)} is at #{get_title(bot)}"
        :exit -> "#{get_handle(user)} left #{get_title(bot)}"
      end
    end

    def uri(%BotPerimeterEvent{bot: bot}),
      do: make_uri(:bot, bot.id, true, "visitors")
  end

  defmodule NewMessageEvent do
    @moduledoc false

    defstruct [:from, :to, :body, :image, :conversation_id]

    @type t :: %__MODULE__{
            from: User.t(),
            to: User.t(),
            body: nil | binary,
            image: nil | binary,
            conversation_id: binary
          }

    use ExConstructor
  end

  defimpl Event, for: NewMessageEvent do
    import Wocky.Push.Events.Utils

    def message(%NewMessageEvent{from: from, body: body}) do
      if blank?(body) do
        get_handle(from) <> " sent you an image!"
      else
        "From: #{get_handle(from)}\n#{body}"
      end
    end

    def uri(%NewMessageEvent{from: from}) do
      make_uri(:conversation, from.id)
    end
  end

  defmodule NewFollowerEvent do
    @moduledoc false

    defstruct [:user, :follower]

    @type t :: %__MODULE__{
            user: User.t(),
            follower: User.t()
          }

    use ExConstructor
  end

  defimpl Event, for: NewFollowerEvent do
    import Wocky.Push.Events.Utils

    def message(%NewFollowerEvent{follower: follower} = _event) do
      get_handle(follower) <> " started following you"
    end

    def uri(%NewFollowerEvent{} = _event) do
      make_uri(:followers, nil, false)
    end
  end

  defmodule BotInviteEvent do
    @moduledoc false

    defstruct [:from, :to, :bot]

    @type t :: %__MODULE__{
            from: User.t(),
            to: User.t(),
            bot: Bot.t()
          }

    use ExConstructor
  end

  defimpl Event, for: BotInviteEvent do
    import Wocky.Push.Events.Utils

    def message(%BotInviteEvent{from: from, bot: bot}) do
      get_handle(from) <> " invited you to follow " <> get_title(bot)
    end

    def uri(%BotInviteEvent{bot: bot}), do: make_uri(:bot, bot.id)
  end

  defmodule BotInvitationAcceptEvent do
    @moduledoc false

    defstruct [:from, :to, :bot]

    @type t :: %__MODULE__{
            from: User.t(),
            to: User.t(),
            bot: Bot.t()
          }

    use ExConstructor
  end

  defimpl Event, for: BotInvitationAcceptEvent do
    import Wocky.Push.Events.Utils

    def message(%BotInvitationAcceptEvent{from: from, bot: bot}) do
      get_handle(from) <> " accepted your invitation to " <> get_title(bot)
    end

    def uri(%BotInvitationAcceptEvent{bot: bot}), do: make_uri(:bot, bot.id)
  end

  defmodule NewBotItemEvent do
    @moduledoc false

    defstruct [:author, :to, :item]

    @type t :: %__MODULE__{
            author: User.t(),
            to: User.t(),
            item: Item.t()
          }

    use ExConstructor
  end

  defimpl Event, for: NewBotItemEvent do
    import Wocky.Push.Events.Utils

    def message(%NewBotItemEvent{author: author, item: item}) do
      get_handle(author) <> " commented on " <> get_title(item.bot)
    end

    def uri(%NewBotItemEvent{item: item}), do: make_uri(:bot, item.bot.id)
  end
end

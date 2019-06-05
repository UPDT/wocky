defmodule Wocky.Messaging.Conversation do
  @moduledoc """
  DB interface module for conversations
  """

  use Wocky.Repo.Schema

  import EctoHomoiconicEnum, only: [defenum: 2]

  alias Wocky.Account.User

  defenum MessageDirection, [
    :incoming,
    :outgoing
  ]

  @foreign_key_type :binary_id
  schema "conversations" do
    field :content, :binary
    field :image_url, :binary
    field :direction, MessageDirection

    belongs_to :user, User
    belongs_to :other_user, User

    timestamps(updated_at: false)
  end

  @type t :: %__MODULE__{
          id: integer,
          user_id: User.id(),
          other_user_id: User.id(),
          content: binary,
          image_url: binary,
          direction: MessageDirection,
          created_at: DateTime.t()
        }
end

defmodule Wocky.User.LocationShare do
  @moduledoc false

  import Ecto.Query

  use Wocky.Repo.Schema

  alias Wocky.{Repo, Roster, User}

  @foreign_key_type :binary_id
  schema "user_location_shares" do
    field :expires_at, :utc_datetime, null: false

    timestamps()

    belongs_to :user, User
    belongs_to :shared_with, User, foreign_key: :shared_with_id
  end

  @type t :: %LocationShare{
          user_id: User.id(),
          shared_with_id: User.id(),
          expires_at: DateTime.t(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @doc false
  def changeset(struct, params) do
    struct
    |> cast(params, [:user_id, :shared_with_id, :expires_at])
    |> validate_required([:user_id, :shared_with_id, :expires_at])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:shared_with_id)
    |> validate_change(:expires_at, fn :expires_at, expiry ->
      if Timex.before?(expiry, Timex.now()) do
        [expires_at: "must be in the future"]
      else
        []
      end
    end)
    |> validate_change(:shared_with_id, fn :shared_with_id, shared_with_id ->
      if Roster.friend?(params[:user_id], shared_with_id) do
        []
      else
        [shared_with_id: "must be a friend"]
      end
    end)
  end

  @spec clean_expired() :: {non_neg_integer(), term()}
  def clean_expired do
    LocationShare
    |> where([l], l.expires_at <= ^DateTime.utc_now())
    |> Repo.delete_all(timeout: :infinity)
  end
end

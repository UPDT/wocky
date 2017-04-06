defmodule Wocky.TROSMetadata do
  @moduledoc """
  DB interface module for TROS metadata (access and ownership info)
  """

  use Wocky.Repo.Model

  alias Wocky.User

  alias __MODULE__, as: TROSMetadata

  @primary_key false
  @foreign_key_type :binary_id
  schema "tros_metadatas" do
    field :id,     :binary_id, primary_key: true
    field :access, :binary

    belongs_to :user, User

    timestamps()
  end

  @type id :: binary
  @type access :: binary

  @type t :: %TROSMetadata{
    id:      id,
    user_id: User.id,
    access:  access
  }

  @spec put(id, User.id, access) :: :ok
  def put(id, user_id, access) do
    %TROSMetadata{id: id, user_id: user_id, access: access}
    |> changeset
    |> Repo.insert!
    :ok
  end

  @spec set_access(id, access) :: :ok
  def set_access(id, access) do
    TROSMetadata
    |> Repo.get!(id)
    |> changeset(%{access: access})
    |> Repo.update
    :ok
  end

  @spec get_user_id(id) :: User.id | nil
  def get_user_id(id) do
    TROSMetadata
    |> with_file(id)
    |> select_user_id
    |> Repo.one
  end

  @spec get_access(id) :: access | nil
  def get_access(id) do
    TROSMetadata
    |> with_file(id)
    |> select_access
    |> Repo.one
  end

  @change_fields [:access]

  defp changeset(struct, params \\ %{}) do
    struct
    |> cast(params, @change_fields)
  end

  defp with_file(query, id) do
    from f in query, where: f.id == ^id
  end

  defp select_user_id(query) do
    from f in query, select: f.user_id
  end

  defp select_access(query) do
    from f in query, select: f.access
  end

end

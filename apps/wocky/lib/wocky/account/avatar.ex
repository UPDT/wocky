defmodule Wocky.Account.Avatar do
  @moduledoc """
  Validation and logic regarding user avatars.
  """

  alias Wocky.Account.User
  alias Wocky.Repo.ID
  alias Wocky.TROS
  alias Wocky.TROS.Metadata

  @type url :: binary
  @type t :: TROS.file_id()

  @spec validate(User.t(), url()) :: {:ok, t()} | {:error, atom()}
  def validate(user, avatar_url) do
    with {:ok, avatar} <- TROS.parse_url(avatar_url),
         :ok <- check_valid_filename(avatar),
         :ok <- check_owner(avatar, user.id) do
      {:ok, avatar}
    end
  end

  defp check_valid_filename(file_id) do
    if ID.valid?(file_id) do
      :ok
    else
      {:error, :invalid_file}
    end
  end

  defp check_owner(id, user_id) do
    case TROS.get_metadata(id) do
      {:ok, %Metadata{user_id: ^user_id}} -> :ok
      {:ok, _} -> {:error, :not_file_owner}
      error -> error
    end
  end

  @spec maybe_delete_existing(url | nil, User.t()) :: :ok

  # For this call, a `nil` in the new position means that the changeset
  # for the user is not changing the avatar, not that it is setting it
  # to be empty. Therefore we take no action in that case:
  def maybe_delete_existing(nil, %User{image_url: _old_avatar}), do: :ok
  def maybe_delete_existing(_new_avatar, %User{image_url: nil}), do: :ok
  def maybe_delete_existing(avatar, %User{image_url: avatar}), do: :ok

  def maybe_delete_existing(_new_avatar, user) do
    case TROS.parse_url(user.image_url) do
      {:ok, file_id} ->
        # TODO Do we really want to ignore this return value?
        _ = TROS.delete(file_id, user)
        :ok

      {:error, _} ->
        :ok
    end
  end
end

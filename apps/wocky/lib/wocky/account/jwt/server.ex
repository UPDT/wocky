defmodule Wocky.Account.JWT.Server do
  @moduledoc """
  Generates and validates JWTs used for uploading user location updates.
  """
  use Guardian,
    otp_app: :wocky,
    issuer: "Wocky",
    verify_issuer: true,
    ttl: {4, :weeks},
    secret_key: {Wocky.Account.JWT.SigningKey, :fetch, [:server]},
    token_verify_module: Wocky.Account.JWT.Verify

  alias Wocky.Account.User
  alias Wocky.Repo

  # This is an overridable function from Guardian that isn't part of
  # the behavior. Any added typespec will be ignored.
  def default_token_type, do: "location"

  @impl true
  def subject_for_token(%User{} = user, _claims) do
    {:ok, user.id}
  end

  def subject_for_token(_resource, _claims) do
    {:error, :unknown_resource}
  end

  @impl true
  def resource_from_claims(%{"sub" => user_id} = _claims) do
    case Repo.get(User, user_id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_claims) do
    {:error, :not_possible}
  end

  @impl true
  def build_claims(claims, _resource, _opts), do: {:ok, claims}
end

defmodule Wocky.UserInvite do
  @moduledoc """
  Module for sending bulk invitations, both SMS (external) and internal
  """

  import Ecto.Query, only: [from: 2]

  alias Wocky.Account
  alias Wocky.Account.User
  alias Wocky.Contacts
  alias Wocky.Contacts
  alias Wocky.PhoneNumber
  alias Wocky.Repo
  alias Wocky.SMS.Messenger
  alias Wocky.UserInvite.DynamicLink
  alias Wocky.UserInvite.InviteCode

  @type result :: map()
  @type results :: [result()]

  @invite_code_expire_days 30

  # ----------------------------------------------------------------------
  # Invite codes

  @spec make_code(User.t(), PhoneNumber.t() | nil, Contacts.share_type()) ::
          Repo.result(String.t())
  def make_code(user, phone_number \\ nil, share_type \\ :disabled) do
    case do_insert_code(user, phone_number, share_type) do
      {:ok, invitation} -> {:ok, invitation.code}
      {:error, _} = error -> error
    end
  end

  defp do_insert_code(user, phone_number, share_type) do
    user
    |> InviteCode.changeset(phone_number, share_type)
    |> Repo.insert()
  end

  @spec get_by_code(String.t(), User.tid()) :: InviteCode.t() | nil
  def get_by_code(code, requestor) do
    code
    |> by_code_query()
    |> Contacts.object_visible_query(requestor)
    |> Repo.one()
  end

  @spec redeem_code(User.t(), String.t(), Contacts.share_type()) :: boolean()
  def redeem_code(redeemer, code, share_type \\ :disabled) do
    invitation = get_by_code(code, redeemer)
    do_redeem_invite_code(redeemer, invitation, share_type)
  end

  defp by_code_query(code) do
    from ic in InviteCode,
      where: ic.code == ^code,
      preload: :user
  end

  defp do_redeem_invite_code(_, nil, _), do: false

  defp do_redeem_invite_code(redeemer, invitation, share_type) do
    do_redeem_invite_code(redeemer, invitation.user, invitation, share_type)
  end

  defp do_redeem_invite_code(%User{id: id}, %User{id: id}, _, _), do: true

  defp do_redeem_invite_code(redeemer, inviter, invitation, share_type) do
    if !code_expired?(invitation) && target_user?(redeemer, invitation) do
      inviter_stype = invitation.share_type

      with {:ok, _} <- Contacts.make_friends(inviter, redeemer, inviter_stype),
           {:ok, _} <- Contacts.make_friends(redeemer, inviter, share_type) do
        true
      else
        {:error, _} ->
          false
      end
    else
      false
    end
  end

  defp code_expired?(invitation) do
    Timex.diff(Timex.now(), invitation.created_at, :days) >
      @invite_code_expire_days
  end

  defp target_user?(%{phone_number: pn}, %{phone_number: pn}), do: true

  defp target_user?(_, _), do: false

  # ----------------------------------------------------------------------
  # SMS invitations

  @spec send(PhoneNumber.t(), Contacts.share_type(), User.t()) :: result()
  def send(number, share_type, user) do
    with {:ok, cc} <- PhoneNumber.country_code(user.phone_number) do
      number
      |> normalise_number(cc)
      |> lookup_user(user)
      |> maybe_invite(user, share_type)
    end
  end

  defp normalise_number(number, country_code) do
    case PhoneNumber.normalise(number, country_code) do
      {:ok, norm} ->
        %{phone_number: number, e164_phone_number: norm}

      {:error, e} ->
        %{
          phone_number: number,
          e164_phone_number: nil,
          result: :could_not_parse_number,
          error: inspect(e)
        }
    end
  end

  defp lookup_user(record, requestor) do
    if record.e164_phone_number do
      case Account.get_by_phone_number([record.e164_phone_number], requestor) do
        [user] ->
          Map.put(record, :user, user)

        [] ->
          record
      end
    else
      record
    end
  end

  defp maybe_invite(%{e164_phone_number: nil} = r, _, _), do: r

  # We found an unblocked user for this number - send an invite
  defp maybe_invite(%{user: user} = r, requestor, share_type)
       when not is_nil(user) do
    send_internal_invitation(r, user, requestor, share_type)
  end

  # We didn't find a user for this number - fire an SMS invitation
  defp maybe_invite(%{e164_phone_number: number} = r, requestor, share_type)
       when not is_nil(number) do
    send_sms_invitation(r, number, requestor, share_type)
  end

  defp send_internal_invitation(r, user, requestor, share_type) do
    result =
      case Contacts.make_friends(requestor, user, share_type) do
        {:ok, :invited} -> :internal_invitation_sent
        {:ok, :friend} -> :already_friends
        {:error, _} -> :self
      end

    Map.put(r, :result, result)
  end

  defp send_sms_invitation(r, number, requestor, share_type) do
    with {:ok, body} <- sms_invitation_body(requestor, number, share_type),
         :ok <- Messenger.send(number, body, requestor) do
      Map.put(r, :result, :external_invitation_sent)
    else
      {:error, e} ->
        r
        |> Map.put(:result, :sms_error)
        |> Map.put(:error, inspect(e))

      {:error, e, code} ->
        r
        |> Map.put(:result, :sms_error)
        |> Map.put(:error, "#{inspect(e)}, #{inspect(code)}")
    end
  end

  defp sms_invitation_body(user, number, share_type) do
    with {:ok, code} <- make_code(user, number, share_type),
         {:ok, link} <- DynamicLink.invitation_link(code) do
      {:ok,
       "@#{user.handle} " <>
         maybe_name(user) <>
         "has invited you to tinyrobot." <> " Please visit #{link} to join."}
    end
  end

  defp maybe_name(user) do
    case String.trim("#{user.name}") do
      "" -> ""
      name -> "(#{name}) "
    end
  end

  @spec send_multi([PhoneNumber.t()], User.t()) :: results()
  def send_multi(numbers, user) do
    with {:ok, cc} <- PhoneNumber.country_code(user.phone_number) do
      numbers
      |> Enum.uniq()
      |> Enum.map(&normalise_number(&1, cc))
      |> lookup_users(user)
      |> Enum.map_reduce(%{}, &maybe_send_invitation(&1, &2, user))
      |> elem(0)
    end
  end

  defp lookup_users(data, requestor) do
    data
    |> Enum.filter(&(&1.e164_phone_number != nil))
    |> Enum.map(& &1.e164_phone_number)
    |> Account.get_by_phone_number(requestor)
    |> Enum.reduce(data, &insert_user/2)
  end

  defp insert_user(user, data),
    do: Enum.map(data, &maybe_add_user_to_record(user, &1))

  defp maybe_add_user_to_record(
         %{phone_number: n} = user,
         %{e164_phone_number: n} = r
       ),
       do: Map.put(r, :user, user)

  defp maybe_add_user_to_record(_, r), do: r

  defp maybe_send_invitation(
         %{e164_phone_number: nil} = r,
         sent_numbers,
         _requestor
       ),
       do: {r, sent_numbers}

  defp maybe_send_invitation(
         %{e164_phone_number: number} = r,
         sent_numbers,
         requestor
       ) do
    case sent_numbers[number] do
      nil ->
        send_invitation(r, sent_numbers, requestor)

      {result, error} ->
        r =
          r
          |> Map.put(:result, result)
          |> Map.put(:error, error)

        {r, sent_numbers}
    end
  end

  # We found an unblocked user for this number - send an invite
  defp send_invitation(%{user: user} = r, sent_numbers, requestor) do
    r = send_internal_invitation(r, user, requestor, :disabled)

    {r, Map.put(sent_numbers, r.e164_phone_number, {r.result, nil})}
  end

  # We didn't find a user for this number - fire an SMS invitation
  defp send_invitation(
         %{e164_phone_number: number} = r,
         sent_numbers,
         requestor
       )
       when not is_nil(number) do
    r = send_sms_invitation(r, number, requestor, :disabled)

    {r, Map.put(sent_numbers, number, {r[:result], r[:error]})}
  end
end

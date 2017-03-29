defmodule Golem.Factory do
  @moduledoc false

  use ExMachina.Ecto, repo: Golem.Repo

  alias Faker.Code
  alias Faker.Internet
  alias Faker.Name
  alias Faker.Phone.EnUs, as: Phone
  alias Golem.ID
  alias Golem.User

  def phone_number do
    "+1555#{Phone.area_code}#{Phone.extension}"
  end

  def user_factory do
    user_id = ID.new
    %User{
      id: user_id,
      username: user_id,
      server: "localhost",
      external_id: Code.isbn13,
      handle: Internet.user_name,
      # avatar: :tros.make_url(:wocky_app.server, ID.new),
      first_name: Name.first_name,
      last_name: Name.last_name,
      phone_number: phone_number(),
      email: Internet.email
    }
  end

  # def bot_factory do
  #   %Bot{
  #     id: ID.new,
  #     server: :wocky_app.server,
  #     title: Company.name,
  #     shortname: Company.buzzword,
  #     owner: :jid.to_binary(:jid.make(ID.new, :wocky_app.server, <<>>)),
  #     description: Lorem.paragraph(%Range{first: 1, last: 2}),
  #     image: :tros.make_url(:wocky_app.server, ID.new),
  #     type: "test",
  #     address: Address.street_address,
  #     lat: Address.latitude,
  #     lon: Address.longitude,
  #     radius: :rand.uniform(100) * 1000,
  #     visibility: 1,
  #     alerts: 1,
  #     updated: :wocky_db.now_to_timestamp(:erlang.timestamp),
  #     follow_me: false
  #   }
  # end

  # def location_factory do
  #   %Location{
  #     lat: Address.latitude,
  #     lon: Address.longitude,
  #     accuracy: 10
  #   }
  # end
end
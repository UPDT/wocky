defmodule Wocky.Repo.Migrations.AddSystemUserRoles do
  use Wocky.Repo.Migration

  def change do
    # noop since we no longer use homestream prepopulation
  end

  # import Ecto.Query

  # alias Wocky.Repo
  # alias Wocky.User

  # @handle "__new_user_hs_archive__"

  # def up do
  #   id = get_id()
  #   User.add_role(id, User.no_index_role)
  #   User.add_role(id, User.system_role)
  # end

  # def down do
  #   id = get_id()
  #   User.remove_role(id, User.no_index_role)
  #   User.remove_role(id, User.system_role)
  # end

  # defp get_id do
  #   User
  #   |> where([u], u.handle == ^@handle)
  #   |> select([u], u.id)
  #   |> Repo.one!
  # end
end

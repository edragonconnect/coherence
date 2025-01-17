defmodule Coherence.PasswordController do
  @moduledoc """
  Handle password recovery actions.

  Controller that handles the recover password feature.

  Actions:

  * new - render the recover password form
  * create - verify user's email address, generate a token, and send the email
  * edit - render the reset password form
  * update - verify password, password confirmation, and update the database
  """
  use Coherence.Web, :controller
  use Timex

  alias Coherence.ControllerHelpers, as: Helpers
  alias Coherence.{TrackableService, Messages, Schemas}

  require Logger

  plug :layout_view, view: Coherence.PasswordView, caller: __MODULE__
  plug :redirect_logged_in when action in [:new, :create, :edit, :update]

  @type schema :: Ecto.Schema.t
  @type conn :: Plug.Conn.t
  @type params :: Map.t

  @doc """
  Render the recover password form.
  """
  @spec new(conn, params) :: conn
  def new(conn, _params) do
    user_schema = Config.user_schema
    cs = Helpers.changeset :password, user_schema, user_schema.__struct__
    conn
    |> render(:new, [email: "", changeset: cs])
  end

  @doc """
  Create the recovery token and send the email
  """
  @spec create(conn, params) :: conn
  def create(conn, %{"password" => password_params} = params) do
    user_schema = Config.user_schema
    email = password_params["email"]
    user =
      user_schema
      |> where([u], u.email == ^email)
      |> Config.repo.one

    case user do
      nil ->
        changeset = Helpers.changeset :password, user_schema, user_schema.__struct__
        conn
        |> put_flash(:error, Messages.backend().could_not_find_that_email_address())
        |> render("new.html", changeset: changeset)
      user ->
        token = random_string 48
        url = router_helpers().password_url(conn, :edit, token)
        Logger.debug "reset email url: #{inspect url}"
        dt = Ecto.DateTime.utc
        cs = Helpers.changeset(:password, user_schema, user,
          %{reset_password_token: token, reset_password_sent_at: dt})
        Config.repo.update! cs

        if Config.mailer?() do
          send_user_email :password, user, url
          put_flash(conn, :info, Messages.backend().reset_email_sent())
        else
          put_flash(conn, :error, Messages.backend().mailer_required())
        end
        |> redirect_to(:password_create, params)
    end
  end

  @doc """
  Render the password and password confirmation form.
  """
  @spec edit(conn, params) :: conn
  def edit(conn, params) do
    user_schema = Config.user_schema
    token = params["id"]
    user =
      user_schema
      |> where([u], u.reset_password_token == ^token)
      |> Config.repo.one
    case user do
      nil ->
        conn
        |> put_flash(:error, Messages.backend().invalid_reset_token())
        |> redirect(to: logged_out_url(conn))
      user ->
        if expired? user.reset_password_sent_at, days: Config.reset_token_expire_days do
          :password
          |> Helpers.changeset(user_schema, user, clear_password_params())
          |> Schemas.update

          conn
          |> put_flash(:error, Messages.backend().password_reset_token_expired())
          |> redirect(to: logged_out_url(conn))
        else
          changeset = Helpers.changeset(:password, user_schema, user)
          conn
          |> render("edit.html", changeset: changeset)
        end
    end
  end

  @doc """
  Verify the passwords and update the database
  """
  @spec update(conn, params) :: conn
  def update(conn, %{"password" => password_params} = params) do
    user_schema = Config.user_schema
    token = password_params["reset_password_token"]

    case Schemas.get_by_user reset_password_token: token do
      nil ->
        conn
        |> put_flash(:error, Messages.backend().invalid_reset_token())
        |> redirect(to: logged_out_url(conn))
      user ->
        if expired? user.reset_password_sent_at, days: Config.reset_token_expire_days do
          :password
          |> Helpers.changeset(user_schema, user, clear_password_params())
          |> Schemas.update

          conn
          |> put_flash(:error, Messages.backend().password_reset_token_expired())
          |> redirect(to: logged_out_url(conn))
        else
          params = password_params
          |> clear_password_params

          :password
          |> Helpers.changeset(user_schema, user, params)
          |> Schemas.update
          |> case do
            {:ok, user} ->
              conn
              |> TrackableService.track_password_reset(user, user_schema.trackable_table?)
              |> put_flash(:info, Messages.backend().password_updated_successfully())
              |> redirect_to(:password_update, params)
            {:error, changeset} ->
              render(conn, "edit.html", changeset: changeset)
          end
        end
    end
  end

  defp clear_password_params(params \\ %{}) do
    params
    |> Map.put("reset_password_token", nil)
    |> Map.put("reset_password_sent_at", nil)
  end
end

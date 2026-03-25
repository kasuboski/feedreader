defmodule Feedreader.Accounts.Emails do
  @moduledoc false

  import Swoosh.Email

  def deliver_magic_link(user_or_email, token) do
    email =
      new()
      |> to(user_or_email)
      |> from({"Feedreader", "noreply@feedreader.local"})
      |> subject("Your Magic Link")
      |> text_body("Your magic link token is: #{token}")

    case Feedreader.Mailer.deliver(email) do
      {:ok, _} -> {:ok, "Magic link sent"}
      {:error, reason} -> {:error, reason}
    end
  end
end

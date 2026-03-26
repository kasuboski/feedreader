defmodule Feedreader.Secrets do
  @moduledoc false
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Feedreader.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:feedreader, :token_signing_secret)
  end
end

defmodule Feedreader.Accounts do
  @moduledoc false
  use Ash.Domain, otp_app: :feedreader, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Feedreader.Accounts.Token
    resource Feedreader.Accounts.User
  end
end

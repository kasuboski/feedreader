defmodule Feedreader.Accounts do
  use Ash.Domain, otp_app: :feedreader, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Feedreader.Accounts.Token
    resource Feedreader.Accounts.User
  end
end

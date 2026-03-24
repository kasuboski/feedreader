defmodule Feedreader.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FeedreaderWeb.Telemetry,
      Feedreader.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:feedreader, :ecto_repos), skip: skip_migrations?()},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:feedreader, :ash_domains),
         Application.fetch_env!(:feedreader, Oban)
       )},
      # Start a worker by calling: Feedreader.Worker.start_link(arg)
      # {Feedreader.Worker, arg},
      # Start to serve requests, typically the last entry
      {DNSCluster, query: Application.get_env(:feedreader, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Feedreader.PubSub},
      FeedreaderWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :feedreader]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Feedreader.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FeedreaderWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations? do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end

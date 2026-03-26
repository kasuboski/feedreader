defmodule FeedreaderWeb.PageController do
  use FeedreaderWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

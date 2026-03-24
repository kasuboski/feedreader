defmodule FeedReader.Workers.Scheduler do
  use Oban.Worker,
    queue: :scheduler,
    max_attempts: 1

  alias FeedReader.Core

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    feeds = Core.list_feeds!()

    for feed <- feeds do
      %{feed_id: feed.id}
      |> FeedReader.Workers.FetchFeed.new()
      |> Oban.insert!()
    end

    :ok
  end
end

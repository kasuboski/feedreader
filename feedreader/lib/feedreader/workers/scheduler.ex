defmodule FeedReader.Workers.Scheduler do
  use Oban.Worker,
    queue: :scheduler,
    max_attempts: 1

  alias FeedReader.Core

  @fetch_interval_minutes 10

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    feeds = Core.list_feeds!()

    now = DateTime.utc_now()

    for feed <- feeds do
      should_fetch? =
        is_nil(feed.last_fetched_at) ||
          DateTime.diff(now, feed.last_fetched_at, :minute) >= @fetch_interval_minutes

      if should_fetch? do
        # Stagger on startup: random delay 0-5 minutes
        # This prevents all feeds from being scheduled at once on app start
        delay_minutes = :rand.uniform(5)

        %{feed_id: feed.id}
        |> FeedReader.Workers.FetchFeed.new(schedule_in: delay_minutes * 60)
        |> Oban.insert!()
      end
    end

    :ok
  end
end

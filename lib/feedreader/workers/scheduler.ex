defmodule FeedReader.Workers.Scheduler do
  @moduledoc "Cron-scheduled Oban worker that enqueues fetch jobs for due feeds."
  use Oban.Worker,
    queue: :scheduler,
    max_attempts: 1

  alias FeedReader.Core
  require Logger

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
        # Stagger on startup: random delay 1-5 minutes
        # This prevents all feeds from being scheduled at once on app start
        delay_minutes = :rand.uniform(5)

        result =
          %{feed_id: feed.id}
          |> FeedReader.Workers.FetchFeed.new(schedule_in: delay_minutes * 60)
          |> Oban.insert()

        case result do
          {:ok, _job} ->
            :ok

          {:error, reason} ->
            Logger.error("Failed to schedule FetchFeed for feed #{feed.id}: #{inspect(reason)}")
        end
      end
    end

    :ok
  end
end

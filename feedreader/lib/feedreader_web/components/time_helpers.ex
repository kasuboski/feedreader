defmodule FeedreaderWeb.TimeHelpers do
  @moduledoc """
  Time formatting helpers for displaying dates in human-readable format.
  """

  def humanize_date(nil), do: nil

  def humanize_date(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, dt, :second)

    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 172_800 -> "yesterday"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86_400)}d ago"
      diff_seconds < 2_592_000 -> "#{div(diff_seconds, 604_800)}w ago"
      true -> Calendar.strftime(dt, "%b %d, %Y")
    end
  end
end

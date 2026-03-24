defmodule FeedreaderWeb.EntryLive.Index do
  use FeedreaderWeb, :live_view

  alias FeedReader.Core

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(_params, url, socket) do
    action = socket.assigns.live_action
    uri = URI.parse(url)

    {entries, offset, has_more} = fetch_entries(action, limit: 50, offset: 0)

    {:noreply,
     socket
     |> assign(:action, action)
     |> assign(:current_path, uri.path)
     |> assign(:entries, entries)
     |> assign(:entry_count, length(entries))
     |> assign(:offset, offset)
     |> assign(:has_more, has_more)
     |> stream(:entries, entries, reset: true)}
  end

  defp fetch_entries(:unread, page_options) do
    case Core.list_unread(page: page_options) do
      {:ok, result} -> {result.results, result.offset, result.more?}
      _ -> {[], 0, false}
    end
  end

  defp fetch_entries(:starred, page_options) do
    case Core.list_starred(page: page_options) do
      {:ok, result} -> {result.results, result.offset, result.more?}
      _ -> {[], 0, false}
    end
  end

  defp fetch_entries(:history, page_options) do
    case Core.list_history(page: page_options) do
      {:ok, result} -> {result.results, result.offset, result.more?}
      _ -> {[], 0, false}
    end
  end

  defp fetch_entries(_, _) do
    {[], 0, false}
  end

  defp feed_display_name(nil), do: nil

  defp feed_display_name(%{name: nil, feed_url: url, site_url: site_url}),
    do: fallback_url(site_url) || root_domain(url)

  defp feed_display_name(%{name: "", feed_url: url, site_url: site_url}),
    do: fallback_url(site_url) || root_domain(url)

  defp feed_display_name(%{name: name}) when name != nil and name != "", do: name

  defp fallback_url(nil), do: nil
  defp fallback_url(url), do: root_domain(url)

  defp root_domain(nil), do: nil

  defp root_domain(url) do
    case URI.parse(url) do
      %{host: host} when host != nil ->
        parts = String.split(host, ".")

        case Enum.reverse(parts) do
          [_, second | _] -> "#{second}.#{List.first(parts)}"
          [single] -> single
          _ -> host
        end

      _ ->
        nil
    end
  end

  def humanize_date(nil), do: nil

  def humanize_date(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, dt, :second)

    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 172_800 -> "yesterday"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)}d ago"
      diff_seconds < 2_592_000 -> "#{div(diff_seconds, 604_800)}w ago"
      true -> Calendar.strftime(dt, "%b %d, %Y")
    end
  end

  @impl true
  def handle_event("toggle_star", %{"id" => id}, socket) do
    action = socket.assigns[:action]
    entry = Core.get_entry!(id)
    {:ok, updated} = Core.toggle_starred(entry)

    socket =
      cond do
        action == :starred && not updated.is_starred ->
          new_count = socket.assigns.entry_count - 1

          socket
          |> stream_delete(:entries, updated)
          |> assign(:entry_count, new_count)
          |> assign(:has_more, socket.assigns.has_more && new_count >= 50)

        action == :starred && updated.is_starred ->
          socket
          |> assign(:entry_count, socket.assigns.entry_count + 1)
          |> stream_insert(:entries, updated, at: 0)

        true ->
          stream_insert(socket, :entries, updated)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_read", %{"id" => id}, socket) do
    action = socket.assigns[:action]
    entry = Core.get_entry!(id)
    {:ok, updated} = Core.toggle_read(entry)

    socket =
      cond do
        action == :unread && updated.is_read ->
          new_count = socket.assigns.entry_count - 1

          socket
          |> stream_delete(:entries, updated)
          |> assign(:entry_count, new_count)
          |> assign(:has_more, socket.assigns.has_more && new_count >= 50)

        action == :unread && not updated.is_read ->
          socket
          |> assign(:entry_count, socket.assigns.entry_count + 1)
          |> stream_insert(:entries, updated, at: 0)

        true ->
          stream_insert(socket, :entries, updated)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    action = socket.assigns[:action]
    current_offset = socket.assigns[:offset] || 0

    new_offset = current_offset + 50

    page_options = [limit: 50, offset: new_offset]

    {new_entries, offset, has_more} = fetch_entries(action, page_options)

    {:noreply,
     socket
     |> assign(:offset, offset)
     |> assign(:has_more, has_more)
     |> assign(:entry_count, socket.assigns.entry_count + length(new_entries))
     |> stream(:entries, new_entries, at: -1)}
  end
end

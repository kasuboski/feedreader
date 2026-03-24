defmodule FeedreaderWeb.EntryLive.Index do
  use FeedreaderWeb, :live_view

  alias FeedReader.Core

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, url, socket) do
    action = socket.assigns.live_action
    uri = URI.parse(url)

    entries = fetch_entries(action, params)

    {:noreply,
     socket
     |> assign(:action, action)
     |> assign(:current_path, uri.path)
     |> assign(:entries, entries)
     |> stream(:entries, entries, reset: true)}
  end

  defp fetch_entries(:unread, _params) do
    case Core.list_unread(page: [limit: 50]) do
      {:ok, result} -> result.results
      _ -> []
    end
  end

  defp fetch_entries(:starred, _params) do
    case Core.list_starred(page: [limit: 50]) do
      {:ok, result} -> result.results
      _ -> []
    end
  end

  defp fetch_entries(:history, _params) do
    case Core.list_history(page: [limit: 50]) do
      {:ok, result} -> result.results
      _ -> []
    end
  end

  defp fetch_entries(_, _params) do
    []
  end

  @impl true
  def handle_event("toggle_star", %{"id" => id}, socket) do
    entry = Core.get_entry!(id)
    {:ok, updated} = Core.toggle_starred(entry)

    {:noreply, stream_insert(socket, :entries, updated)}
  end

  @impl true
  def handle_event("toggle_read", %{"id" => id}, socket) do
    entry = Core.get_entry!(id)
    {:ok, updated} = Core.toggle_read(entry)

    {:noreply, stream_insert(socket, :entries, updated)}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    {:noreply, socket}
  end
end

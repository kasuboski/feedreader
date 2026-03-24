defmodule FeedreaderWeb.FeedLive.Index do
  use FeedreaderWeb, :live_view

  alias FeedReader.Core

  @impl true
  def mount(_params, _session, socket) do
    feeds = Core.list_feeds!()

    {:ok,
     socket
     |> assign(:feeds, feeds)
     |> assign(:form, to_form(%{}))
     |> assign(:current_path, "/feeds")}
  end

  @impl true
  def handle_params(_params, url, socket) do
    uri = URI.parse(url)

    {:noreply,
     socket
     |> assign(:current_path, uri.path)}
  end

  @impl true
  def handle_event("add_feed", %{"feed" => feed_params}, socket) do
    case Core.add_feed(feed_params) do
      {:ok, _feed} ->
        feeds = Core.list_feeds!()

        {:noreply,
         socket
         |> assign(:feeds, feeds)
         |> put_flash(:info, "Feed added successfully")}

      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, "Failed to add feed")}
    end
  end

  @impl true
  def handle_event("import_opml", %{"opml" => %{"file" => upload}}, socket) do
    file_content =
      case upload do
        %{path: path} -> File.read!(path)
        _ -> nil
      end

    if file_content do
      {success_count, _error_count} = Core.import_opml(file_content)

      feeds = Core.list_feeds!()

      {:noreply,
       socket
       |> assign(:feeds, feeds)
       |> put_flash(:info, "Imported #{success_count} feeds")}
    else
      {:noreply, socket |> put_flash(:error, "Failed to read OPML file")}
    end
  end

  @impl true
  def handle_event("delete_feed", %{"id" => id}, socket) do
    feed = Core.get_feed!(id)
    Core.delete_feed!(feed)

    feeds = Core.list_feeds!()

    {:noreply,
     socket
     |> assign(:feeds, feeds)
     |> put_flash(:info, "Feed deleted")}
  end
end

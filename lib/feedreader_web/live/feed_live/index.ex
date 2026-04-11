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
     |> assign(:current_path, "/feeds")
     |> allow_upload(:opml, accept: ~w(.opml text/xml application/xml), max_entries: 1)}
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
  def handle_event("validate_opml", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("import_opml", _params, socket) do
    file_entries =
      consume_uploaded_entries(socket, :opml, fn %{path: tmp_path}, _entry ->
        {:ok, File.read!(tmp_path)}
      end)

    case file_entries do
      [file_content] ->
        {success_count, _error_count} = Core.import_opml(file_content)
        feeds = Core.list_feeds!()

        {:noreply,
         socket
         |> assign(:feeds, feeds)
         |> put_flash(:info, "Imported #{success_count} feeds")}

      [] ->
        {:noreply, put_flash(socket, :error, "No file uploaded")}
    end
  end

  @impl true
  def handle_event("delete_feed", %{"id" => id}, socket) do
    case Core.get_feed(id) do
      {:ok, feed} ->
        result = Core.delete_feed(feed)
        require Logger
        Logger.info("delete_feed result: #{inspect(result)}")

        case result do
          :ok ->
            feeds = Core.list_feeds!()

            {:noreply,
             socket
             |> assign(:feeds, feeds)
             |> put_flash(:info, "Feed deleted")}

          {:error, error} ->
            Logger.error("Failed to delete feed: #{inspect(error)}")
            {:noreply, put_flash(socket, :error, "Unable to delete feed")}

          other ->
            Logger.error("Unexpected delete_feed result: #{inspect(other)}")
            {:noreply, put_flash(socket, :error, "Unable to delete feed")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Feed not found")}
    end
  end
end

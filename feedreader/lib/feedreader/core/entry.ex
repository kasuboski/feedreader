defmodule FeedReader.Core.Entry do
  @moduledoc "Ash resource representing a single feed entry/article."
  use Ash.Resource,
    domain: FeedReader.Core,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "entries"
    repo Feedreader.Repo
  end

  actions do
    defaults [:destroy]

    read :read do
      prepare build(load: [:feed])
    end

    read :unread do
      filter expr(is_read == false)
      prepare build(sort: [published_at: :asc], load: [:feed])
      pagination keyset?: true, default_limit: 50
    end

    read :starred do
      filter expr(is_starred == true)
      prepare build(sort: [published_at: :asc], load: [:feed])
      pagination keyset?: true, default_limit: 50
    end

    read :history do
      prepare build(sort: [published_at: :desc], load: [:feed])
      pagination keyset?: true, default_limit: 50
    end

    update :update do
      accept [:is_read, :is_starred]
    end

    update :toggle_read do
      accept []
      require_atomic? false

      change fn changeset, _ ->
        current_value = Ash.Changeset.get_attribute(changeset, :is_read) || false
        Ash.Changeset.change_attribute(changeset, :is_read, not current_value)
      end
    end

    update :toggle_starred do
      accept []
      require_atomic? false

      change fn changeset, _ ->
        current_value = Ash.Changeset.get_attribute(changeset, :is_starred) || false
        Ash.Changeset.change_attribute(changeset, :is_starred, not current_value)
      end
    end

    create :upsert_from_feed do
      accept [
        :external_id,
        :title,
        :content_link,
        :comments_link,
        :published_at,
        :feed_id
      ]

      upsert? true
      upsert_identity :unique_entry_per_feed
    end
  end

  attributes do
    uuid_primary_key :id

    create_timestamp :created_at

    attribute :external_id, :string do
      allow_nil? false
    end

    attribute :title, :string do
      allow_nil? true
    end

    attribute :content_link, :string do
      allow_nil? true
    end

    attribute :comments_link, :string do
      allow_nil? true
    end

    attribute :published_at, :utc_datetime

    attribute :is_read, :boolean do
      default false
      allow_nil? false
    end

    attribute :is_starred, :boolean do
      default false
      allow_nil? false
    end
  end

  relationships do
    belongs_to :feed, FeedReader.Core.Feed do
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :unique_entry_per_feed, [:feed_id, :external_id]
  end
end

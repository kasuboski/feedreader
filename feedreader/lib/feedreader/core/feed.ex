defmodule FeedReader.Core.Feed do
  use Ash.Resource,
    domain: FeedReader.Core,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "feeds"
    repo Feedreader.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :add do
      accept [:name, :site_url, :feed_url, :category]
    end

    update :log_fetch_success do
      accept []

      change set_attribute(:last_fetched_at, DateTime.utc_now())
      change set_attribute(:fetch_error, nil)
    end

    update :log_fetch_error do
      accept [:fetch_error]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? true
    end

    attribute :site_url, :string do
      allow_nil? true
    end

    attribute :feed_url, :string do
      allow_nil? false
    end

    attribute :category, :string do
      default "Uncategorized"
    end

    attribute :last_fetched_at, :utc_datetime

    attribute :fetch_error, :string
  end

  relationships do
    has_many :entries, FeedReader.Core.Entry do
      destination_attribute :feed_id
    end
  end

  identities do
    identity :unique_feed_url, [:feed_url]
  end
end

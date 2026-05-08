defmodule HnTelegramDigest.HackerNews.FeedItem do
  @moduledoc """
  A normalized item from the Hacker News RSS feed.

  The struct keeps RSS parsing details out of workflow code. Workflow steps can
  call `to_workflow_map/1` when they need JSON-friendly transport data.
  """

  @enforce_keys [:id, :title, :url]
  defstruct [:id, :title, :url, :comments_url, :published_at]

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          url: String.t(),
          comments_url: String.t() | nil,
          published_at: DateTime.t() | nil
        }

  @type workflow_map :: %{
          required(:id) => String.t(),
          required(:title) => String.t(),
          required(:url) => String.t(),
          required(:comments_url) => String.t() | nil,
          required(:published_at) => String.t() | nil
        }

  @doc """
  Converts a feed item into a workflow-safe map.
  """
  @spec to_workflow_map(t()) :: workflow_map()
  def to_workflow_map(%__MODULE__{} = item) do
    %{
      id: item.id,
      title: item.title,
      url: item.url,
      comments_url: item.comments_url,
      published_at: format_datetime(item.published_at)
    }
  end

  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_datetime(nil), do: nil
end

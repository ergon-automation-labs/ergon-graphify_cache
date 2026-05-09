defmodule BotArmyGraphifyCache.Handlers.GraphQueryHandler do
  @moduledoc """
  Handles graph queries by loading and returning cached knowledge graphs.
  """

  require Logger

  @cache_pattern ".graphify-cache/graph.json"

  def handle_query(query) do
    case query do
      %{"repo_path" => repo_path} when is_binary(repo_path) ->
        load_graph(repo_path)

      %{"repo_path" => nil} ->
        %{"error" => "missing_repo_path"}

      _ ->
        %{"error" => "invalid_query"}
    end
  end

  defp load_graph(repo_path) do
    cache_file = Path.join(repo_path, @cache_pattern)

    case File.read(cache_file) do
      {:ok, content} ->
        try do
          graph = Jason.decode!(content)

          %{
            "repo_path" => repo_path,
            "cached_at" =>
              File.stat!(cache_file).mtime
              |> DateTime.from_unix(:millisecond)
              |> elem(1)
              |> DateTime.to_iso8601(),
            "graph" => graph
          }
        rescue
          _ ->
            %{"error" => "invalid_graph_format", "repo_path" => repo_path}
        end

      {:error, :enoent} ->
        %{"error" => "graph_not_found", "repo_path" => repo_path}

      {:error, reason} ->
        %{"error" => "read_failed", "repo_path" => repo_path, "reason" => inspect(reason)}
    end
  end
end

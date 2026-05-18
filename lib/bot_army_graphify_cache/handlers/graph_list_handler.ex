defmodule BotArmyGraphifyCache.Handlers.GraphListHandler do
  @moduledoc """
  Lists all available cached knowledge graphs by scanning for .graphify-cache/graph.json files.
  """

  require Logger

  @cache_pattern ".graphify-cache/graph.json"

  def handle_list(query) do
    case query do
      %{"search_paths" => paths} when is_list(paths) ->
        graphs = Enum.flat_map(paths, &find_graphs/1)
        %{"graphs" => graphs, "count" => length(graphs)}

      _ ->
        # Default: search common locations
        common_paths = [
          "/Users/abby/code/elixir_bots",
          "/Users/abby/code/surfaces",
          "/Users/abby/code"
        ]

        graphs = Enum.flat_map(common_paths, &find_graphs/1)
        %{"graphs" => graphs, "count" => length(graphs)}
    end
  end

  defp find_graphs(base_path) do
    case File.ls(base_path) do
      {:ok, entries} ->
        entries
        |> Enum.map(&Path.join(base_path, &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.filter(&has_graph_cache?/1)
        |> Enum.map(&graph_info/1)

      {:error, _} ->
        []
    end
  end

  defp has_graph_cache?(repo_path) do
    cache_file = Path.join(repo_path, @cache_pattern)
    File.exists?(cache_file)
  end

  defp graph_info(repo_path) do
    cache_file = Path.join(repo_path, @cache_pattern)

    case File.stat(cache_file) do
      {:ok, stat} ->
        %{
          "repo_path" => repo_path,
          "size" => stat.size,
          "cached_at" => format_mtime(stat.mtime)
        }

      {:error, _} ->
        %{"repo_path" => repo_path, "size" => 0, "cached_at" => "unknown"}
    end
  end

  defp format_mtime({{year, month, day}, {hour, minute, second}}) do
    "#{year}-#{pad(month)}-#{pad(day)}T#{pad(hour)}:#{pad(minute)}:#{pad(second)}Z"
  end

  defp format_mtime(_), do: "unknown"

  defp pad(n) do
    n |> Integer.to_string() |> String.pad_leading(2, "0")
  end
end

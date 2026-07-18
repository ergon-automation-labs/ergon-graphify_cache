defmodule BotArmyGraphifyCache.Handlers.GraphStatsHandler do
  @moduledoc """
  Returns statistics about a cached knowledge graph.
  """

  require Logger

  @cache_pattern ".graphify-cache/graph.json"

  def handle_stats(query) do
    case query do
      %{"repo_path" => repo_path} when is_binary(repo_path) ->
        get_stats(repo_path)

      _ ->
        %{"error" => "invalid_query"}
    end
  end

  defp get_stats(repo_path) do
    cache_file = Path.join(repo_path, @cache_pattern)

    case File.read(cache_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, graph} ->
            %{
              "repo_path" => repo_path,
              "stats" => compute_stats(graph),
              "cached_at" => format_mtime(cache_file),
              "size" => byte_size(content)
            }

          {:error, _} ->
            %{"error" => "invalid_graph_format", "repo_path" => repo_path}
        end

      {:error, :enoent} ->
        %{"error" => "graph_not_found", "repo_path" => repo_path}

      {:error, reason} ->
        %{"error" => "read_failed", "repo_path" => repo_path, "reason" => inspect(reason)}
    end
  end

  defp compute_stats(graph) when is_map(graph) do
    %{
      "total_keys" => map_size(graph),
      "modules" => count_modules(graph),
      "functions" => count_functions(graph),
      "complexity" => estimate_complexity(graph)
    }
  end

  defp compute_stats(_), do: %{"error" => "invalid_graph_structure"}

  defp count_modules(graph) do
    graph
    |> Map.keys()
    |> Enum.count(&module_key?/1)
  end

  defp count_functions(graph) do
    graph
    |> Map.values()
    |> Enum.map(&extract_functions/1)
    |> Enum.sum()
  end

  defp module_key?(key) when is_binary(key) do
    String.contains?(key, ".")
  end

  defp module_key?(_), do: false

  defp extract_functions(value) when is_map(value) do
    case Map.get(value, "functions") do
      list when is_list(list) -> length(list)
      _ -> 0
    end
  end

  defp extract_functions(_), do: 0

  defp estimate_complexity(graph) do
    total_items = map_size(graph)

    cond do
      total_items < 10 -> "simple"
      total_items < 50 -> "low"
      total_items < 200 -> "medium"
      total_items < 500 -> "high"
      true -> "very_high"
    end
  end

  defp format_mtime(file_path) do
    case File.stat(file_path) do
      {:ok, stat} ->
        case stat.mtime do
          {{year, month, day}, {hour, minute, second}} ->
            "#{year}-#{pad(month)}-#{pad(day)}T#{pad(hour)}:#{pad(minute)}:#{pad(second)}Z"

          _ ->
            "unknown"
        end

      {:error, _} ->
        "unknown"
    end
  end

  defp pad(n) do
    n |> Integer.to_string() |> String.pad_leading(2, "0")
  end
end

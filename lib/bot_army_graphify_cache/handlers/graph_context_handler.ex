defmodule BotArmyGraphifyCache.Handlers.GraphContextHandler do
  @moduledoc """
  Returns context around a specific symbol or file in the cached knowledge graph.
  """

  require Logger

  @cache_pattern ".graphify-cache/graph.json"

  def handle_context(query) do
    case query do
      %{"repo_path" => repo_path, "symbol" => symbol}
      when is_binary(repo_path) and is_binary(symbol) ->
        depth = Map.get(query, "depth", 2)
        get_context(repo_path, symbol, depth)

      _ ->
        %{"error" => "invalid_query"}
    end
  end

  defp get_context(repo_path, symbol, depth) do
    cache_file = Path.join(repo_path, @cache_pattern)

    case File.read(cache_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, graph} ->
            context = find_context(graph, symbol, depth)

            %{
              "repo_path" => repo_path,
              "symbol" => symbol,
              "depth" => depth,
              "context" => context,
              "found" => context != nil
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

  defp find_context(graph, symbol, depth) do
    # Find exact match first
    case Map.get(graph, symbol) do
      nil ->
        # Try partial match
        case find_partial_match(graph, symbol) do
          nil -> nil
          {name, data} -> build_context(graph, name, data, depth)
        end

      data ->
        build_context(graph, symbol, data, depth)
    end
  end

  defp find_partial_match(graph, symbol) do
    graph
    |> Enum.find(fn {key, _} ->
      String.contains?(key, symbol) or String.contains?(symbol, key)
    end)
  end

  defp build_context(graph, symbol, data, depth) when depth > 0 do
    %{
      "symbol" => symbol,
      "type" => get_type(data),
      "definition" => extract_definition(data),
      "related" => find_related(graph, symbol, depth - 1)
    }
  end

  defp build_context(_, symbol, data, _) do
    %{
      "symbol" => symbol,
      "type" => get_type(data),
      "definition" => extract_definition(data)
    }
  end

  defp get_type(value) when is_map(value) do
    cond do
      Map.has_key?(value, "functions") -> "module"
      Map.has_key?(value, "module") -> "function"
      Map.has_key?(value, "file") -> "file"
      true -> "unknown"
    end
  end

  defp get_type(_), do: "unknown"

  defp extract_definition(value) when is_map(value) do
    value
    |> Map.take(["doc", "description", "file", "line", "arity"])
    |> Enum.filter(fn {_, v} -> v != nil end)
    |> Enum.into(%{})
  end

  defp extract_definition(_), do: %{}

  defp find_related(graph, symbol, depth) when depth > 0 do
    graph
    |> Enum.filter(fn {key, _} ->
      String.jaro_distance(symbol, key) > 0.7
    end)
    |> Enum.map(fn {key, _} -> key end)
    |> Enum.take(5)
  end

  defp find_related(_, _, _), do: []
end

defmodule BotArmyGraphifyCache.Handlers.GraphSearchHandler do
  @moduledoc """
  Searches within a cached knowledge graph for symbols, files, or patterns.
  """

  require Logger

  @cache_pattern ".graphify-cache/graph.json"

  def handle_search(query) do
    case query do
      %{"repo_path" => repo_path, "query" => search_query}
      when is_binary(repo_path) and is_binary(search_query) ->
        search_type = Map.get(query, "type", "symbol")
        search_graph(repo_path, search_query, search_type)

      _ ->
        %{"error" => "invalid_query"}
    end
  end

  defp search_graph(repo_path, search_query, search_type) do
    cache_file = Path.join(repo_path, @cache_pattern)

    case File.read(cache_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, graph} ->
            results = perform_search(graph, search_query, search_type)

            %{
              "repo_path" => repo_path,
              "query" => search_query,
              "type" => search_type,
              "results" => results,
              "count" => length(results)
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

  defp perform_search(graph, search_query, "symbol") do
    graph
    |> Enum.filter(fn {key, _} ->
      String.contains?(String.downcase(key), String.downcase(search_query))
    end)
    |> Enum.map(fn {key, value} ->
      %{
        "name" => key,
        "type" => get_type(value),
        "functions" => extract_function_names(value)
      }
    end)
  end

  defp perform_search(graph, search_query, "file") do
    graph
    |> Enum.filter(fn {key, _} ->
      String.contains?(String.downcase(key), String.downcase(search_query))
    end)
    |> Enum.map(fn {key, value} ->
      %{"path" => key, "type" => get_type(value)}
    end)
  end

  defp perform_search(graph, search_query, "pattern") do
    pattern_regex = Regex.compile!(String.downcase(search_query), "i")

    graph
    |> Enum.filter(fn {key, value} ->
      Regex.match?(pattern_regex, String.downcase(key)) or
        Regex.match?(pattern_regex, inspect(value))
    end)
    |> Enum.map(fn {key, _} ->
      %{"match" => key}
    end)
  end

  defp perform_search(_, _, _), do: []

  defp get_type(value) when is_map(value) do
    cond do
      Map.has_key?(value, "functions") -> "module"
      Map.has_key?(value, "module") -> "function"
      true -> "unknown"
    end
  end

  defp get_type(_), do: "unknown"

  defp extract_function_names(value) when is_map(value) do
    case Map.get(value, "functions") do
      list when is_list(list) ->
        list
        |> Enum.filter(&is_binary/1)
        |> Enum.take(5)

      _ ->
        []
    end
  end

  defp extract_function_names(_), do: []
end

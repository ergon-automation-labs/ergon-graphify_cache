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
        case Jason.decode(content) do
          {:ok, graph} ->
            cached_at = format_mtime(cache_file)

            %{
              "repo_path" => repo_path,
              "cached_at" => cached_at,
              "graph" => graph
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

  defp format_mtime(file_path) do
    case File.stat(file_path) do
      {:ok, stat} ->
        # stat.mtime is an Erlang datetime tuple {{year,month,day},{hour,minute,second}}
        case stat.mtime do
          {{year, month, day}, {hour, minute, second}} ->
            "#{year}-#{String.pad_leading(Integer.to_string(month), 2, "0")}-#{String.pad_leading(Integer.to_string(day), 2, "0")}T#{String.pad_leading(Integer.to_string(hour), 2, "0")}:#{String.pad_leading(Integer.to_string(minute), 2, "0")}:#{String.pad_leading(Integer.to_string(second), 2, "0")}Z"

          _ ->
            "unknown"
        end

      {:error, _} ->
        "unknown"
    end
  end
end

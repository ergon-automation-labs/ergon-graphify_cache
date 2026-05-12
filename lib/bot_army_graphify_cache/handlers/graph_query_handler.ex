defmodule BotArmyGraphifyCache.Handlers.GraphQueryHandler do
  @moduledoc """
  Handles graph queries by loading and returning cached knowledge graphs.
  Graphs larger than the NATS payload limit are gzip-compressed + base64-encoded.
  """

  require Logger

  @cache_pattern ".graphify-cache/graph.json"
  # NATS default max_payload is 1 MB; leave headroom for base64 overhead (~33%)
  @max_uncompressed_payload 768_000

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
            payload_size = byte_size(content)

            if payload_size > @max_uncompressed_payload do
              compressed = :zlib.gzip(content)
              encoded = Base.encode64(compressed)

              %{
                "repo_path" => repo_path,
                "cached_at" => cached_at,
                "graph" => encoded,
                "encoding" => "gzip+base64",
                "compressed" => true,
                "original_size" => payload_size,
                "compressed_size" => byte_size(encoded)
              }
            else
              %{
                "repo_path" => repo_path,
                "cached_at" => cached_at,
                "graph" => graph
              }
            end

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

defmodule BotArmyGraphifyCache.Handlers.GraphRefreshHandler do
  @moduledoc """
  Handles graph refresh requests. Checks if a graph cache exists and is stale,
  or signals that a refresh is needed.
  """

  require Logger

  @cache_pattern ".graphify-cache/graph.json"
  @stale_threshold_hours 24

  def handle_refresh(query) do
    case query do
      %{"repo_path" => repo_path} when is_binary(repo_path) ->
        check_refresh_needed(repo_path)

      _ ->
        %{"error" => "invalid_query"}
    end
  end

  defp check_refresh_needed(repo_path) do
    cache_file = Path.join(repo_path, @cache_pattern)

    case File.stat(cache_file) do
      {:ok, stat} ->
        age_hours = calculate_age_hours(stat.mtime)

        if age_hours > @stale_threshold_hours do
          %{
            "repo_path" => repo_path,
            "status" => "stale",
            "age_hours" => age_hours,
            "cached_at" => format_mtime(stat.mtime),
            "refresh_needed" => true,
            "message" => "Graph cache is stale. Run graphify to refresh."
          }
        else
          %{
            "repo_path" => repo_path,
            "status" => "fresh",
            "age_hours" => age_hours,
            "cached_at" => format_mtime(stat.mtime),
            "refresh_needed" => false,
            "message" => "Graph cache is fresh."
          }
        end

      {:error, :enoent} ->
        %{
          "repo_path" => repo_path,
          "status" => "missing",
          "refresh_needed" => true,
          "message" => "No graph cache found. Run graphify to generate."
        }

      {:error, reason} ->
        %{
          "error" => "stat_failed",
          "repo_path" => repo_path,
          "reason" => inspect(reason)
        }
    end
  end

  defp calculate_age_hours({{year, month, day}, {hour, minute, second}}) do
    case DateTime.new(Date.from_erl!({year, month, day}), Time.from_erl!({hour, minute, second})) do
      {:ok, file_time} ->
        now = DateTime.utc_now()

        DateTime.diff(now, file_time, :hour)

      _ ->
        999
    end
  end

  defp calculate_age_hours(_), do: 999

  defp format_mtime({{year, month, day}, {hour, minute, second}}) do
    "#{year}-#{pad(month)}-#{pad(day)}T#{pad(hour)}:#{pad(minute)}:#{pad(second)}Z"
  end

  defp format_mtime(_), do: "unknown"

  defp pad(n) do
    n |> Integer.to_string() |> String.pad_leading(2, "0")
  end
end

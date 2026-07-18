defmodule BotArmyGraphifyCache.NATS.Consumer do
  @moduledoc """
  NATS consumer for graphify knowledge graph queries.
  Serves cached knowledge graphs from .graphify-cache/graph.json files.
  """

  use GenServer
  require Logger

  alias BotArmyGraphifyCache.Handlers.{
    GraphQueryHandler,
    GraphSearchHandler,
    GraphStatsHandler,
    GraphListHandler,
    GraphContextHandler,
    GraphRefreshHandler
  }

  @reconnect_delay_ms 5_000
  @version Mix.Project.config()[:version]
  @registry_heartbeat_ms 20_000
  @health_subject "system.health.graphify_cache"
  @health_interval_ms 30_000

  @query_subject "bot_army.graph.query"
  @search_subject "bot_army.graph.search"
  @stats_subject "bot_army.graph.stats"
  @list_subject "bot_army.graph.list"
  @context_subject "bot_army.graph.context"
  @refresh_subject "bot_army.graph.refresh"

  @subjects [
    %{
      subject: @query_subject,
      type: :request_reply,
      description: "Query cached knowledge graph for a repository"
    },
    %{
      subject: @search_subject,
      type: :request_reply,
      description: "Search within a cached knowledge graph"
    },
    %{
      subject: @stats_subject,
      type: :request_reply,
      description: "Get statistics about a cached knowledge graph"
    },
    %{
      subject: @list_subject,
      type: :request_reply,
      description: "List all available cached knowledge graphs"
    },
    %{
      subject: @context_subject,
      type: :request_reply,
      description: "Get context around a symbol in a cached graph"
    },
    %{
      subject: @refresh_subject,
      type: :request_reply,
      description: "Check if a cached graph needs refresh"
    },
    %{
      subject: @health_subject,
      type: :publish,
      description: "Graphify cache health pulse"
    }
  ]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    {:ok, %{subscriptions: []}, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case GenServer.call(BotArmyLibraryRuntime.NATS.Connection, :get_connection, 5_000) do
      {:ok, conn} ->
        BotArmyLibraryRuntime.NATS.Connection.subscribe_to_status()

        subjects_to_sub = [
          @query_subject,
          @search_subject,
          @stats_subject,
          @list_subject,
          @context_subject,
          @refresh_subject
        ]

        case subscribe_all(conn, self(), subjects_to_sub, []) do
          {:ok, subs} ->
            BotArmyLibraryRuntime.Registry.register("graphify_cache", @subjects, @version)
            Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)
            Logger.info("[GraphifyCache] Subscribed to graph query subjects")
            Process.send_after(self(), :publish_health, 1_000)
            {:noreply, %{state | subscriptions: subs}}

          {:error, reason} ->
            Logger.error("[GraphifyCache] Subscribe failed: #{inspect(reason)}")
            Process.send_after(self(), :reconnect, @reconnect_delay_ms)
            {:noreply, state}
        end

      {:error, _} ->
        Process.send_after(self(), :reconnect, @reconnect_delay_ms)
        {:noreply, state}
    end
  end

  defp subscribe_all(_conn, _pid, [], subs), do: {:ok, Enum.reverse(subs)}

  defp subscribe_all(conn, pid, [subject | rest], subs) do
    case Gnat.sub(conn, pid, subject) do
      {:ok, sub} ->
        subscribe_all(conn, pid, rest, [sub | subs])

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_info(:reconnect, state) do
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info(:publish_health, state) do
    _ = build_health_payload() |> publish_json(@health_subject)
    Process.send_after(self(), :publish_health, @health_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    BotArmyLibraryRuntime.Tracing.with_consumer_span(msg.topic, Map.get(msg, :headers, []), fn ->
      try do
        query = Jason.decode!(msg.body)
        Logger.debug("[GraphifyCache] #{msg.topic}: #{inspect(query)}")

        response =
          case msg.topic do
            @query_subject -> GraphQueryHandler.handle_query(query)
            @search_subject -> GraphSearchHandler.handle_search(query)
            @stats_subject -> GraphStatsHandler.handle_stats(query)
            @list_subject -> GraphListHandler.handle_list(query)
            @context_subject -> GraphContextHandler.handle_context(query)
            @refresh_subject -> GraphRefreshHandler.handle_refresh(query)
            _ -> %{"error" => "unknown_subject"}
          end

        Logger.debug("[GraphifyCache] Response: #{inspect(response)}")

        case msg.reply_to do
          nil ->
            Logger.warning("[GraphifyCache] No reply_to for #{msg.topic}")

          reply_to ->
            _ = publish_json(response, reply_to)
        end
      rescue
        e ->
          Logger.warning("[GraphifyCache] Query failed: #{inspect(e)}")

          case msg.reply_to do
            nil -> :ok
            reply_to -> publish_json(%{"error" => "query_failed"}, reply_to)
          end
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:registry_heartbeat, state) do
    if state.subscriptions != [] do
      BotArmyLibraryRuntime.Registry.register("graphify_cache", @subjects, @version)
      Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)
    end

    {:noreply, state}
  end

  defp build_health_payload do
    %{
      service: "graphify_cache",
      status: "ok",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp publish_json(payload, subject) do
    with {:ok, conn} <- GenServer.call(BotArmyLibraryRuntime.NATS.Connection, :get_connection, 5_000) do
      Gnat.pub(conn, subject, Jason.encode!(payload))
    end
  end
end

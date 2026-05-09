defmodule BotArmyGraphifyCache.NATS.Consumer do
  @moduledoc """
  NATS consumer for graphify knowledge graph queries.
  Serves cached knowledge graphs from .graphify-cache/graph.json files.
  """

  use GenServer
  require Logger

  alias BotArmyGraphifyCache.Handlers.GraphQueryHandler

  @reconnect_delay_ms 5_000
  @version Mix.Project.config()[:version]
  @registry_heartbeat_ms 20_000
  @health_subject "system.health.graphify_cache"
  @health_interval_ms 30_000
  @query_subject "bot_army.graph.query"

  @subjects [
    %{
      subject: @query_subject,
      type: :request_reply,
      description: "Query cached knowledge graph for a repository"
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
    case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000) do
      {:ok, conn} ->
        BotArmyRuntime.NATS.Connection.subscribe_to_status()

        case Gnat.sub(conn, self(), @query_subject) do
          {:ok, sub} ->
            BotArmyRuntime.Registry.register("graphify_cache", @subjects, @version)
            Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)
            Logger.info("[GraphifyCache] Subscribed to #{@query_subject}")
            Process.send_after(self(), :publish_health, 1_000)
            {:noreply, %{state | subscriptions: [sub]}}

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
    BotArmyRuntime.Tracing.with_consumer_span(msg.topic, Map.get(msg, :headers, []), fn ->
      try do
        query = Jason.decode!(msg.body)
        Logger.debug("[GraphifyCache] Query: #{inspect(query)}")

        response = GraphQueryHandler.handle_query(query)
        Logger.debug("[GraphifyCache] Response: #{inspect(response)}")

        case msg.reply_to do
          nil ->
            Logger.warning("[GraphifyCache] No reply_to for query")

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
    if length(state.subscriptions) > 0 do
      BotArmyRuntime.Registry.register("graphify_cache", @subjects, @version)
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
    with {:ok, conn} <- GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000) do
      Gnat.pub(conn, subject, Jason.encode!(payload))
    end
  end
end

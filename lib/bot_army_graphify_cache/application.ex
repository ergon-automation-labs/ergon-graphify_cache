defmodule BotArmyGraphifyCache.Application do
  use Application

  @env Mix.env()
  @version Mix.Project.config()[:version]

  @impl true
  def start(_type, _args) do
    children =
      []
      |> maybe_add_consumer()
      |> maybe_add_health_responder()
      |> maybe_add_pulse_publisher()

    opts = [strategy: :one_for_one, name: BotArmyGraphifyCache.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_consumer(children) do
    if @env == :test, do: children, else: [BotArmyGraphifyCache.NATS.Consumer | children]
  end

  defp maybe_add_health_responder(children) do
    if @env == :test do
      children
    else
      children ++
        [
          {BotArmyLibraryRuntime.Health.Responder,
           [bot_name: :graphify_cache, version: @version]}
        ]
    end
  end

  # Periodic system.health heartbeat — Synapse treats system.health as stale
  # after ~90s; the reactive Responder alone never fills the window.
  defp maybe_add_pulse_publisher(children) do
    if @env == :test do
      children
    else
      [
        {BotArmyLibraryRuntime.HealthPulsePublisher,
         [app_name: :bot_army_graphify_cache, service: "graphify_cache"]}
        | children
      ]
    end
  end
end

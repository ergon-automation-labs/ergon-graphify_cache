defmodule BotArmyGraphifyCache.Application do
  use Application

  @env Mix.env()

  @impl true
  def start(_type, _args) do
    children =
      []
      |> maybe_add_consumer()

    opts = [strategy: :one_for_one, name: BotArmyGraphifyCache.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_consumer(children) do
    if @env == :test, do: children, else: [BotArmyGraphifyCache.NATS.Consumer | children]
  end
end

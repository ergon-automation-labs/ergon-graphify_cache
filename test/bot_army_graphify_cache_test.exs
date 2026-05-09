defmodule BotArmyGraphifyCacheTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmyGraphifyCache.Handlers.GraphQueryHandler

  test "handle_query returns error for invalid payload" do
    assert %{"error" => "invalid_query"} == GraphQueryHandler.handle_query(%{})
  end

  test "handle_query returns error when graph file missing" do
    assert %{"error" => "graph_not_found", "repo_path" => _} =
             GraphQueryHandler.handle_query(%{
               "repo_path" => "/nonexistent/repo/path/for/graphify"
             })
  end
end

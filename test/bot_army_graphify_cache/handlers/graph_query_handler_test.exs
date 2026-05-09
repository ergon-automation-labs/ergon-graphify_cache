defmodule BotArmyGraphifyCache.Handlers.GraphQueryHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  alias BotArmyGraphifyCache.Handlers.GraphQueryHandler

  describe "handle_query/1" do
    test "returns error when repo_path is missing" do
      result = GraphQueryHandler.handle_query(%{})
      assert result["error"] == "invalid_query"
    end

    test "returns error when repo_path is nil" do
      result = GraphQueryHandler.handle_query(%{"repo_path" => nil})
      assert result["error"] == "missing_repo_path"
    end

    test "returns error when graph not found" do
      result = GraphQueryHandler.handle_query(%{"repo_path" => "/nonexistent/path"})
      assert result["error"] == "graph_not_found"
      assert result["repo_path"] == "/nonexistent/path"
    end

    test "loads valid graph file" do
      # Create temp cache file
      tmp_dir = System.tmp_dir()
      cache_dir = Path.join(tmp_dir, "test_cache")
      File.mkdir_p!(cache_dir)
      cache_file = Path.join(cache_dir, ".graphify-cache/graph.json")
      File.mkdir_p!(Path.dirname(cache_file))

      graph_data = %{"nodes" => ["node1", "node2"], "edges" => []}
      File.write!(cache_file, Jason.encode!(graph_data))

      result = GraphQueryHandler.handle_query(%{"repo_path" => cache_dir})

      assert result["repo_path"] == cache_dir
      assert result["graph"] == graph_data
      assert result["cached_at"] != nil

      # Cleanup
      File.rm_rf!(cache_dir)
    end

    test "handles invalid JSON in cache file" do
      tmp_dir = System.tmp_dir()
      cache_dir = Path.join(tmp_dir, "invalid_json_cache")
      File.mkdir_p!(cache_dir)
      cache_file = Path.join(cache_dir, ".graphify-cache/graph.json")
      File.mkdir_p!(Path.dirname(cache_file))
      File.write!(cache_file, "invalid json {")

      result = GraphQueryHandler.handle_query(%{"repo_path" => cache_dir})

      assert result["error"] == "invalid_graph_format"
      assert result["repo_path"] == cache_dir

      # Cleanup
      File.rm_rf!(cache_dir)
    end
  end
end

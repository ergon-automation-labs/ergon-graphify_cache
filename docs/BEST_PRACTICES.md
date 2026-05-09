# Bot Army Best Practices

This document captures the patterns and practices that successful bots follow. These are not requirements, but recommendations proven in production across 12+ bots.

## Table of Contents

1. [Health Observability](#health-observability)
2. [HTTP Client Isolation](#http-client-isolation)
3. [Test Environment](#test-environment)
4. [Test Tagging & Organization](#test-tagging--organization)
5. [Release & Deployment](#release--deployment)
6. [Commit & Version Discipline](#commit--version-discipline)
7. [Skills](#skills)

---

## Health Observability

### Pattern: PulsePublisher

Every bot publishes health metrics every 30 minutes.

**NATS Subject:** `bot.<service>.pulse`

**Payload Structure:**
```json
{
  "service": "gtd",
  "health": "nominal",
  "timestamp": "2026-04-25T11:30:00Z",
  "metrics": {
    "active_projects": 5,
    "tasks_completed": 12,
    "errors_5m": 0
  }
}
```

**Health Signal Rules:**
- `:nominal` — All systems operational, business metrics positive
- `:degraded` — Minor issues or zero activity (recoverable)
- `:critical` — Errors, failures, or operational blocked state

**Implementation:**

```elixir
# lib/bot_army_<name>/pulse_publisher.ex
defmodule YourBot.PulsePublisher do
  use GenServer
  require Logger

  @publish_interval_ms 30 * 60 * 1000  # 30 minutes

  def init(_opts) do
    send(self(), :publish_pulse)
    {:ok, %{}}
  end

  def handle_info(:publish_pulse, state) do
    Task.start(fn -> publish_pulse() end)
    Process.send_after(self(), :publish_pulse, @publish_interval_ms)
    {:noreply, state}
  end

  defp publish_pulse do
    pulse = %{
      service: "your_service",
      health: health_signal(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      metrics: collect_metrics()
    }

    BotArmyRuntime.NATS.Connection.publish(
      "bot.your_service.pulse",
      Jason.encode!(pulse)
    )
  end

  defp health_signal do
    # TODO: Implement domain-specific logic
    # Example: return :critical if error_count > 10
    :nominal
  end

  defp collect_metrics do
    # TODO: Return domain metrics
    %{}
  end
end
```

**Add to Application.ex:**
```elixir
defp maybe_add_pulse_publisher(children) do
  if @env == :test do
    children
  else
    [{YourBot.PulsePublisher, []} | children]
  end
end
```

**Synapse aggregates all pulses** into fleet health view for observability.

---

## HTTP Client Isolation

### Pattern: Behavior + Dependency Injection

Use `HTTPClient` behavior for all external HTTP calls. This allows mocking in tests without real network calls.

**Define Behavior:**

```elixir
# lib/your_bot/http_client.ex
defmodule YourBot.HTTPClient do
  @callback get(url :: String.t(), opts :: keyword()) :: {:ok, map()} | {:error, any()}
  @callback get(url :: String.t()) :: {:ok, map()} | {:error, any()}
end

defmodule YourBot.HTTPClient.Req do
  @behaviour YourBot.HTTPClient

  @impl true
  def get(url, opts \\ []) do
    Req.get(url, opts)
  end
end
```

**Use in GenServer:**

```elixir
# lib/your_bot/external_api.ex
defmodule YourBot.ExternalAPI do
  def init(opts) do
    http_client = Keyword.get(opts, :http_client, YourBot.HTTPClient.Req)
    {:ok, %{http_client: http_client}}
  end

  def handle_call({:fetch_data, url}, _from, state) do
    case fetch_data(url, state[:http_client]) do
      {:ok, data} -> {:reply, {:ok, data}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp fetch_data(url, http_client) do
    case http_client.get(url) do
      {:ok, response} -> {:ok, response.body}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

**Use in Tests:**

```elixir
# test/your_bot/external_api_test.exs
defmodule YourBot.ExternalAPITest do
  use ExUnit.Case
  @moduletag :integrations

  test "fetches data from API" do
    Mox.expect(HTTPClientMock, :get, fn url, _opts ->
      {:ok, %{status: 200, body: %{"key" => "value"}}}
    end)

    # Pass mock instead of real client
    {:ok, api} = YourBot.ExternalAPI.start_link(http_client: HTTPClientMock)
    {:ok, data} = GenServer.call(api, {:fetch_data, "https://api.example.com"})
    assert data.key == "value"
  end
end
```

**Benefits:**
- Tests never make real HTTP calls
- No `Req.TransportError` noise in test output
- Fast test execution (no network latency)
- Easy to stub different response scenarios

---

## Test Environment

### Pattern: Environment-Aware Startup

Use compile-time `@env Mix.env()` to gate components that shouldn't run in tests.

**In Application.ex:**

```elixir
defmodule YourBot.Application do
  use Application

  @env Mix.env()

  def start(_type, _args) do
    children =
      []
      |> maybe_add_repo()
      |> maybe_add_pulse_publisher()
      |> maybe_add_workers()

    Supervisor.start_link(children, [strategy: :one_for_one])
  end

  # Database: only in production/dev
  defp maybe_add_repo do
    if @env == :test do
      []
    else
      [{YourBot.Repo, []}]
    end
  end

  # Health metrics: only in production/dev
  defp maybe_add_pulse_publisher(children) do
    if @env == :test do
      children
    else
      [{YourBot.PulsePublisher, []} | children]
    end
  end

  # Long-running pollers/watchers: only in production/dev
  defp maybe_add_workers(children) do
    if @env == :test do
      children
    else
      [{YourBot.Scheduler, []}, {YourBot.Poller, []} | children]
    end
  end
end
```

**Benefits:**
- Tests start instantly (no DB connections)
- No background processes interfering with test assertions
- Database sandbox mode works reliably
- HTTP client mocking works (no real network calls attempted)

---

## Test Tagging & Organization

### Pattern: @moduletag for Feature-Based Test Running

Every test module has a `@moduletag` that groups tests by feature area. Developers can run only tests for the code they're changing.

**In test_helper.exs:**

```elixir
ExUnit.configure(exclude: [:integration, :load, :nats_live])
```

**Common Tags:**

| Tag | Source | Example |
|-----|--------|---------|
| `:handlers` | `lib/.../handlers/*_handler.ex` | Request/command handlers |
| `:stores` | `lib/.../*_store.ex` | Persistence/state management |
| `:nats` | `lib/.../nats/*` | NATS consumer/publisher |
| `:scheduler` | `lib/.../*_scheduler.ex` | Polling, timing, state machines |
| `:integrations` | `lib/.../integrations/*` | External APIs, HTTP clients |
| `:skills` | `lib/.../skills/*` | Skill implementations |

**Individual Test Tags:**

| Tag | Purpose | Run |
|-----|---------|-----|
| `@tag :integration` | Requires real services (DB, HTTP, NATS) | `mix test --include integration` |
| `@tag :nats_live` | Requires NATS connection | `mix test --include nats_live` |
| `@tag :load` | Performance/stress test | `mix test --include load` |

**Example:**

```elixir
defmodule YourBot.Handlers.ExampleTest do
  use ExUnit.Case, async: true
  @moduletag :handlers  # ← Feature area

  describe "handle_create" do
    test "creates item successfully" do
      assert YourBot.Handlers.Example.handle_create(payload) == {:ok, item}
    end

    @tag :integration  # ← Requires DB
    test "persists to database" do
      {:ok, item} = YourBot.Handlers.Example.handle_create(payload)
      assert item.id != nil
    end
  end
end
```

**Run Tests:**

```bash
mix test                          # Unit tests only (default)
mix test --only handlers          # All handler tests
mix test --only handlers --trace  # Handler tests with debug output
mix test --include integration    # Include database tests
mix test --only scheduler --trace # Scheduler tests with output
```

---

## Release & Deployment

### Pattern: Automated Releases via Pre-Push Hooks

Every bot follows the same release workflow:

**Version in mix.exs → GitHub Release → Jenkins → Salt → launchd**

**Pre-Push Hook Flow:**

```bash
git push
  ↓
# 1. Check version bumped?
  ↓
# 2. Compile + Test
  ↓
# 3. Build OTP release
  ↓
# 4. Create tarball: bot_name-X.Y.Z.tar.gz
  ↓
# 5. Publish to GitHub
  ↓
# 6. Jenkins detects release (polls every 5 min)
  ↓
# 7. Jenkins:
#    - Downloads tarball
#    - Deploys to /opt/ergon/releases/
#    - Restarts launchd service
```

**No manual release steps needed** — version bump triggers automation.

---

## Commit & Version Discipline

### Pattern: Version Bump → Commit → Push

When making changes that should be deployed:

```bash
# 1. Make changes to code
#    Edit: lib/your_bot/...
#    Add: features, fixes, observability

# 2. Bump version in mix.exs
#    0.1.0 → 0.1.1 (patch for fixes)
#    0.1.0 → 0.2.0 (minor for features)

# 3. Commit
git add lib/ mix.exs
git commit -m "Add feature X

Reason: Why this matters
Impact: What changed

Co-Authored-By: Claude <noreply@anthropic.com>"

# 4. Push (never --no-verify)
git push

# 5. Pre-push hook:
#    - Tests code
#    - Builds release
#    - Publishes to GitHub
#    - Triggers deployment pipeline
```

**Important:**
- ✅ Always bump `mix.exs` version when changing code
- ✅ Use commit messages that explain **why** (not what)
- ✅ Never use `git push --no-verify` (skips pre-push hook)
- ✅ One bot repo per push (separate repos = separate releases)

---

## Skills

Two complementary skill architectures:

### Pattern 1: Code-Based Skills (Per-Bot, Recommended)

Autonomous Elixir units defined in each bot. Use for:
- Bot-specific logic you want in version control
- Skills compiled with the bot
- Full type safety + testing
- Tight integration with bot code

**Structure:**

```
lib/your_bot/skills/
├── example.ex          # Template skill
├── analyze.ex          # Custom skill 1
└── classify.ex         # Custom skill 2
```

**Lifecycle:**

```
NATS Message Arrives
    ↓
bot.your_bot.command.analyze
    ↓
GenBot Routes to Skill
    ↓
validate(payload) — Check schema
    ↓
execute(payload, context) — Run logic
    ↓
Result → NATS Response Subject
```

**Payload Format:**

```json
{
  "request_id": "uuid",
  "content": "what to process",
  "metadata": {...}
}
```

**Context Passed to execute/2:**

```elixir
ctx = %{
  bot_id: "your-bot-id",
  llm: llm_proxy,          # For LLM requests
  personality: "helpful",  # Bot personality for tone
  context: %{},            # Current state/context
}
```

**Implementation Example:**

```elixir
defmodule YourBot.Skills.Analyze do
  use BotArmy.Skill
  require Logger

  # Skill metadata
  @impl true
  def name, do: :analyze

  @impl true
  def description do
    "Analyzes content for patterns and insights"
  end

  @impl true
  def nats_triggers do
    ["bot.your_bot.command.analyze"]
  end

  @impl true
  def llm_hint do
    :fast  # or :deep for complex reasoning
  end

  # Validate incoming payload
  @impl true
  def validate(%{"content" => content, "criteria" => criteria})
      when is_binary(content) and is_binary(criteria) do
    :ok
  end

  def validate(_) do
    {:error, "content and criteria required"}
  end

  # Execute skill logic
  @impl true
  def execute(%{"content" => content, "criteria" => criteria}, ctx) do
    try do
      # Option 1: Simple processing (no LLM)
      results = analyze_content(content, criteria)

      {:ok, %{
        analysis: results,
        bot_id: ctx.bot_id,
        executed_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }}

      # Option 2: With LLM reasoning
      # {:ok, llm_result} = ctx.llm.request(
      #   "Analyze: " <> content <> " using criteria: " <> criteria,
      #   hint: :deep
      # )
      # {:ok, %{analysis: llm_result.output}}
    rescue
      e ->
        Logger.error("Analysis failed: #{inspect(e)}")
        {:error, :analysis_failed}
    end
  end

  defp analyze_content(content, criteria) do
    # Your domain logic here
    %{
      length: byte_size(content),
      matches_criteria: String.contains?(content, criteria)
    }
  end
end
```

**Testing Skills:**

```elixir
defmodule YourBot.Skills.AnalyzeTest do
  use ExUnit.Case
  @moduletag :skills

  alias YourBot.Skills.Analyze

  test "validates required fields" do
    assert Analyze.validate(%{"content" => "test", "criteria" => "find"}) == :ok
    assert Analyze.validate(%{"content" => "test"}) != :ok
  end

  test "executes analysis" do
    payload = %{"content" => "hello world", "criteria" => "world"}
    ctx = %{bot_id: "test-bot"}

    {:ok, result} = Analyze.execute(payload, ctx)
    assert result.analysis.matches_criteria == true
  end
end
```

**LLM Integration (Optional):**

Skills can request LLM reasoning via `ctx.llm`:

```elixir
{:ok, llm_result} = ctx.llm.request(
  "Classify this sentiment: #{content}",
  hint: :fast   # Fast for simple tasks
)

# Or:
{:ok, llm_result} = ctx.llm.request(
  "Multi-step reasoning: #{content}",
  hint: :deep   # Deep for complex reasoning chains
)
```

**Registering Skills:**

Skills are registered in `Application.ex` via GenBot configuration:

```elixir
defmodule YourBot.Application do
  def start(_type, _args) do
    children = [
      {BotArmy.GenBot, [
        bot_id: "your-bot-id",
        skills: [
          YourBot.Skills.Analyze,
          YourBot.Skills.Classify,
          YourBot.Skills.Example
        ],
        # Optional: LLM integration
        llm_endpoint: System.get_env("LLM_ENDPOINT"),
        personality: "helpful and concise"
      ]}
    ]

    Supervisor.start_link(children, [strategy: :one_for_one])
  end
end
```

**NATS Subject Naming Convention:**

- **Command (Trigger):** `bot.<app_name>.command.<skill_name>`
  - Example: `bot.your_bot.command.analyze`
- **Response:** `bot.<app_name>.response.<request_id>`
  - Automatically routed by GenBot

**Request Example:**

```bash
nats request --server nats://localhost:4223 \
  'bot.your_bot.command.analyze' \
  '{"request_id":"uuid","content":"test","criteria":"find"}' \
  --timeout 5s
```

**Benefits of Code-Based Skills:**

- ✅ Reusable across bot fleet (same subject pattern)
- ✅ Autonomous — run without user interaction
- ✅ Optional LLM — use LLM for complex tasks, pure logic for simple ones
- ✅ Observable — logged, trackable via request_id
- ✅ Scalable — add new skills without changing bot core
- ✅ Testable — full unit test isolation via mocks
- ✅ Versioned — skills deploy with bot via GitHub releases

### Pattern 2: Database-Driven Skills (Shared, Advanced)

Centralized markdown-based skill platform via `bot_army_skills` library. Use for:
- Shared skills across multiple bots
- Non-developers to manage skills
- Hot-reloading without bot restart
- Tenant-scoped skill variants

**Architecture:**

```
bot_army_skills (shared library)
    ↓
PostgreSQL (tenant-scoped skills table)
    ↓
Markdown + YAML frontmatter (skill definition)
    ↓
Template variables: {{payload.key}}, {{context.key}}, {{action:slug}}
    ↓
Bot opts-in: GenBot config db_skills: true
    ↓
Skills loaded at runtime from database
```

**Skill Definition (Markdown):**

```markdown
---
name: summarize
description: Summarize content for reporting
triggers: bot.gtd.action.summarize
llm_hint: quality
---

Summarize the following content:

{{payload.content}}

Focus on:
{{payload.focus}}

Provide a brief summary with key points.
```

**Registration:**

```elixir
{BotArmy.GenBot, [
  bot_id: "your-bot-id",
  db_skills: true,  # Load skills from database
  repo: YourBot.Repo,
  skills: [
    # Static skills still work alongside db skills
    YourBot.Skills.Analyze
  ]
]}
```

**Benefits of Database-Driven Skills:**

- ✅ Shared across bot fleet
- ✅ Multi-tenant support (skill variants per tenant)
- ✅ Hot reload (no bot restart needed)
- ✅ Accessible to non-developers
- ✅ Template-based (variable substitution)
- ✅ Version history (skill versioning in DB)

**Choose Based On:**

| Feature | Code-Based | DB-Driven |
|---------|-----------|-----------|
| **Quick to build** | ✅ | ❌ |
| **Full type safety** | ✅ | ❌ |
| **Hot reload** | ❌ | ✅ |
| **Shared across bots** | ⚠️ | ✅ |
| **Non-dev friendly** | ❌ | ✅ |
| **Complex logic** | ✅ | ⚠️ |
| **Versioned with bot** | ✅ | ❌ |

**Recommendation:** Start with **code-based skills**. Move to database-driven if you need shared skills, hot reload, or non-dev management.

---

## Checklist for New Bots

### Foundation Setup

- [ ] Copy template files
- [ ] Replace all `{{PLACEHOLDER}}` values
- [ ] Run `mix deps.get && mix compile` (verify compiles)
- [ ] Run `mix test` (should have 1 test passing)

### Core Services

- [ ] Implement `PulsePublisher` — customize `health_signal()` and `collect_metrics()`
- [ ] Implement `HTTPClient` for external APIs
- [ ] Gate repo + workers in `Application.ex` via `@env Mix.env()`
- [ ] Add `test/test_helper.exs` with Mox (already in template)

### Skills (if needed)

- [ ] Create skills in `lib/your_bot/skills/` (code-based, recommended)
  - [ ] Rename `example.ex` to your skill names
  - [ ] Implement `validate/1` for payload schema
  - [ ] Implement `execute/2` with domain logic
  - [ ] Update `nats_triggers/0` with NATS subjects
- [ ] Test skills with `mix test --only skills`
- [ ] Register skills in `Application.ex` via GenBot
- [ ] Optional: Enable `db_skills: true` if using shared database skills

### Testing & Tagging

- [ ] Add `@moduletag` to all test modules
- [ ] Test handlers with `mix test --only handlers`
- [ ] Test skills with `mix test --only skills`
- [ ] Test stores with `mix test --only stores` (if applicable)
- [ ] Run full suite: `mix test` (should pass)

### Verification

- [ ] Health pulse publishes every 30 min:
  ```bash
  nats request --server nats://localhost:4223 bot.<service>.pulse '{}' --timeout 5s
  ```
- [ ] Skills respond correctly:
  ```bash
  nats request --server nats://localhost:4223 \
    'bot.<app>.command.<skill>' \
    '{"request_id":"id","content":"test"}' --timeout 5s
  ```

### Release & Deploy

- [ ] Bump version in `mix.exs`
- [ ] Commit: `git add lib/ mix.exs && git commit -m "Your message"`
- [ ] Push: `git push` (pre-push hook runs automatically)
- [ ] Verify GitHub release created
- [ ] Verify Jenkins detects release
- [ ] Verify launchd service restarts with new version

---

## Questions?

Refer to production bots for examples:
- **GTD** (`bot_army_gtd`) — project tracking, decomposition, health metrics
- **LLM** (`bot_army_llm`) — API circuit breaker, conversation state, error handling
- **SRE** (`bot_army_sre`) — Kubernetes integration, Prometheus queries, HTTP client isolation
- **Skills Bot** (`bot_army_skills`) — Shared database-driven skills platform

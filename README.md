# HN Telegram Digest

OTP application for a Hacker News digest Telegram bot. The app dogfoods Squid
Mesh in a small host application with a real Ecto repo, Oban execution, Telegram
polling, and durable workflow state.

## Current Dev Path

The app can currently run Telegram ingestion, subscription commands, and manual
digest requests in dev:

- Poll Telegram with `getUpdates`.
- Fetch and parse Hacker News front-page RSS items.
- Deduplicate Hacker News items per Telegram chat.
- Format deduplicated Hacker News items into deterministic Telegram text.
- Persist received Telegram updates.
- Start a Squid Mesh workflow for `/start` and `/stop`.
- Start a Hacker News digest workflow for `/digest` from active subscriptions.
- Send deterministic Telegram replies for unsupported commands.
- Start a Squid Mesh cron workflow that fans out digest workflow runs for
  active subscriptions.
- Persist Telegram chats and subscription status.
- Send and record Telegram confirmation messages.

Verify Telegram integration by sending `/start`, `/digest`, or `/stop` to the
bot, checking that Telegram receives the expected reply or digest, and checking
the database rows described below.

## Test With Your Own Telegram Bot

Follow these steps to run the app locally against a real Telegram bot you own.

1. Create the bot in Telegram.

   Open Telegram, message `@BotFather`, send `/newbot`, and follow the prompts
   for the display name and username. BotFather will return a bot token.

2. Configure the bot commands.

   In the same BotFather chat, send `/setcommands`, select your bot, and enter:

   ```text
   start - Subscribe to Hacker News digests
   stop - Stop Hacker News digests
   digest - Send a Hacker News digest now
   ```

3. Create a local env file.

   ```sh
   cp .env.example .env.local
   ```

4. Add your token and enable polling.

   Edit `.env.local`:

   ```sh
   TELEGRAM_BOT_TOKEN=replace-with-your-bot-token
   TELEGRAM_POLLING_ENABLED=true
   ```

   Do not commit `.env.local` or paste the real token into committed files.

5. Load the env file in your shell.

   ```sh
   set -a
   source .env.local
   set +a
   ```

6. Remove any webhook from the bot.

   The dev app uses polling with `getUpdates`. If the bot has a webhook,
   Telegram will not deliver updates to polling until the webhook is removed.

   ```sh
   curl -sS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/deleteWebhook"
   ```

7. Create and migrate the database.

   The app expects Postgres to be reachable with the values from
   `config/dev.exs`. The defaults are:

   ```text
   POSTGRES_USER=postgres
   POSTGRES_PASSWORD=postgres
   POSTGRES_HOST=localhost
   POSTGRES_DB=hn_telegram_digest_dev
   ```

   For a fresh database:

   ```sh
   mix setup
   ```

   If the database already exists:

   ```sh
   mix ecto.migrate
   ```

8. Start the OTP app.

   ```sh
   mix run --no-halt
   ```

9. Send `/start` to your bot in Telegram.

   The app should poll Telegram, persist the update, start the subscription
   workflow, store the chat subscription as active, and send this confirmation:

   ```text
   You are subscribed to Hacker News digests.
   ```

10. Inspect the database from another terminal.

    If you use `DATABASE_URL`:

    ```sh
    psql "$DATABASE_URL" -c "select chat_id, type, username from telegram_chats;"
    psql "$DATABASE_URL" -c "select chat_id, status, subscribed_at, unsubscribed_at from telegram_subscriptions;"
    psql "$DATABASE_URL" -c "select idempotency_key, chat_id, status, sent_at from telegram_message_deliveries;"
    ```

    With the default local database:

    ```sh
    psql -d hn_telegram_digest_dev -c "select chat_id, type, username from telegram_chats;"
    psql -d hn_telegram_digest_dev -c "select chat_id, status, subscribed_at, unsubscribed_at from telegram_subscriptions;"
    psql -d hn_telegram_digest_dev -c "select idempotency_key, chat_id, status, sent_at from telegram_message_deliveries;"
    ```

11. Send `/stop` to your bot.

    Telegram should receive:

    ```text
    You are unsubscribed from Hacker News digests.
    ```

    Rerun the subscription query. The row should move to `inactive` and set
    `unsubscribed_at`.

12. Send `/digest` to your bot.

    Active subscriptions should start a digest workflow and receive a digest if
    there are new Hacker News items. Inactive or unknown chats should receive:

    ```text
    Subscribe with /start before requesting a Hacker News digest.
    ```

## Trigger The Schedule Locally

The daily schedule is declared as a Squid Mesh cron trigger in
`HnTelegramDigest.Workflows.ScheduleHnDigests` and activated through
`SquidMesh.Plugins.Cron` in dev/prod Oban config.

To trigger the schedule without waiting for the cron minute, start a scheduler
workflow manually:

```sh
iex -S mix
```

```elixir
SquidMesh.start_run(HnTelegramDigest.Workflows.ScheduleHnDigests, :daily_digest_schedule, %{})
```

That scheduler workflow queries active subscriptions and starts one
`HnTelegramDigest.Workflows.DeliverHnDigest` run per active chat. The same
digest workflow is used for manual `/digest` requests. Squid Mesh currently
allows only one trigger per workflow, so the host app uses one shared
`:digest_requested` trigger and tracks the missing multi-trigger support as a
runtime finding below.

Automated tests keep API boundaries mocked or unexecuted; real Hacker News and
Telegram calls are reserved for explicit smoke testing.

## Operator Diagnostics

Inspect a persisted Squid Mesh run from the app:

```sh
mix hn_telegram_digest.inspect_run RUN_ID
```

The task prints the workflow, trigger, status, current step, persisted payload,
context, errors, steps, and step runs. Secret-like values are redacted before
printing.

Squid Mesh has an `explain_run/2` API in the repository, but it is not in the
current Hex release used by this app. Until Squid Mesh publishes that API, this
task reports the upstream release gap:

```sh
mix hn_telegram_digest.explain_run RUN_ID
```

See [Squid Mesh #148](https://github.com/ccarvalho-eng/squid_mesh/issues/148).

## Restart Smoke

This smoke path checks that a queued workflow run remains inspectable across a
fresh BEAM process and that resuming work does not call Telegram when no bot
token is configured. Step 4 can fetch the real Hacker News RSS feed; it should
not call the real Telegram API without `TELEGRAM_BOT_TOKEN`.

1. Reset the test database.

   ```sh
   MIX_ENV=test mix ecto.reset
   ```

2. Start a digest run and leave it queued.

   ```sh
   MIX_ENV=test mix run -e '
   alias HnTelegramDigest.Telegram.Subscriptions
   alias HnTelegramDigest.Workflows.DeliverHnDigest

   {:ok, _subscription} =
     Subscriptions.apply_subscription_command(%{
       action: "subscribe",
       chat: %{id: 12_345, type: "private"}
     })

   {:ok, run} =
     SquidMesh.start_run(
       DeliverHnDigest,
       :digest_requested,
       %{chat_id: 12_345, window_start_at: "2026-05-10T13:00:00Z"}
     )

   IO.puts("digest_run_id=#{run.id}")
   '
   ```

3. In a new command, inspect the queued run using the printed id.

   ```sh
   MIX_ENV=test mix hn_telegram_digest.inspect_run DIGEST_RUN_ID
   ```

   Expected: the run is still present after the process restart and is either
   `pending` or `running`, depending on whether any worker already picked it up.

4. Resume queued work in a fresh process without configuring
   `TELEGRAM_BOT_TOKEN`.

   ```sh
   MIX_ENV=test mix run -e '
   result = Oban.drain_queue(queue: :squid_mesh, with_recursion: true)
   IO.inspect(result, label: "drain")
   '
   ```

   Expected: the workflow resumes from persisted Squid Mesh/Oban state. If it
   reaches Telegram delivery, the host app records a failed
   `telegram_message_deliveries` row with `missing_telegram_bot_token` instead
   of sending a real Telegram message.

5. Inspect the final run state and delivery rows.

   ```sh
   MIX_ENV=test mix hn_telegram_digest.inspect_run DIGEST_RUN_ID
   psql -d hn_telegram_digest_test -c "select idempotency_key, status, last_error from telegram_message_deliveries;"
   ```

Verified on May 10, 2026: a queued digest run was inspected from a fresh BEAM
process, `Oban.drain_queue/2` resumed four Squid Mesh steps, the run failed at
`send_digest` with `missing_telegram_bot_token`, and the only Telegram delivery
row was `failed` with `{"kind": "missing_telegram_bot_token"}`.

## Tests

Run the test suite:

```sh
mix test
```

The workflow tests cover:

- Hacker News RSS fetching and parsing into workflow-safe feed item maps.
- per-chat Hacker News item deduplication with replay-safe workflow retries.
- deterministic Telegram digest formatting, including empty digests and long
  item text.
- `/start` creates or updates an active subscription.
- `/stop` marks an existing subscription inactive.
- `/digest` starts a digest workflow for active subscriptions.
- inactive `/digest` and unsupported commands send deterministic Telegram
  replies without starting workflow work.
- operator diagnostics format `SquidMesh.inspect_run/2` output and fail clearly
  while `SquidMesh.explain_run/2` is not in the published dependency.
- duplicate command delivery is idempotent at the subscription row.
- confirmation delivery is persisted and retry-safe by idempotency key.
- non-command messages do not start workflow work.

## Runtime Notes

- `TELEGRAM_POLLING_ENABLED=false` leaves the poller out of the supervision tree.
- `TELEGRAM_BOT_TOKEN` is required when polling is enabled and when a workflow
  needs to send Telegram confirmations.
- Polling is durable through the `telegram_updates` table and Telegram
  `update_id` offset.
- Subscription commands are executed through Squid Mesh and Oban, so workflow
  state is inspectable through Squid Mesh runtime APIs.
- Hacker News deduplication is stored in `hacker_news_seen_items`. Items are
  reserved by chat and workflow run so a retry of the same run returns the same
  new items, while later runs treat those items as duplicates.
- Digest formatting is side-effect free and emits plain Telegram text without a
  parse mode. Long messages are capped to Telegram's text limit with explicit
  omitted-item metadata.
- Outbound confirmations are durable through `telegram_message_deliveries`.
  Successful duplicate step attempts skip the Telegram API call; failed sends
  are recorded for retry. Stale in-flight sends move to `unknown` for operator
  inspection instead of retrying automatically, because Telegram may already
  have accepted the message.
- Scheduled digest fanout intentionally stays thin in the host app: it queries
  active subscriptions and starts digest workflow runs through Squid Mesh.
  Dynamic parent/child run modeling and duplicate scheduled-start semantics are
  left to Squid Mesh and tracked as runtime findings below.
- Manual `/digest` requests reuse the same digest workflow as scheduled fanout.
  Because Squid Mesh currently supports exactly one trigger per workflow, both
  entrypoints share the `:digest_requested` trigger instead of modeling separate
  `:scheduled_digest` and `:manual_digest` triggers.
- The digest send step re-checks the subscription before calling Telegram, so
  stale queued digest runs skip delivery after a chat unsubscribes.
- `mix hn_telegram_digest.inspect_run RUN_ID` is the host app's operator
  surface over `SquidMesh.inspect_run/2`. It formats and redacts data but does
  not interpret runtime state itself.

## Squid Mesh Findings

- [Squid Mesh #144](https://github.com/ccarvalho-eng/squid_mesh/issues/144):
  Squid Mesh installs several separate migrations for its run, step, attempt,
  trigger, and manual/resume schema. For host apps, one cohesive generated
  migration, or fewer clearly grouped migrations, would be easier to review and
  apply.
- [Squid Mesh #141](https://github.com/ccarvalho-eng/squid_mesh/issues/141):
  Scheduled digest fanout has a runtime-sized graph: one digest run per active
  subscription. This app keeps subscription lookup in host code, but child run
  relationships, cancellation/replay semantics, and inspection of dynamic
  subflows belong in Squid Mesh.
- [Squid Mesh #146](https://github.com/ccarvalho-eng/squid_mesh/issues/146):
  Squid Mesh cron triggers do not expose the intended schedule window to the
  workflow payload. This app currently derives the window inside the scheduler
  step, which is enough for dogfooding but weakens duplicate-window semantics
  after delayed cron execution.
- [Squid Mesh #145](https://github.com/ccarvalho-eng/squid_mesh/issues/145):
  Squid Mesh does not provide a built-in idempotency key for cron-started runs.
  The host app currently avoids adding its own scheduled-run table so this gap
  stays visible: duplicate cron delivery can create duplicate digest workflow
  runs, even though downstream domain deduplication still protects story
  delivery.
- [Squid Mesh #147](https://github.com/ccarvalho-eng/squid_mesh/issues/147):
  Squid Mesh currently validates that each workflow has exactly one trigger.
  This app needed scheduled and manual entrypoints for the same digest workflow,
  so it uses one shared `:digest_requested` trigger and records the missing
  first-class multi-trigger support upstream.
- [Squid Mesh #148](https://github.com/ccarvalho-eng/squid_mesh/issues/148):
  `SquidMesh.explain_run/2` exists in the Squid Mesh repo but is not in the
  current published Hex release. The host app exposes a placeholder
  `mix hn_telegram_digest.explain_run RUN_ID` task that reports this release gap
  instead of re-implementing explanation logic locally.
- [Squid Mesh #149](https://github.com/ccarvalho-eng/squid_mesh/issues/149):
  Public run-id APIs should return structured errors for malformed IDs instead
  of leaking Ecto cast exceptions. This app validates CLI `RUN_ID` input at the
  host boundary, but Squid Mesh should still harden `inspect_run/2`,
  `explain_run/2`, and lifecycle APIs that accept persisted run IDs.

Reviewed as host-owned, not Squid Mesh issues:

- Telegram delivery rows, idempotency keys, stale in-flight recovery, and
  `unknown` delivery status are host-owned external side-effect semantics.
  Squid Mesh provides workflow retries and run context; it cannot know whether
  Telegram accepted a message after a process crash.
- Hacker News item deduplication is product-domain state keyed by chat and item.
  Squid Mesh should not own feed-specific duplicate rules.
- Operator CLI rendering and redaction are host presentation concerns. Squid
  Mesh should expose structured diagnostic data and stable error shapes; the
  host app decides how to format that data for operators.

# HN Telegram Digest

OTP application for a Hacker News digest Telegram bot. The app dogfoods Squid
Mesh in a small host application with a real Ecto repo, Oban execution, Telegram
polling, and durable workflow state.

## Current Dev Path

The app can currently run the Telegram ingestion and subscription-command
workflow in dev:

- Poll Telegram with `getUpdates`.
- Fetch and parse Hacker News front-page RSS items.
- Deduplicate Hacker News items per Telegram chat.
- Format deduplicated Hacker News items into deterministic Telegram text.
- Persist received Telegram updates.
- Start a Squid Mesh workflow for `/start` and `/stop`.
- Start a Squid Mesh cron workflow that fans out digest workflow runs for
  active subscriptions.
- Persist Telegram chats and subscription status.
- Send and record Telegram confirmation messages.

Verify Telegram integration by sending `/start` or `/stop` to the bot, checking
that Telegram receives the confirmation reply, and checking the database rows
described below.

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
`HnTelegramDigest.Workflows.DeliverHnDigest` run per active chat. Automated
tests keep API boundaries mocked or unexecuted; real Hacker News and Telegram
calls are reserved for explicit smoke testing.

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
  Duplicate scheduled-start semantics are left to Squid Mesh and tracked as a
  runtime finding below.

## Squid Mesh Findings

- [Squid Mesh #144](https://github.com/ccarvalho-eng/squid_mesh/issues/144):
  Squid Mesh installs several separate migrations for its run, step, attempt,
  trigger, and manual/resume schema. For host apps, one cohesive generated
  migration, or fewer clearly grouped migrations, would be easier to review and
  apply.
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

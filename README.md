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
- Persist received Telegram updates.
- Start a Squid Mesh workflow for `/start` and `/stop`.
- Persist Telegram chats and subscription status.
- Send and record Telegram confirmation messages.

Digest generation and scheduled delivery are later slices. For now, verify
Telegram integration by sending `/start` or `/stop` to the bot, checking that
Telegram receives the confirmation reply, and checking the database rows
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

## Tests

Run the test suite:

```sh
mix test
```

The workflow tests cover:

- Hacker News RSS fetching and parsing into workflow-safe feed item maps.
- per-chat Hacker News item deduplication with replay-safe workflow retries.
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
- Outbound confirmations are durable through `telegram_message_deliveries`.
  Successful duplicate step attempts skip the Telegram API call; failed sends
  are recorded for retry. Stale in-flight sends move to `unknown` for operator
  inspection instead of retrying automatically, because Telegram may already
  have accepted the message.

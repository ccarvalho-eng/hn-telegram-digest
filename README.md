# HN Telegram Digest

OTP application for a Hacker News digest Telegram bot. The app dogfoods Squid
Mesh in a small host application with a real Ecto repo, Oban execution, Telegram
polling, and durable workflow state.

## Current Dev Path

The app can currently run the Telegram ingestion and subscription-command
workflow in dev:

- Poll Telegram with `getUpdates`.
- Persist received Telegram updates.
- Start a Squid Mesh workflow for `/start` and `/stop`.
- Persist Telegram chats and subscription status.
- Send and record Telegram confirmation messages.

Digest generation is a later slice. For now, verify integration by sending
`/start` or `/stop` to the bot, checking that Telegram receives the confirmation
reply, and checking the database rows described below.

## Create A Telegram Bot

1. Open Telegram and message `@BotFather`.
2. Send `/newbot`.
3. Follow BotFather's prompts for the display name and username.
4. Copy the bot token into a local environment file. Do not commit it.
5. Optional: send `/setcommands` to BotFather and configure:

   ```text
   start - Subscribe to Hacker News digests
   stop - Stop Hacker News digests
   ```

This app uses polling in dev. If the bot was previously configured with a
webhook, remove it before using polling:

```sh
curl -sS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/deleteWebhook"
```

## Local Environment

Create a local env file from the example:

```sh
cp .env.example .env.local
```

Fill in the Telegram token:

```sh
TELEGRAM_BOT_TOKEN=replace-with-bot-token
TELEGRAM_POLLING_ENABLED=true
```

`.env.local` is ignored by git. Load it before running Mix commands that should
talk to Telegram:

```sh
set -a
source .env.local
set +a
```

## Database Setup

The app expects Postgres to be reachable with the values from `config/dev.exs`.
The defaults are:

```text
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_HOST=localhost
POSTGRES_DB=hn_telegram_digest_dev
```

Create and migrate the database:

```sh
mix setup
```

If the database already exists, just run:

```sh
mix ecto.migrate
```

## Run The Bot In Dev

Start the OTP app with polling enabled:

```sh
mix run --no-halt
```

Send `/start` to the bot in Telegram. The poller should persist the update,
start the subscription workflow, store the chat subscription as active, and send
a confirmation reply.

Check the database:

```sh
psql "$DATABASE_URL" -c "select chat_id, type, username from telegram_chats;"
psql "$DATABASE_URL" -c "select chat_id, status, subscribed_at, unsubscribed_at from telegram_subscriptions;"
psql "$DATABASE_URL" -c "select idempotency_key, chat_id, status, sent_at from telegram_message_deliveries;"
```

If you are using the default local Postgres settings instead of `DATABASE_URL`,
connect to `hn_telegram_digest_dev` directly:

```sh
psql -d hn_telegram_digest_dev -c "select chat_id, status, subscribed_at, unsubscribed_at from telegram_subscriptions;"
psql -d hn_telegram_digest_dev -c "select idempotency_key, chat_id, status, sent_at from telegram_message_deliveries;"
```

Send `/stop` to the bot and rerun the subscription query. The row should move to
`inactive`, set `unsubscribed_at`, and produce an unsubscribe confirmation.

## Tests

Run the test suite:

```sh
mix test
```

The workflow tests cover:

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
- Outbound confirmations are durable through `telegram_message_deliveries`.
  Successful duplicate step attempts skip the Telegram API call; failed sends
  are recorded for retry. Stale in-flight sends move to `unknown` for operator
  inspection instead of retrying automatically, because Telegram may already
  have accepted the message.

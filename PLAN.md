# Hacker News Telegram Digest Bot Plan

## Purpose

Build a small Phoenix side project that dogfoods Squid Mesh in a realistic host
application without prematurely adding speculative runtime features to Squid
Mesh itself.

The app is a Telegram bot that fetches Hacker News RSS content, deduplicates
items, formats a digest, and sends it to subscribed Telegram chats.

## Why This Project

This project is intentionally small but operationally real. It should exercise:

- a host-owned Ecto repo
- a host-owned Oban instance
- Squid Mesh migrations inside a normal Phoenix app
- scheduled workflow starts
- external HTTP calls
- retryable Telegram delivery
- persisted deduplication
- user subscription commands
- cancellation or disabled-subscription paths
- operator inspection through `SquidMesh.inspect_run/2`
- operator diagnostics through `SquidMesh.explain_run/2`

## First Workflow

```elixir
workflow :deliver_hn_digest do
  step :fetch_feed, FetchHackerNewsRss
  step :dedupe_items, DedupeItems, after: :fetch_feed
  step :rank_items, RankItems, after: :dedupe_items
  step :format_message, FormatTelegramDigest, after: :rank_items
  step :send_digest, SendTelegramMessage, after: :format_message
end
```

## Supporting Workflows

```elixir
workflow :handle_subscription_command do
  step :parse_command, ParseTelegramCommand
  step :update_preferences, UpdatePreferences, after: :parse_command
  step :confirm_change, SendTelegramMessage, after: :update_preferences
end
```

Potential commands:

- `/start`
- `/stop`
- `/digest`
- `/topics`
- `/limit`

## Reliability Contract To Test

The project should validate whether Squid Mesh feels reliable without adding a
custom heartbeat or lease protocol yet.

Current assumptions:

- Oban owns job durability and redelivery.
- Squid Mesh persists workflow runs, step runs, and attempts.
- Duplicate deliveries are guarded at the workflow layer.
- External side effects use idempotency keys or duplicate-safe behavior.
- Long waits use scheduled continuation rather than sleeping workers.
- Long-running in-process steps are avoided in the first version.

Heartbeat or leases may become useful later for long-running worker-held steps,
but this side project should first test whether bounded workflow steps plus
idempotent side effects are enough.

## Implementation Slices

1. Create a Phoenix app with Postgres, Oban, and Squid Mesh installed.
2. Add Telegram webhook or polling ingestion.
3. Persist Telegram chats and subscriptions.
4. Implement the HN RSS fetch step.
5. Implement item deduplication per chat.
6. Implement digest formatting.
7. Implement Telegram send with retry-safe behavior.
8. Add a scheduled digest trigger.
9. Add `/start` and `/stop` command workflows.
10. Add an operator page or task that surfaces `inspect_run/2` and
    `explain_run/2`.
11. Restart the app while runs are active and record behavior.
12. Feed real API, docs, and runtime gaps back into Squid Mesh issues.

## Future Jido Experiments

After the deterministic version works, try Jido-powered agentic steps:

- summarize stories
- classify topics
- personalize rankings
- explain why a story was included

The goal is to let real usage determine whether Squid Mesh should add an
`agent_step` DSL and how much Jido runtime integration belongs inside it.

## Success Criteria

- A user can subscribe to HN digests from Telegram.
- Scheduled digests are delivered without duplicate stories.
- Failed Telegram sends retry without sending duplicate digest entries.
- A disabled subscription stops future delivery.
- An operator can inspect why a digest did or did not send.
- At least one restart/deploy-style test runs while workflow state is active.
- Any Squid Mesh improvements discovered are captured as concrete issues.

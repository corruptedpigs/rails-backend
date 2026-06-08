# cpigs-news-bot — Implementation Plan

## Overview

An automated pipeline that fetches corruption-related news from NewsAPI.org, filters for relevance and novelty using an AI layer, and delivers notifications to Telegram channels — with language-based routing and an audited article history to prevent duplicate or stale alerts.

Each Telegram notification links to a branded preview page hosted at `https://cpigs.to/<public_id>`. That page renders the article snippet in the corruptedpigs.com visual style and forwards the reader to the original source.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Sidekiq Cron Job                         │
│                  (runs every N minutes)                     │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                  1. News Fetcher                            │
│         NewsAPI.org — one query per language                │
│         keywords: "corruption", "corrupção", etc.           │
└───────────────────────┬─────────────────────────────────────┘
                        │  raw articles
                        ▼
┌─────────────────────────────────────────────────────────────┐
│               2. Persistence Layer                          │
│         Upsert Articles into DB (url as unique key)         │
│         Generate public_id (nanoid) on first insert         │
│         Track with `audited` gem (last N versions)          │
└───────────────────────┬─────────────────────────────────────┘
                        │  new + updated articles
                        ▼
┌─────────────────────────────────────────────────────────────┐
│             3. Relevance & Dedup Filter (AI)               │
│   - Score relevance (is it really about corruption?)        │
│   - Cluster by story (same event = same story)              │
│   - Decide: skip / notify-new / replace-previous-alert      │
└───────────────────────┬─────────────────────────────────────┘
                        │  approved articles
                        ▼
┌─────────────────────────────────────────────────────────────┐
│               4. Telegram Notifier                          │
│   - Route by language → channel (configurable)              │
│   - Link = https://cpigs.to/<public_id>                     │
│   - Edit previous message if "replace" decision             │
└─────────────────────────────────────────────────────────────┘
                        │  reader clicks link
                        ▼
┌─────────────────────────────────────────────────────────────┐
│           5. Article Preview Page (cpigs.to)               │
│   - Branded page in corruptedpigs.com visual style          │
│   - Title, description, source, language, date              │
│   - OG meta tags for Telegram link preview card             │
│   - "Read full article →" button → original source URL      │
└─────────────────────────────────────────────────────────────┘
```

---

## Stack

| Layer | Technology |
|---|---|
| Web framework | Ruby on Rails 8.1.3 |
| Background jobs | Sidekiq + Redis |
| Scheduler | sidekiq-cron |
| Database | PostgreSQL |
| Audit trail | `audited` gem |
| AI filtering | OpenAI API (gpt-4o-mini — cheapest tier) |
| News source | NewsAPI.org (free tier) |
| Notifications | Telegram Bot API |
| Preview page | Rails controller + ERB (same app, custom domain) |
| Short domain | `cpigs.to` → same VPS/Fly app, custom domain config |

**Why Rails + Sidekiq over GitHub Actions:**
- Stateful — the DB tracks what was already sent, making deduplication reliable across runs.
- Telegram "edit message" requires storing the `message_id`, which needs persistence.
- Easier to add a simple admin UI later (ActiveAdmin / Hotwire).
- Sidekiq-cron is more flexible than cron syntax in YAML workflows.

GitHub Actions remains a valid option for a completely stateless, DB-free version, but loses the deduplication and replace-message capabilities.

---

## Data Models

### `Article`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | PK |
| `public_id` | string | 8-char lowercase alphanumeric (`SecureRandom.alphanumeric(8).downcase`), unique — used in `cpigs.to/<public_id>` |
| `external_id` | string | NewsAPI article URL (unique index) |
| `title` | string | |
| `description` | text | |
| `content` | text | truncated by NewsAPI on free tier |
| `url` | string | original source URL |
| `source_name` | string | |
| `author` | string | |
| `language` | string | `"pt"`, `"en"`, … |
| `published_at` | datetime | |
| `relevance_score` | float | 0.0–1.0 set by AI layer |
| `story_key` | string | AI-assigned cluster identifier |
| `status` | string | `pending`, `approved`, `rejected`, `superseded` |
| `notified_at` | datetime | when Telegram message was sent |
| `telegram_message_id` | bigint | for editing previous messages |
| `telegram_channel` | string | which channel received this |
| `preview_views` | integer | optional click counter |
| `created_at` / `updated_at` | datetime | |

The `audited` gem is enabled on this model, keeping the last **10 versions** per record so we can inspect what changed between NewsAPI fetches.

### `ChannelConfig` — YAML only

Language → Telegram channel mapping lives in `config/news_bot.yml` (no separate DB model or `channels.yml`):

```yaml
# config/news_bot.yml (languages section)
languages:
  - code: pt
    keywords: "corrupção OR suborno OR desvio de dinheiro público"
    telegram_chat_id: "@cpigs_pt"
  - code: en
    keywords: "corruption OR bribery OR embezzlement"
    telegram_chat_id: "@cpigs_en"
```

### `StoryCluster` (optional, for richer dedup)

If the AI story-clustering needs to be inspectable:

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | PK |
| `key` | string | unique slug |
| `summary` | text | AI-generated one-liner |
| `first_seen_at` | datetime | |
| `last_updated_at` | datetime | |

---

## Key Components

### 1. News Fetcher (`NewsFetcherJob`)

- Reads configured languages from `config/channels.yml`.
- For each language, calls NewsAPI `/v2/everything` with:
  - `q`: configurable keyword list (e.g. `"corruption OR corrupção OR suborno"`)
  - `language`: `pt` / `en`
  - `from`: today's date (free tier supports up to 1 month back)
  - `sortBy`: `publishedAt`
  - `pageSize`: 100 (free tier max)
- Upserts each article by `url` (external_id).
- Enqueues `ArticleFilterJob` for each new/updated article.

**Free tier limits:** 100 requests/day, results up to 1 month old. With 2 languages and hourly runs, this is well within the 100/day cap.

### 2. Relevance & Dedup Filter (`ArticleFilterJob` + `AiFilter` service)

Runs per article. `ArticleFilterJob` delegates AI calls to `app/services/ai_filter.rb`, which uses OpenAI (or any LLM with an OpenAI-compatible API) to:

**Step A — Relevance check**

Prompt asks: "Is this article genuinely about corruption, bribery, fraud, or related misconduct by a public figure or institution? Score 0.0 to 1.0."

- `score >= 0.7` → proceed
- `score < 0.7` → mark `rejected`, stop

**Step B — Story clustering**

Prompt provides the article headline + description plus the titles of recent `approved` articles (last 7 days). Asks: "Does this article report on the same underlying event as any of the listed articles? If yes, return its story_key. If no, generate a short slug for the new story."

- Same story found → compare completeness; if new article is more detailed, mark old as `superseded` and schedule a Telegram message edit.
- New story → mark `approved`, enqueue `TelegramNotifierJob`.

**Cost estimate (gpt-4o-mini):** ~300 tokens per article × $0.15/1M input tokens ≈ negligible for tens of articles/day.

### 3. Telegram Notifier (`TelegramNotifierJob`)

- Reads `telegram_channel` from the article's language config.
- Formats message using the `cpigs.to` short URL:

```
🐷 *{title}*

{description}

🗞 {source_name} · {published_at}
🔗 https://cpigs.to/{public_id}
```

- Sends via `sendMessage` (Bot API) with `parse_mode: "MarkdownV2"` (default in `TelegramClient`).
- Stores returned `message_id` on the article record.
- For `superseded` replacements: calls `editMessageText` using the old article's `telegram_message_id`.

> **Why a short URL instead of the direct source link?**
> Telegram renders an inline link preview using OG tags. By routing through `cpigs.to` we control the preview card (title, image, description) and can track click counts. The original article URL is still one tap away on the preview page.

### 4. Article Preview Page (`ArticlesController#preview`)

Served at `GET https://cpigs.to/:public_id` by the same Rails app with `cpigs.to` as a custom domain.

#### Visual style

Mirrors the corruptedpigs.com prototype (`cpigs-game-prototype`):

| Element | Value |
|---|---|
| Background | `hsl(270 59% 10%)` — very dark purple |
| Primary accent | `#FF33BB` — neon pink (glows, borders, CTA button) |
| Secondary accent | `#F4B625` — gold (source name, date) |
| Heading font | Russo One (Google Fonts) |
| Display font | Bangers (Google Fonts) |
| Body font | Inter |
| Background effects | noise overlay (5% opacity SVG), scanline animation, two glowing blur orbs, perspective grid lines |

#### Page layout (single card, centered)

```
┌──────────────────────────────────────────┐
│  [noise + scanline + orb bg effects]     │
│                                          │
│  ╔════════════════════════════════════╗  │
│  ║  🐷 CORRUPTED PIGS  [lang badge]  ║  │
│  ╠════════════════════════════════════╣  │
│  ║                                    ║  │
│  ║  Article Title (Russo One, lg)     ║  │
│  ║                                    ║  │
│  ║  Description paragraph (Inter)     ║  │
│  ║                                    ║  │
│  ║  🗞 Source Name  ·  2026-06-04     ║  │
│  ║     (gold color)                   ║  │
│  ║                                    ║  │
│  ║  [ Read full article → ]           ║  │
│  ║    (pink neon CTA button)          ║  │
│  ╚════════════════════════════════════╝  │
│                                          │
│  cpigs.to  ·  corruptedpigs.com          │
└──────────────────────────────────────────┘
```

#### OG / Twitter meta tags (for Telegram link preview)

```html
<meta property="og:title"       content="{title}" />
<meta property="og:description" content="{description}" />
<meta property="og:url"         content="https://cpigs.to/{public_id}" />
<meta property="og:site_name"   content="Corrupted Pigs" />
<meta property="og:type"        content="article" />
<meta property="article:published_time" content="{published_at iso8601}" />
<!-- Optional: og:image pointing to a default branded banner -->
```

Telegram's `linkPreview` will render these tags as a rich card below the message text.

#### Controller

```ruby
class ArticlesController < ApplicationController
  def preview
    @article = Article.find_by!(public_id: params[:public_id])
    @article.increment!(:preview_views)
    expires_in 10.minutes, public: true
  end
end
```

#### Routes

```ruby
# config/routes.rb
root to: redirect("https://corruptedpigs.com")
get "/:public_id", to: "articles#preview", as: :article_preview,
    constraints: { public_id: /[a-z0-9]{8}/ }
```

The `public_id` constraint prevents the route from swallowing Rails reserved paths like `/rails/` or `/up`.

#### `public_id` generation

Generated at upsert time using Ruby's `SecureRandom`:

```ruby
# app/models/article.rb
before_create :assign_public_id

private

def assign_public_id
  self.public_id ||= SecureRandom.alphanumeric(8).downcase
end
```

Unique index on `public_id` in the migration.

### 5. Configuration

All tuneable values live in `config/news_bot.yml` (loaded via a `Rails.application.config_for`):

```ruby
# config/news_bot.yml — all tuneable values, loaded via Rails.application.config_for(:news_bot)
default: &default
  fetch_interval_minutes: 60
  lookback_days: 1
  relevance_threshold: 0.7
  max_audit_versions: 10
  short_url_base: "https://cpigs.to"
  languages:
    - code: pt
      keywords: "corrupção OR suborno OR desvio de dinheiro público"
      telegram_chat_id: "@cpigs_pt"
    - code: en
      keywords: "corruption OR bribery OR embezzlement"
      telegram_chat_id: "@cpigs_en"
```

---

## Sidekiq Cron Schedule

Registered in `config/initializers/sidekiq.rb` inside `config.on(:startup)`:

```ruby
# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.on(:startup) do
    Sidekiq::Cron::Job.load_from_hash(
      "news_fetcher" => {
        "cron"  => ENV.fetch("NEWS_FETCH_CRON", "0 * * * *"),  # every hour, overridable
        "class" => "NewsFetcherJob"
      }
    )
  end
end
```

---

## Deployment Options

### Option A — Small VPS (recommended for always-on)

- Single $4–6/month VPS (e.g. Hetzner CX11, Fly.io free tier).
- Docker Compose: `app` (Rails/Puma), `worker` (Sidekiq), `redis`, `postgres`.
- `.env` for secrets (never committed).

### Option B — GitHub Actions (stateless fallback)

- Scheduled workflow with `schedule: cron`.
- Run a plain Ruby script (no Rails) that calls NewsAPI + Telegram.
- **Loses:** deduplication, message editing, audit trail.
- Suitable only if no VPS is available and dedup is not needed.

---

## Environment Variables / Secrets

| Variable | Description |
|---|---|
| `NEWS_API_KEY` | NewsAPI.org API key |
| `TELEGRAM_BOT_TOKEN` | BotFather token |
| `OPENAI_API_KEY` | For the AI filter layer |
| `DATABASE_URL` | PostgreSQL connection string |
| `REDIS_URL` | Sidekiq Redis |
| `SHORT_URL_BASE` | `https://cpigs.to` (override for local dev) |

---

## Gems

```ruby
# Gemfile (additions to Rails 8.1.3 defaults)
gem "sidekiq",         "~> 7.0"
gem "sidekiq-cron",    "~> 1.12"
gem "connection_pool", "~> 2.4"   # pinned — v3.0 breaks sidekiq 7.x
gem "audited",         "~> 5.0"
gem "faraday",         "~> 2.0"
gem "faraday-retry",   "~> 2.0"
gem "ruby-openai",     "~> 7.0"
```

---

## Implementation Phases

### Phase 1 — Skeleton & Fetch ✅
- [x] Rails app scaffold (`rails new cpigs-news-bot --database=postgresql --skip-action-mailer --skip-action-cable`)
- [x] `Article` model + migration (columns above, including `public_id`)
- [x] `audited` on `Article`
- [x] `config/news_bot.yml` loader
- [x] `NewsApiClient` service (Faraday wrapper)
- [x] `NewsFetcherJob` — fetches + upserts articles
- [x] Sidekiq + sidekiq-cron setup

### Phase 2 — Article Preview Page ✅
- [x] `ArticlesController#preview` with `public_id` lookup
- [x] ERB view with full cpigs visual style (dark purple bg, noise, scanline, orbs, grid, pink/gold accents, Russo One + Bangers fonts)
- [x] OG / Twitter meta tags in layout
- [x] Route with `public_id` constraint
- [x] `preview_views` counter increment
- [x] `root` redirect to `corruptedpigs.com`
- [x] Local smoke test at `http://localhost:3000/<public_id>`

### Phase 3 — Telegram Notifier ✅
- [x] `TelegramClient` service (sendMessage, editMessageText)
- [x] `TelegramNotifierJob` — uses `cpigs.to/<public_id>` as the link
- [x] Channel routing from config
- [ ] Manual trigger task: `rails news_bot:notify_pending`

### Phase 4 — AI Filter ✅
- [x] `ArticleFilterJob`
- [x] `AiFilter` service (relevance scoring + story clustering prompts)
- [x] Relevance scoring prompt
- [x] Story clustering prompt
- [x] `superseded` flow + message edit

### Phase 5 — Hardening ✅
- [x] Rate-limit handling for NewsAPI (429 backoff via faraday-retry)
- [x] Telegram flood-control handling (retry with delay via faraday-retry)
- [x] Dead-letter queue monitoring in Sidekiq UI
- [x] Duplicate URL guard (unique index on `external_id`)
- [x] Unique index on `public_id`
- [x] Basic health-check endpoint (`/up`)

### Phase 6 — Deployment & Domain (in progress)
- [x] Dockerfile + docker-compose.yml (4 services: postgres, redis, app, worker)
- [x] `.env.example`
- [x] Separate entrypoints: `bin/docker-entrypoint` (app) and `bin/worker-entrypoint` (worker)
- [ ] Deploy to VPS or Fly.io
- [ ] Point `cpigs.to` DNS to the same app (A record / CNAME)
- [ ] Add `cpigs.to` as allowed host in `config/environments/production.rb`
- [ ] TLS via Let's Encrypt / Fly's automatic certs
- [ ] Fill in real API keys and smoke test end-to-end (fetch → filter → notify → preview page)

---

## Open Questions / Decisions Needed

1. **AI provider:** OpenAI gpt-4o-mini is the cheapest option with good quality. Alternatively, a local Ollama instance (free, needs GPU/RAM) or Groq free tier could replace it.
2. **Story key persistence:** Simple string slug vs. a `StoryCluster` join model. Start with slug on `Article`, promote to its own model if needed.
3. **"Replace" UX:** Editing the Telegram message silently updates it; alternatively, send a follow-up reply to the original message. The latter is more visible to subscribers.
4. **Admin UI:** Not planned in Phase 1–5. Could add ActiveAdmin or a simple Hotwire dashboard to review rejected/pending articles and see preview_views counts.
5. **Multiple Telegram channels per language:** Config supports a single `chat_id` per language. Could extend to an array if needed.
6. **Preview page image:** The OG `og:image` could be a static branded banner (e.g. a pig illustration from the game) or dynamically generated per article using a headless Chrome screenshot or an image generation service like Satori.
7. **`cpigs.to` domain:** Needs to be registered and pointed at the hosting platform. If not yet registered, `cpigs.news` or a similar short domain would serve the same purpose. The Rails app needs `config.hosts << "cpigs.to"` in production.
8. **Click tracking granularity:** `preview_views` is a simple increment counter. If referrer or per-channel analytics are needed, a separate `ArticleView` event table (or a lightweight analytics tool like Plausible) would be more appropriate.

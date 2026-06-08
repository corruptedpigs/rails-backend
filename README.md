# rails-backend

The Rails monolith powering [corruptedpigs.com](https://corruptedpigs.com). It combines two concerns:

1. **Game backend** — REST API + Action Cable WebSockets for the CorruptedPigs NFT card game (matchmaking, move validation, result resolution, blockchain notification).
2. **News pipeline** — scheduled fetching of corruption-related news from NewsAPI, AI-based relevance filtering, story deduplication, and Telegram channel posting.

---

## Stack

| Layer | Technology |
|---|---|
| Runtime | Ruby 3.3.4 / Rails 8.1 |
| Database | PostgreSQL 16 |
| Job queue | Sidekiq 7 (Redis-backed) |
| Scheduler | sidekiq-cron (`config/schedule.yml`) |
| Real-time | Action Cable (WebSockets) |
| AI filtering | OpenAI GPT-4o-mini (optional) |

---

## Services

### Game API (`/api/v1/`)

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/health` | Health check |
| `GET` | `/api/v1/players/:wallet_address/nonce` | SIWE nonce for wallet auth |
| `GET` | `/api/v1/players/:wallet_address` | Player profile |
| `POST` | `/api/v1/matchmaking` | Join or create a game session |
| `GET` | `/api/v1/game_sessions/:id` | Session state |
| `POST` | `/api/v1/game_sessions/:id/moves` | Submit a move |

WebSocket endpoint: `GET /cable`

### News pipeline

Runs every 30 minutes via Sidekiq-cron (96 requests/day across 2 languages — within NewsAPI free tier). Flow:

```
NewsFetcherJob → ArticleFilterJob → TelegramNotifierJob
                      ↓
             AiFilter (GPT-4o-mini)
             or KeywordFilter (fallback)
```

Approved articles are posted to the configured Telegram channel and accessible at `/:public_id` (8-char short URL for Telegram link previews).

---

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | yes | PostgreSQL connection string |
| `REDIS_URL` | yes | Redis connection string (default: `redis://localhost:6379/0`) |
| `RAILS_MASTER_KEY` | yes | Decrypts `config/credentials.yml.enc` |
| `NEWS_API_KEY` | yes | [newsapi.org](https://newsapi.org) API key |
| `TELEGRAM_BOT_TOKEN` | yes | Telegram Bot API token |
| `OPENAI_API_KEY` | no | GPT-4o-mini for relevance scoring; falls back to keyword filter if absent |
| `GAME_RESULT_API_URL` | yes | Polygon-side endpoint for posting game results |
| `GAME_RESULT_API_KEY` | yes | Auth key for the game result API |
| `ALLOWED_ORIGINS` | no | CORS origins (default: `http://localhost:3000`) |

---

## Development setup

**Prerequisites:** Docker + Docker Compose.

```bash
cp .env.example .env   # fill in API keys

docker compose up
```

This starts PostgreSQL, Redis, the Rails server (`localhost:3000`), and the Sidekiq worker.

The database is created and migrated automatically on first boot (`db:prepare`).

**Sidekiq dashboard:** [http://localhost:3000/sidekiq](http://localhost:3000/sidekiq) (development only)

### Without Docker

```bash
bundle install
bin/rails db:prepare
bin/rails server           # web process
bundle exec sidekiq        # worker process (separate terminal)
```

---

## Configuration

### News pipeline

`config/news_bot.yml` controls language/keyword pairs, relevance threshold, and fetch interval:

```yaml
languages:
  - code: "pt"
    keywords: "corrupção OR suborno OR fraude ..."
    telegram_chat_id: "@your_channel"
  - code: "en"
    keywords: "corruption OR bribery OR fraud ..."
    telegram_chat_id: "@your_channel"
relevance_threshold: 0.7   # 0.0–1.0; articles below this score are rejected
fetch_interval_minutes: 30 # must match cron in config/schedule.yml
```

If `OPENAI_API_KEY` is not set, a keyword-based scorer is used instead (no external calls, lower precision).

### Cron schedule

Defined in `config/schedule.yml`, loaded automatically by sidekiq-cron on startup.

**Budget note:** with N languages configured, every cron run costs N NewsAPI requests. Adjust the interval to stay under 100 req/day:

| Languages | Max runs/day | Minimum interval |
|---|---|---|
| 2 | 50 | `*/30 * * * *` |
| 3 | 33 | `*/45 * * * *` |
| 4 | 25 | `0 * * * *` |

---

## Database

```bash
bin/rails db:migrate          # run pending migrations
bin/rails db:migrate:status   # check migration state
```

Key tables: `articles`, `audits`, `players`, `game_sessions`, `moves`, `game_results`.

---

## Deployment

The app is deployed via Kamal. See `config/deploy.yml` for host and registry configuration.

```bash
kamal deploy
kamal logs
kamal app exec 'bin/rails console'
```

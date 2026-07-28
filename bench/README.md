# Engine Benchmarking (`mix benchmark`)

Headless bot-vs-bot benchmarking for UBI engines, built on the same match/game/engine
infrastructure the website uses. Two engine binaries (or one binary with two different
option sets) play an N-game match; the harness reports score, Elo difference with a 95%
confidence interval, likelihood of superiority, and optional SPRT early stopping.

## Requirements

- The dev database running (`mix ecto.setup` done) — matches and games are persisted
  through the normal schemas, so benchmark games are replayable in the web UI.
- Engine binaries speaking UBI (see `UBI.md`), referenced by filesystem path.
  The engine repo itself is never touched.

## Usage

```bash
mix benchmark --engine-a ../bughouse-engine/target/release/bughouse_engine \
              --engine-b ../bughouse-engine/target/release/bughouse_engine \
              --games 4 --time-control 60000
```

Parameter-sweep / feature A/B (same binary, different options):

```bash
mix benchmark --engine-a ./baseline_engine --engine-b ./baseline_engine \
              --option-b QsCheckDropDepth=0 \
              --name-a baseline --name-b qs-check-off \
              --games 200 --parallel 2 --sprt "elo0=0,elo1=10"
```

### Flags

| Flag | Default | Meaning |
|---|---|---|
| `--engine-a PATH` | required | Engine A binary |
| `--engine-b PATH` | required | Engine B binary (may equal `--engine-a`) |
| `--games N` | 20 | Number of games (1–1000) |
| `--time-control MS` | 60000 | Per-player clock in milliseconds |
| `--option-a Name=Val` | — | UBI `setoption` for engine A (repeatable) |
| `--option-b Name=Val` | — | UBI `setoption` for engine B (repeatable) |
| `--parallel N` | 1 | Concurrent games (1–10; each game uses 2 engine processes) |
| `--output-dir PATH` | `bench_results` | Where results and logs are written |
| `--name-a`, `--name-b` | binary basename | Labels used in reports and `opponent` metadata |
| `--sprt "elo0=0,elo1=10,alpha=0.05,beta=0.05"` | off | SPRT early stopping (all keys optional) |
| `--config PATH` | — | JSON config file; CLI flags override its values |

A config file uses the same keys as the spec struct:

```json
{
  "engine_a": "/path/to/engine",
  "engine_b": "/path/to/engine",
  "games": 200,
  "time_control_ms": 60000,
  "parallel": 2,
  "options_b": {"QsCheckDropDepth": "0"},
  "sprt": {"elo0": 0, "elo1": 10}
}
```

## Output

Everything for one run lands in `<output-dir>/<match_id>/`:

- `results.json` — the full report, **rewritten atomically after every game**, so it is
  always current and safe to inspect (or `Ctrl-C` the run) at any time.
- `<timestamp>_<game_id>_<bot>.log` — one log per engine process per game, written by
  the engine itself via `--log-file`. Contains the engine's `=== GAME START/END ===`
  and `MOVE ...` telemetry. The UBI `metadata` keys (`match_id`, `game_number`,
  `opponent`, `position`, `time_control`, `total_games`, and `game_result` at game end)
  appear in these logs, which is how engine-side telemetry is joined to website-side
  results.

`results.json` schema (v1):

- `status` — `running` | `completed` | `cancelled` | `stopped_sprt`
- `spec` — the resolved run spec (engines, names, games, tc, options, sprt)
- `score` — `games_played`, `wins_a`, `wins_b`, `draws`, `aborted`, `score_a`, `score_a_pct`
- `stats` — `elo_diff`, `elo_ci95` (`[low, high]` or null), `los`, `significant`,
  `significance` (sentence), `sprt` (`llr`/`lower`/`upper`/`decision` or null)
- `games[]` — `game_number`, `game_id`, `invite_code`, `result` (`bot_a_win`/`bot_b_win`/`draw`),
  `winner` (`a`/`b`/`draw`), `termination`, `move_count`, `bot_a_team`, `finished_at`

## Fairness guarantees

- **Seat alternation**: odd games seat engine A as team 1 (white on board 1),
  even games as team 2, so any board/seat advantage cancels over the match.
- **Identical clocks**: both teams get the same `--time-control`; clocks are enforced
  server-side by the game server, never by the engines.
- **Fresh engine processes**: every game spawns new engine processes with the full
  `ubi` → `setoption`/`metadata` → `ubinewgame` → `isready` handshake — no state leaks
  between games.
- **Same host, same wrapper**: both engines run through the identical
  `BotEngine.Server` code path the website uses.

## Failure semantics

| `termination` | Meaning | Counted in stats? |
|---|---|---|
| `checkmate` | Normal decisive finish | yes |
| `timeout` | Flag fell — includes engines that stall (illegal move, no `bestmove`) | yes |
| `forfeit_crash` | Engine OS process died mid-game → its team resigns immediately | yes (loss for the crashed side) |
| `aborted` | Infrastructure failure (game server died twice) | **no** — listed but excluded |

A failed game never kills the match: game-server crashes are retried once (keeping the
game number, so seat parity is preserved), then recorded as `aborted`. All engine
processes are reaped after each game and on cancellation — no orphans.

## Statistics

For engine A's counts (w, d, l), with score fraction `p = (w + d/2) / n`:

- **Elo difference**: `-400·log10(1/p − 1)` (clamped away from 0/1)
- **95% CI**: normal approximation on `p` (trinomial per-game variance) mapped through
  the Elo curve; `null` until there is variance (≥2 games, not all draws)
- **LOS**: `Φ((p − 0.5)/se)` — probability A is genuinely stronger
- **SPRT**: GSPRT approximation of the LLR between H0 (`elo0`) and H1 (`elo1`), with
  bounds `log(β/(1−α))` and `log((1−β)/α)`. When a decision is reached before
  `--games`, the match stops early with status `stopped_sprt`.

Caveat: the trinomial model treats games as independent and ignores correlation within
seat-alternated game pairs; a pentanomial model (as used by fishtest) would give
slightly tighter intervals. TODO if benchmark precision ever becomes the bottleneck.

## How it works

`mix benchmark` upserts two persistent bot records (`bench_a`, `bench_b` — hidden from
the public bot list) pointing at the given binaries/options, creates a `BotMatch`, and
runs it through the same `BotMatchServer` → `BughouseGameServer` → `BotEngine.Server`
pipeline as UI-created matches. The task follows the match over PubSub and rewrites
`results.json` after every game. Match results also land in the `bot_matches` /
`bot_match_games` tables and are visible at `/matches` in the web UI.

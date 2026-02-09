# Bughouse Engine Integration

A living reference document for the design, protocol, and phased implementation plan for bot players and the Bughouse chess engine.

---

## Table of Contents

1. [Vision](#vision)
2. [Architecture Overview](#architecture-overview)
3. [Bot Types & Registration](#bot-types--registration)
4. [UBI — Universal Bughouse Interface](#ubi--universal-bughouse-interface)
5. [Integration with Existing Game Loop](#integration-with-existing-game-loop)
6. [Evaluation & Heuristics](#evaluation--heuristics)
7. [Rust Engine Architecture](#rust-engine-architecture)
8. [Phased Implementation Plan](#phased-implementation-plan)
9. [Bot-Only Games & Rankings](#bot-only-games--rankings)
10. [Open Questions & Decisions](#open-questions--decisions)

---

## Vision

Bughouse is one of the most interesting domains for engine development because the heuristic space is dramatically richer than standard chess. Captured pieces return to play via drops, both boards run simultaneously, clocks are a first-class strategic variable, and teammates must coordinate across boards they don't directly control. No open-source bughouse engine exists today that seriously tackles these dynamics.

The goal is threefold:

1. **Build a standardized bot protocol (UBI)** so that anyone — internal or external — can write a bughouse engine and connect it to this platform, similar to how UCI works for standard chess engines.
2. **Write a Rust-based bughouse engine** that explores move-tree search, parallel evaluation, and bughouse-specific heuristics as a learning project in systems programming.
3. **Create an ecosystem** where bots can fill lobby slots alongside humans, play each other in bot-only games, and have their own rankings — making the platform a testbed for engine development.

---

## Architecture Overview

The bot system is layered. Each layer has a clear boundary and can be developed and tested independently.

```
┌─────────────────────────────────────────────────────────────┐
│  LAYER 4: ENGINE HEURISTICS  (Rust)                         │
│  Search trees, scoring functions, time management          │
├─────────────────────────────────────────────────────────────┤
│  LAYER 3: UBI PROTOCOL  (Rust stdin/stdout + spec)          │
│  Universal Bughouse Interface — the UCI equivalent           │
├─────────────────────────────────────────────────────────────┤
│  LAYER 2: BOT ADAPTER  (Elixir)                             │
│  Internal: Erlang Port wrapping Rust binary                 │
│  External: Phoenix Channel for remote bot servers           │
├─────────────────────────────────────────────────────────────┤
│  LAYER 1: BOT REGISTRY + LOBBY  (Elixir)                    │
│  Bot schema, health checks, lobby UI integration            │
├─────────────────────────────────────────────────────────────┤
│  LAYER 0: EXISTING GAME LOOP  (already built)              │
│  BughouseGameServer → binbo_bughouse → PubSub               │
└─────────────────────────────────────────────────────────────┘
```

### Key Principle: Bots Are Invisible to the Game Loop

`BughouseGameServer` does not need to know a player is a bot. A bot adapter subscribes to the same PubSub topic as a LiveView, receives the same `{:game_state_update, state}` broadcasts, and submits moves via the same `Games.make_game_move/3` and `Games.drop_game_piece/4` functions a human does. The game server treats all four positions identically.

---

## Bot Types & Registration

### Three Player Types

| Type | Identity | Auth | Controls | Lives on |
|---|---|---|---|---|
| Guest | Session-scoped UUID | Cookie | 1 position | Browser |
| Authenticated | Persistent UUID | Google OAuth | 1 position | Browser |
| Bot | Persistent UUID | Registered bot record | 1 or 2 positions | Server(s) |

### Bot Schema (implemented)

The `players` table has an `is_bot` flag. The `bots` table is a 1:1 extension of
`players` that holds bot-specific operational and rating fields. The bot's display
name and username live on the `player` record — no duplication. Aggregate win/loss
stats also live on `player`; the bot table owns only the per-mode ratings, because
single-position and dual-position games are separate rating pools.

```elixir
# players table: added is_bot boolean (default: false)
# Player.has_one :bot, Bot

# bots table (1:1 with players via unique index on player_id)
schema "bots" do
  belongs_to :player, Player                    # 1:1 — identity, display_name, username

  field :bot_type, :string                      # "internal" | "external"
  field :health_url, :string                    # HTTP health endpoint (external bots only, required)
  field :status, :string, default: "offline"   # "online" | "offline" | "in_game"
  field :supported_modes, :string              # "single" | "dual" | "both"

  field :single_rating, :integer, default: 1200  # rating in single-position games
  field :dual_rating, :integer, default: 1200    # rating in dual-position games

  field :config, :map, default: %{}            # engine config passed via UBI (depth, time, etc.)

  timestamps()
end
```

**Validations:**
- `bot_type` must be `"internal"` or `"external"`
- `status` must be `"online"`, `"offline"`, or `"in_game"`
- `supported_modes` must be `"single"`, `"dual"`, or `"both"`
- `health_url` is required when `bot_type` is `"external"`
- `player_id` is unique (enforced by DB index + Ecto constraint)

### Health Checks

Before a bot is placed into a game position, the system pings its health endpoint:

- **External bots:** HTTP GET to `health_url` — must return `200` within 2 seconds or the bot is marked offline and removed from the lobby.
- **Internal bots:** Check that the Port process (wrapping the Rust binary) is alive. If the binary has crashed, restart it or mark offline.

Health checks run:
1. When the lobby loads (to populate the available bot list)
2. Before `start_game` is called (revalidate all bots in the lobby)
3. Periodically in the background (every 30s) to update bot status in real time

### Dual-Position Bots

A single bot can fill **both positions on one team** (e.g., board_1_white AND board_2_black). Regular human players cannot do this. This is the mode where coordination is most interesting — the engine has full information about both boards and can plan across them.

In the lobby, a dual-position bot occupies two seats. The lobby UI should make this visually clear (e.g., both seats show the same bot name with a "linked" indicator).

From the game loop's perspective, the bot adapter simply calls `make_game_move` twice — once for each position — whenever each position's turn arrives. The engine receives both board states and can internally coordinate.

---

## UBI — Universal Bughouse Interface

UBI is modeled after UCI but extended for the dimensions that make bughouse unique: two boards, four clocks, reserves, and teammate coordination signals.

> **Authoritative spec:** The full UBI v0.1 specification lives in [`bughouse-engine/docs/UBI.md`](../bughouse-engine/docs/UBI.md). This section is a summary for integration context. When in doubt, `UBI.md` wins.

### Why a Protocol?

UCI's power is its simplicity. An engine is a black box: you give it a position, it gives you a move. The protocol is language-agnostic and transport-agnostic. UBI does the same for bughouse, which means:

- Engines can be written in any language (Rust, C++, Python, Go — whatever)
- Engines can be hosted anywhere (same server, remote VPS, cloud function)
- The protocol is the only contract between the platform and the engine

### Protocol Summary

Communication is line-based, newline-delimited, plain text. The server writes to the engine's stdin. The engine writes to the server's stdout. (For external bots over WebSocket, the same messages are sent as text frames.)

Positions use **BFEN** (Bughouse FEN), which embeds reserves directly in the position string using bracket notation. See [`bughouse-engine/docs/BFEN.md`](../bughouse-engine/docs/BFEN.md) for the full spec.

#### Server → Engine

```
# ── Handshake ─────────────────────────────────────────────────
ubi                                         # Engine must reply: id name/author, then ubiok
ubinewgame                                  # Clear state for a new game
isready                                     # Engine must reply: readyok

# ── Position (uses BFEN — reserves embedded in brackets) ──────
# Reserves are part of the BFEN string, not separate fields.
# The engine is position-agnostic — it doesn't know its color or team.
#
position board <A|B> bfen <bfenstring> [moves <move1> ... <moveN>]
position board A startpos                   # Shorthand for starting position

# ── Clock Times (all four, sent before "go") ──────────────────
clock white_A <ms>
clock black_A <ms>
clock white_B <ms>
clock black_B <ms>

# ── Go (Think & Return a Move) ────────────────────────────────
go board <A|B> [movetime <ms>] [wtime <ms> btime <ms>] [depth <n>] [infinite]

# ── Stop ──────────────────────────────────────────────────────
stop [board <A|B>]                          # Stop search (all or specific board)

# ── Team Messages (forwarded from partner engine) ─────────────
partnermsg need <piece> [urgency <low|medium|high>]
partnermsg stall [duration <moves>]
partnermsg play_fast [reason <time|pressure>]
partnermsg threat <low|medium|high|critical>

# ── Quit ──────────────────────────────────────────────────────
quit
```

#### Engine → Server

```
# ── Identification (during handshake) ─────────────────────────
id name <string>
id author <string>
ubiok

# ── Best Move ─────────────────────────────────────────────────
#   Standard move:   e2e4
#   Promotion:       e7e8q
#   Drop:            p@e4
#
bestmove board <A|B> <move> [ponder <move>]

# ── Team Messages (sent to partner via server) ────────────────
teammsg need <piece> [urgency <low|medium|high>]
teammsg stall [duration <moves>]
teammsg threat <low|medium|high|critical>
teammsg material <+/-><value>

# ── Info (optional diagnostic output) ─────────────────────────
info board <A|B> depth <n> nodes <n> score cp <n> time <ms> [pv <moves>]

# ── Ready ─────────────────────────────────────────────────────
readyok
```

### Example Session

```
# Handshake
> ubi
< id name BughouseBot 1.0
< id author Viren
< ubiok

> ubinewgame
> isready
< readyok

# Server sets up both boards and clocks, then asks for a move:
> position board A bfen rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR[] w KQkq - 0 1
> position board B bfen rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR[] b KQkq - 0 1
> clock white_A 600000
> clock black_A 600000
> clock white_B 599800
> clock black_B 600000
> go board A movetime 3000

# Engine thinks, outputs info, then returns a move:
< info board A depth 8 nodes 12400 score cp 30 time 850
< bestmove board A e2e4

# Partner engine requests a knight:
> partnermsg need n urgency medium

# Teammate captured a pawn — reserves now in the BFEN brackets:
> position board A bfen rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R[p] w KQkq - 2 3
> position board B bfen rnbqkbnr/ppppp1pp/8/5p2/4P3/8/PPPP1PPP/RNBQKBNR[P] b KQkq - 0 2
> clock white_A 598500
> clock black_A 599200
> clock white_B 598100
> clock black_B 598900
> go board A movetime 2500

# Engine decides to drop the pawn (and signals it needs a bishop):
< teammsg need b urgency high
< info board A depth 6 nodes 8200 score cp 45 time 400
< bestmove board A p@e5
```

### Dual-Control Mode

When an engine controls both positions on a team, the server sends two independent `position` + `go` sequences — one for each board. The engine can maintain shared internal state to coordinate, but each `bestmove` response corresponds to exactly one board. The `teammsg` / `partnermsg` messages are suppressed in dual-control mode since coordination is internal.

---

## Integration with Existing Game Loop

### Where Bots Plug In

Nothing in `BughouseGameServer` changes. The bot adapter is a separate process that acts as a player. Here is the data flow:

```
┌──────────────┐     PubSub      ┌─────────────────┐
│              │ ◄─── broadcast ─│  BughouseGame   │
│  Bot Adapter │                 │  Server         │
│  (GenServer) │ ── make_move ──►│  (GenServer)    │
└──────┬───────┘                 └─────────────────┘
       │ Port stdin/stdout (internal)
       │ or WebSocket (external)
       ▼
┌──────────────┐
│  Engine      │  (Rust binary, or remote server)
│  Process     │
└──────────────┘
```

### Bot Adapter Responsibilities

The adapter is a GenServer that:

1. **Subscribes** to the game's PubSub topic on mount (same topic as LiveView)
2. **Translates** `{:game_state_update, state}` into a UBI `position` command
3. **Determines** if it's this bot's turn (checks `active_clocks` against its position)
4. **Sends** `go` with the correct clock values
5. **Reads** `bestmove` back from the engine
6. **Calls** `Games.make_game_move/3` or `Games.drop_game_piece/4`
7. **Forwards** `request` messages to the teammate's adapter (if applicable)

### State Translation: Game State → UBI Commands

The game state broadcast already contains everything UBI needs. The adapter converts it to BFEN-based `position` and `clock` commands:

```elixir
# What the server broadcasts (from serialize_state_for_client/1):
%{
  board_1_fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR",
  board_2_fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR",
  clocks: %{board_1_white: 600000, board_1_black: 600000, board_2_white: 600000, board_2_black: 600000},
  active_clocks: [:board_1_white, :board_2_white],
  reserves: %{
    board_1_white: %{p: 0, n: 0, b: 0, r: 0, q: 0},
    board_1_black: %{p: 0, n: 0, b: 0, r: 0, q: 0},
    board_2_white: %{p: 0, n: 0, b: 0, r: 0, q: 0},
    board_2_black: %{p: 0, n: 0, b: 0, r: 0, q: 0}
  }
}

# Adapter translates to UBI commands:
#   1. Build BFEN for each board (embed reserves in brackets)
#   2. Send position + clock commands
#
# position board A bfen rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR[<reserves>] w KQkq - 0 1
# position board B bfen rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR[<reserves>] w KQkq - 0 1
# clock white_A 600000
# clock black_A 600000
# clock white_B 600000
# clock black_B 600000
# go board A movetime 3000
```

Note: BFEN embeds reserves directly in the position string using bracket notation (e.g. `[QNPqp]`). Each board's BFEN carries the reserves for the players on that board. The adapter builds the BFEN reserve bracket from the per-position reserve maps. Team mapping for which reserves belong to which board:

- **Board A reserves** = `board_1_white` reserves (white side) + `board_1_black` reserves (black side)
- **Board B reserves** = `board_2_white` reserves (white side) + `board_2_black` reserves (black side)

### Internal vs External Adapter

| Concern | Internal Bot | External Bot |
|---|---|---|
| Transport | Erlang Port (stdin/stdout) | Phoenix Channel (WebSocket) |
| Hosting | Same Fly.io VM | Remote server (any HTTP endpoint) |
| Latency | Sub-millisecond IPC | Network round-trip |
| Health check | Port alive? | HTTP GET health_url |
| UBI framing | One message per line | One message per WebSocket frame |
| Lifecycle | Spawned on game start, stopped on game end | Connects on game start, disconnects on game end |

---

## Evaluation & Heuristics

This is where bughouse gets genuinely interesting from an engine design perspective. Standard chess evaluation is roughly: material + position + king safety. Bughouse breaks every one of those assumptions.

### Why Standard Chess Scoring Breaks Down

| Assumption | Standard Chess | Bughouse |
|---|---|---|
| Captured pieces are gone | ✓ | ✗ — they reappear on the other board |
| Material balance is stable | ✓ | ✗ — reserves are constantly in flux |
| You only play one board | ✓ | ✗ — your scoring must consider the teammate's board |
| Time is uniform | ✓ | ✗ — four independent clocks, stalling is a strategy |
| You control all your pieces | ✓ | ✗ — in single-control mode, you can't move teammate's pieces |

### Bughouse Scoring Components

A bughouse engine's scoring function needs to consider all of the following. Not all need to be implemented at once — this is a progression from simple to complex:

```
score(state) =
    positional_score(my_board)          // piece activity, king safety, pawn structure
  + threat_score(my_board)              // am I threatening mate? how close?
  - threat_score(opponent_board)        // is my opponent threatening mate on my board?
  + reserve_value(my_team_reserves)     // what can I drop? immediate tactical options
  - reserve_value(opp_team_reserves)    // what can THEY drop? threats I must defend
  + teammate_board_value(teammate_board)// how healthy is my partner? (read-only if single-control)
  + time_pressure_score(all_clocks)     // clock differentials — stall or rush?
  + demand_supply_score(state)          // can I get the piece I need? can my teammate?
```

### Strategic Tensions Unique to Bughouse

**1. Stalling vs. Rushing**
If your opponent is low on time and you have plenty, deliberately playing slow, safe moves can win without ever threatening checkmate. Conversely, if YOU are low on time, you need to play fast tactical moves even if they're slightly unsound. The engine must detect which regime it's in and adjust its search accordingly.

**2. Capture Value Is Not Material Value**
Capturing a piece gives your teammate a reserve piece, but it also gives the opponent a piece they captured from you (if you traded). In some positions, *not* capturing is correct because the piece you'd give to the opponent's teammate is more dangerous than the one you'd gain. Evaluation of captures must account for both sides of the transfer.

**3. Piece Requests Create Planning Horizons**
If you need a rook to deliver checkmate but your teammate hasn't captured one yet, the optimal line might be: make a safe neutral move, wait for the capture, then deliver mate. But "waiting" has a cost — your opponent might recognize the threat and defend, or your clock ticks down. The engine needs to search lines that include *anticipated* future drops, not just currently available ones.

**4. Reserve Threats Are Positional, Not Material**
An opponent with three pawns in reserve can drop-check you repeatedly. A queen in reserve can land on a devastating square. Defending against drops is fundamentally different from defending against moves — you're guarding against pieces that can appear *anywhere* on the board. This makes king safety evaluation much more complex than in standard chess.

### Scoring Progression (Build Order)

| Stage | What You Implement | Engine Strength |
|---|---|---|
| 1 | Random legal move | Loses to everything |
| 2 | Greedy: captures > moves, avoids hanging pieces | Barely functional |
| 3 | Material + simple positional tables | Plays recognizable chess |
| 4 | Minimax search (depth 2-3) | Competitive in short games |
| 5 | Alpha-beta pruning + iterative deepening | Strong positional play |
| 6 | Reserve-aware scoring (drop threats + drop opportunities) | Bughouse-aware |
| 7 | Clock-based strategy (stall/rush detection) | Time-smart |
| 8 | Cross-board awareness + piece request coordination | Full bughouse |
| 9 | Parallel search with Rayon | Faster, deeper search |

---

## Rust Engine Architecture

### Why Rust

- **Performance:** Chess engines are search-bound. Rust compiles to native code with zero-cost abstractions — the search loop will be as fast as C++.
- **Parallelism:** Rayon makes data-parallel search over move trees trivial and safe. Exploring the root moves in parallel is the single biggest performance win in chess engines, and Rayon's work-stealing scheduler handles it elegantly.
- **Learning value:** Rust's ownership model forces you to think carefully about state — which is exactly what a search tree needs. The borrow checker will catch bugs that would be silent memory errors in C++.
- **Portability:** The compiled binary is a single static executable. It runs on the same Fly.io VM as Phoenix (internal bot) or on any remote server (external bot). No runtime dependencies.

### Project Structure

```
bughouse-engine/                             # Engine binary (Rust)
├── Cargo.toml                               # Depends on bughouse-chess
├── src/
│   ├── main.rs                              # UBI protocol handler (stdin/stdout loop)
│   ├── search.rs                            # Minimax / alpha-beta search
│   ├── scoring.rs                           # Position scoring / evaluation function
│   └── time.rs                              # Time management (how long to think)
├── tests/
│   ├── scoring_tests.rs                     # Scoring function sanity checks
│   └── protocol_tests.rs                    # UBI parse/format tests
└── benches/
    └── search_bench.rs                      # Benchmark search speed at various depths

bughouse-chess/                              # Move generation library (Rust)
├── src/
│   ├── lib.rs                               # Public API
│   ├── board.rs                             # Bitboard board state + reserves + promoted tracking
│   ├── board_builder.rs                     # BFEN parsing and emission
│   ├── reserve.rs                           # Piece reserve type (drop tracking)
│   ├── bughouse_move.rs                     # BughouseMove enum (Regular + Drop)
│   ├── movegen/                             # Legal move generation (all pieces + drops)
│   └── game.rs                              # Game history, draw detection
```

### Board Representation

Board representation and move generation are handled by the `bughouse-chess` library (forked from [jordanbray/chess](https://github.com/jordanbray/chess) and adapted for bughouse rules). This gives us:

- **Bitboard-based** board state (~90 bytes, `Copy`-friendly)
- **BFEN parsing** with `[reserves]` brackets and `~` promoted-piece markers
- **Legal move generation** for all piece types + drops (no pin/check filtering per bughouse rules)
- **Capture tracking** with promoted-piece demotion
- **Zobrist hashing** that includes reserve state (for repetition detection)

The engine depends on the library via:

```toml
# bughouse-engine/Cargo.toml
[dependencies]
bughouse-chess = { git = "https://github.com/vcsawant/bughouse-chess", branch = "main" }
```

The engine only needs to implement search, scoring, time management, and the UBI I/O loop — all board mechanics are delegated to the library.

```rust
use bughouse_chess::*;

// Parse a BFEN position
let board = Board::from_str("r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R[Np] w KQkq - 4 5").unwrap();

// Generate all legal moves
let moves: Vec<ChessMove> = MoveGen::new_legal(&board).collect();

// Generate all drop moves from reserves
let drops: Vec<BughouseMove> = MoveGen::drop_moves(&board);

// Make a move and track captures (for routing to partner's reserves)
let (new_board, capture) = board.make_move_with_capture(chosen_move);
// capture: Option<(Piece, was_promoted)> — if was_promoted, piece demotes to pawn
```

### Parallel Search with Rayon

The biggest win from parallelism in chess search is at the root: each candidate first move can be evaluated independently. Rayon's `par_iter` makes this almost free:

```rust
use rayon::prelude::*;

fn search_root(state: &BughouseState, depth: u8, time_budget_ms: u64) -> Move {
    let legal_moves = generate_legal_moves(&state.my_board(), state.my_color);

    let scored_moves: Vec<(Move, i32)> = legal_moves
        .par_iter()
        .map(|&mv| {
            let new_state = apply_move(state, mv);
            let score = -alpha_beta(&new_state, depth - 1, i32::MIN, i32::MAX);
            (mv, score)
        })
        .collect();

    scored_moves.into_iter()
        .max_by_key(|&(_, score)| score)
        .map(|(mv, _)| mv)
        .expect("no legal moves")
}
```

At deeper levels, you can also parallelize with techniques like lazy SMP (Lazy Symmetric Multi-Processing), but that's advanced territory. Start with root parallelism — it's simple and effective.

### Time Management

The engine must decide how long to think on each move. A simple model:

```rust
fn time_budget(my_time_ms: u64, moves_estimated_remaining: u32) -> u64 {
    // Reserve 500ms as a safety margin (for IPC latency + overhead)
    let usable_time = my_time_ms.saturating_sub(500);
    // Divide remaining time across estimated remaining moves
    // Use a fraction (e.g. 1/30) to leave time for future moves
    usable_time / (moves_estimated_remaining as u64).max(30)
}
```

This gets more sophisticated as the engine matures (detect time pressure, use more time in critical positions, less in clearly winning/losing ones). But this simple model is sufficient for stages 1-5.

---

## Phased Implementation Plan

Each phase has a clear deliverable and can be tested independently. Phases A and B can proceed in parallel.

### Phase A: Bot Registry & Lobby Integration *(Elixir)*

**Deliverable:** Bots can appear in the lobby and be placed into positions. No engine logic yet — bots are stubs.

| Step | Task | Notes |
|---|---|---|
| A1 | `bots` migration + schema | `is_bot` flag on players, new `bots` table |
| A2 | Seed internal bot player records | One per engine tier (e.g. "Random Bot") |
| A3 | Lobby UI: list available bots | Show bots alongside human join options |
| A4 | Lobby: place bot in position | Same as human join, but triggered by button |
| A5 | Health check logic | Ping before placement; mark offline on failure |
| A6 | Dual-position bot support | One bot fills two team seats; lobby shows linkage |

### Phase B: UBI Protocol + Random Bot *(Rust)*

**Deliverable:** A Rust binary that speaks UBI and plays random legal moves. End-to-end proof that the protocol works.

| Step | Task | Notes |
|---|---|---|
| B1 | Rust project scaffold | `cargo new bughouse-engine` |
| B2 | FEN parser | Parse piece-placement FEN into board struct |
| B3 | Legal move generation | All piece types, including drops |
| B4 | Random move selection | Pick a random legal move |
| B5 | UBI stdin/stdout handler | Read `position` + `go`, write `bestmove` |
| B6 | Basic test suite | Move gen correctness for known positions |

### Phase C: Bot Adapter + End-to-End Wiring *(Elixir)*

**Deliverable:** A bot actually plays in a game. You can sit down, add a bot, start a game, and watch it move.

| Step | Task | Notes |
|---|---|---|
| C1 | Internal bot adapter (GenServer) | Wraps Rust binary via Erlang Port |
| C2 | PubSub subscription + turn detection | Listen for state updates, detect own turn |
| C3 | State → UBI translation | Convert game state map to `position` command |
| C4 | Move submission | Read `bestmove`, call `make_game_move` / `drop_game_piece` |
| C5 | Integration test | Full game: human vs random bot (or bot vs bot) |
| C6 | External bot adapter (Phoenix Channel) | For remote bots; same interface as internal |

### Phase D: Real Engine Heuristics *(Rust — the fun part)*

**Deliverable:** The engine plays competently. Each step is a meaningful strength increase.

| Step | Task | Engine Stage |
|---|---|---|
| D1 | Material + positional tables scoring | Stage 3 |
| D2 | Minimax search (depth 2-3) | Stage 4 |
| D3 | Alpha-beta pruning | Stage 5 |
| D4 | Iterative deepening + time management | Stage 5 |
| D5 | Reserve-aware scoring (drop threats + opportunities) | Stage 6 |
| D6 | Clock-based strategy (stall vs rush) | Stage 7 |
| D7 | Cross-board awareness + piece request signaling | Stage 8 |
| D8 | Parallel root search with Rayon | Stage 9 |

### Phase E: Bot Ecosystem *(Phoenix + infra)*

**Deliverable:** Bot-only games, rankings, and external bot documentation.

| Step | Task | Notes |
|---|---|---|
| E1 | Bot-only game mode | Lobby option: "Bot Game" — all 4 positions are bots |
| E2 | Bot rankings | Separate leaderboard; Elo calculated between bots |
| E3 | Difficulty tiers | Expose engine config (depth, time limit) as selectable difficulty |
| E4 | External bot developer docs | UBI spec, registration flow, example client |
| E5 | Bot vs bot replay | All bot games are automatically replayable |

### Milestone Checkpoints

| Milestone | What It Means |
|---|---|
| **"First Move"** | A bot makes a legal move in a real game (end of Phase C) |
| **"Plays Chess"** | The bot plays recognizable chess — doesn't blunder pieces randomly (D1-D2) |
| **"Plays Bughouse"** | The bot uses drops, defends against drops, and shows reserve awareness (D5) |
| **"Plays Smart"** | The bot uses time pressure and cross-board coordination (D6-D7) |
| **"Bot Arena"** | Bot-only games run and produce rankings (Phase E) |

---

## Bot-Only Games & Rankings

Bot-only games are a natural consequence of the architecture — once you can place bots in lobby slots, you can place four bots. But they deserve special treatment:

### Why Bot Rankings Are Interesting

- **Deterministic testing:** You can replay exact games (same seed) to verify engine changes actually improve strength.
- **Rapid iteration:** A bot vs bot game at 1-minute time control takes ~2 minutes. You can run hundreds of games overnight to get statistically significant win rates.
- **Relative strength:** Elo between bots tells you exactly how much a heuristic change improved the engine. This is the tightest feedback loop in the project.

### Implementation Notes

- Bot-only games use the same `Game` schema and `BughouseGameServer`. No special code path.
- A separate `bot_rankings` leaderboard query filters `game_players` where all four players are bots.
- Consider a "bot tournament" mode: round-robin or Swiss bracket across registered bots, run automatically.
- Bot games should complete quickly (use short time controls) to generate data fast.

---

## Open Questions & Decisions

These are design decisions that should be revisited as each phase is implemented. Capture the decision and rationale here when resolved.

### Bot Communication

- [ ] **Should external bots connect via Phoenix Channel or raw WebSocket?**
  - Channel is cleaner (Phoenix handles framing, reconnection, presence). Raw WebSocket is more universal for external developers.
  - *Leaning toward: Channel, with good documentation. The Channel API is simple enough.*

### Engine Communication (Internal Bots)

- [ ] **Erlang Port vs Rustler NIF for internal bot communication?**
  - Port is simple: spawn a process, read/write stdin/stdout. Works with UBI as-is. Has IPC overhead (~1ms per message).
  - NIF is faster (direct function call, no IPC) but tightly couples Rust to Elixir. Also means the engine can't run standalone.
  - *Leaning toward: Port first. If latency becomes an issue at deeper search depths, consider NIF.*

### Piece Requests

- [ ] **Should piece requests be blocking or advisory?**
  - Advisory (current design): Engine sends `request n`, continues playing. Teammate engine receives `teammate_wants n` and may or may not prioritize capturing a knight.
  - Blocking: Engine sends `request n` and waits. Risky — could cause timeouts if teammate can't fulfill.
  - *Leaning toward: Advisory. Blocking requests are a footgun in timed games.*

### Dual-Control Coordination

- [ ] **How does a dual-control engine interleave moves on two boards?**
  - Two independent `go` sequences is the simplest. The engine maintains shared state internally.
  - A single `go` that returns two moves (one per board) would be more coordinated but breaks the protocol's simplicity.
  - *Leaning toward: Two independent `go` sequences. Simpler protocol, engine handles internal coordination.*

### Bot Difficulty Tiers

- [ ] **How do we expose difficulty levels to lobby users?**
  - Option A: Fixed named tiers ("Beginner", "Intermediate", "Strong") backed by preset configs (search depth, time budget fraction).
  - Option B: Continuous slider (depth 1-10) that users can tune.
  - *Decide when Phase E starts.*

### Move Delay

- [ ] **Should bots have an artificial delay before playing moves?**
  - Instant moves look unnatural in human-vs-bot games. A small delay (200-500ms) makes it feel more like playing a person.
  - In bot-only games, no delay is needed (faster iteration).
  - *Leaning toward: Configurable per-game. Human-involved games default to 300ms delay. Bot-only games default to 0.*

---

*Last updated: February 2026*
*Owner: Viren Sawant*

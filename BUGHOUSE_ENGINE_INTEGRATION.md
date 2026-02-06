# Bughouse Engine Integration

A living reference document for the design, protocol, and phased implementation plan for bot players and the Bughouse chess engine.

---

## Table of Contents

1. [Vision](#vision)
2. [Architecture Overview](#architecture-overview)
3. [Bot Types & Registration](#bot-types--registration)
4. [BUP — Bughouse Universal Protocol](#bup--bughouse-universal-protocol)
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

1. **Build a standardized bot protocol (BUP)** so that anyone — internal or external — can write a bughouse engine and connect it to this platform, similar to how UCI works for standard chess engines.
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
│  LAYER 3: BUP PROTOCOL  (Rust stdin/stdout + spec)          │
│  Bughouse Universal Protocol — the UCI equivalent           │
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

  field :config, :map, default: %{}            # engine config passed via BUP (depth, time, etc.)

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

## BUP — Bughouse Universal Protocol

BUP is modeled after UCI but extended for the dimensions that make bughouse unique: two boards, four clocks, reserves, and teammate coordination signals.

### Why a Protocol?

UCI's power is its simplicity. An engine is a black box: you give it a position, it gives you a move. The protocol is language-agnostic and transport-agnostic. BUP does the same for bughouse, which means:

- Engines can be written in any language (Rust, C++, Python, Go — whatever)
- Engines can be hosted anywhere (same server, remote VPS, cloud function)
- The protocol is the only contract between the platform and the engine

### Protocol Specification

Communication is line-based, newline-delimited, plain text. The server writes to the engine's stdin. The engine writes to the server's stdout. (For external bots over WebSocket, the same messages are sent as text frames.)

#### Server → Engine

```
# ── Position Update ──────────────────────────────────────────
# Sent before every "go" command. Contains full game state.
#
# Fields:
#   fen1        FEN of board 1 (piece placement only, e.g. "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR")
#   fen2        FEN of board 2
#   res_w       White team reserves (comma-separated piece chars, e.g. "p,p,n" or empty string)
#   res_b       Black team reserves
#   myboard     Which board this engine is playing on: 1 or 2
#   mycolor     Which color: white or black
#
position fen1 <fen1> fen2 <fen2> res_w <pieces> res_b <pieces> myboard <1|2> mycolor <white|black>

# ── Go (Think & Return a Move) ────────────────────────────────
# Tells the engine to calculate and return a bestmove.
# All times in milliseconds.
#
# Fields:
#   mytime      Time remaining on the engine's own clock
#   opptime     Time remaining on the opponent's clock (same board)
#   tmtime      Time remaining on the teammate's clock
#   otmtime     Time remaining on the opponent's teammate's clock
#
go mytime <ms> opptime <ms> tmtime <ms> otmtime <ms>

# ── Stop ──────────────────────────────────────────────────────
# Tells the engine to stop thinking immediately and return
# whatever bestmove it has so far. Used when the server needs
# an urgent response (e.g. time is nearly up).
#
stop

# ── Teammate Request ──────────────────────────────────────────
# Signals that the teammate engine has requested a specific piece.
# The engine should factor this into its scoring
# (e.g. prefer capturing that piece type if possible).
#
# piece: p | n | b | r | q
#
teammate_wants <piece>

# ── Quit ──────────────────────────────────────────────────────
# Tells the engine to shut down cleanly.
#
quit
```

#### Engine → Server

```
# ── Best Move ─────────────────────────────────────────────────
# The engine's chosen move. Exactly one of these formats:
#
#   Standard move:   <from><to>          e.g. "e2e4"
#   Promotion:       <from><to><piece>   e.g. "e7e8q"
#   Drop:            <piece>@<square>    e.g. "p@c3"
#
bestmove <move>

# ── Piece Request ─────────────────────────────────────────────
# Engine signals that it wants a specific piece from its teammate.
# The teammate engine will receive a "teammate_wants" message.
# This is advisory — the teammate is not obligated to comply.
# The engine should not block waiting for it.
#
# piece: p | n | b | r | q
#
request <piece>

# ── Info (optional) ──────────────────────────────────────────
# Debug/diagnostic output. The server logs this but does not act on it.
# Fields are all optional and can appear in any order.
#
#   depth   Search depth reached
#   nodes   Number of nodes searched
#   score   Position score (centipawns, from engine's perspective; "mate N" for forced mate)
#   time    Milliseconds spent thinking
#
info depth <n> nodes <n> score <cp|mate N> time <ms>
```

### Example Session

```
# Server sends position and asks for a move:
> position fen1 rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR fen2 rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR res_w  res_b  myboard 1 mycolor white
> go mytime 600000 opptime 600000 tmtime 599800 otmtime 600000

# Engine thinks, outputs info, then returns a move:
< info depth 4 nodes 12400 score cp 30 time 850
< bestmove e2e4

# Later, teammate requests a knight:
> teammate_wants n

# Server sends new position (teammate captured a pawn, it's now in our reserves):
> position fen1 rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R fen2 rnbqkbnr/ppppp1pp/8/5p2/4P3/8/PPPP1PPP/RNBQKBNR res_w p res_b  myboard 1 mycolor white
> go mytime 598500 opptime 599200 tmtime 598100 otmtime 598900

# Engine decides to drop the pawn (and also requests a bishop):
< request b
< info depth 3 nodes 8200 score cp 45 time 400
< bestmove p@e5
```

### Dual-Control Mode

When an engine controls both positions on a team, the server sends two independent `position` + `go` sequences — one for each board. The engine can maintain shared internal state to coordinate, but each `bestmove` response corresponds to exactly one board. The `request` / `teammate_wants` messages are suppressed in dual-control mode since coordination is internal.

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
2. **Translates** `{:game_state_update, state}` into a BUP `position` command
3. **Determines** if it's this bot's turn (checks `active_clocks` against its position)
4. **Sends** `go` with the correct clock values
5. **Reads** `bestmove` back from the engine
6. **Calls** `Games.make_game_move/3` or `Games.drop_game_piece/4`
7. **Forwards** `request` messages to the teammate's adapter (if applicable)

### State Translation: Game State → BUP Position

The game state broadcast already contains everything BUP needs:

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

# Translated to BUP:
# position fen1 <board_1_fen> fen2 <board_2_fen> res_w <white_team_reserves> res_b <black_team_reserves> myboard <N> mycolor <color>
```

Note: BUP reserves are per-team (white team / black team), not per-position. The adapter aggregates the two positions' reserves into team totals before sending. Team mapping:

- **White team reserves** = `board_1_white` reserves + `board_2_black` reserves (Team 1)
- **Black team reserves** = `board_1_black` reserves + `board_2_white` reserves (Team 2)

### Internal vs External Adapter

| Concern | Internal Bot | External Bot |
|---|---|---|
| Transport | Erlang Port (stdin/stdout) | Phoenix Channel (WebSocket) |
| Hosting | Same Fly.io VM | Remote server (any HTTP endpoint) |
| Latency | Sub-millisecond IPC | Network round-trip |
| Health check | Port alive? | HTTP GET health_url |
| BUP framing | One message per line | One message per WebSocket frame |
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
bughouse-engine/
├── Cargo.toml
├── src/
│   ├── main.rs                  # BUP protocol handler (stdin/stdout loop)
│   ├── board.rs                 # Board representation + FEN parsing
│   ├── moves.rs                 # Legal move generation
│   ├── search.rs                # Minimax / alpha-beta search
│   ├── scoring.rs               # Position scoring / evaluation function
│   ├── bughouse.rs              # Bughouse-specific state (reserves, two boards, clocks)
│   └── time.rs                  # Time management (how long to think)
├── tests/
│   ├── move_gen_tests.rs        # Exhaustive legal move generation tests
│   ├── scoring_tests.rs         # Scoring function sanity checks
│   └── protocol_tests.rs        # BUP parse/format tests
└── benches/
    └── search_bench.rs          # Benchmark search speed at various depths
```

### Board Representation

Start simple, optimize later. An 8x8 array of `Option<Piece>` is readable and correct. If performance becomes a bottleneck at deeper search depths, migrate to bitboards (one `u64` per piece type + color). The move generation and scoring code stays the same either way — only the board representation changes.

```rust
#[derive(Clone, Copy, Debug, PartialEq)]
enum Color { White, Black }

#[derive(Clone, Copy, Debug, PartialEq)]
enum PieceType { Pawn, Knight, Bishop, Rook, Queen, King }

#[derive(Clone, Copy, Debug, PartialEq)]
struct Piece {
    piece_type: PieceType,
    color: Color,
}

#[derive(Clone, Debug)]
struct Board {
    squares: [[Option<Piece>; 8]; 8],
    active_color: Color,
    castling: CastlingRights,
    en_passant: Option<Square>,  // (file, rank)
}

// Bughouse adds reserves to the board state:
#[derive(Clone, Debug)]
struct BughouseState {
    board1: Board,
    board2: Board,
    reserves: TeamReserves,      // pieces available to drop, per team
    clocks: [u64; 4],            // ms remaining: [b1_white, b1_black, b2_white, b2_black]
    my_board: u8,                // 1 or 2
    my_color: Color,
}
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

### Phase B: BUP Protocol + Random Bot *(Rust)*

**Deliverable:** A Rust binary that speaks BUP and plays random legal moves. End-to-end proof that the protocol works.

| Step | Task | Notes |
|---|---|---|
| B1 | Rust project scaffold | `cargo new bughouse-engine` |
| B2 | FEN parser | Parse piece-placement FEN into board struct |
| B3 | Legal move generation | All piece types, including drops |
| B4 | Random move selection | Pick a random legal move |
| B5 | BUP stdin/stdout handler | Read `position` + `go`, write `bestmove` |
| B6 | Basic test suite | Move gen correctness for known positions |

### Phase C: Bot Adapter + End-to-End Wiring *(Elixir)*

**Deliverable:** A bot actually plays in a game. You can sit down, add a bot, start a game, and watch it move.

| Step | Task | Notes |
|---|---|---|
| C1 | Internal bot adapter (GenServer) | Wraps Rust binary via Erlang Port |
| C2 | PubSub subscription + turn detection | Listen for state updates, detect own turn |
| C3 | State → BUP translation | Convert game state map to `position` command |
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
| E4 | External bot developer docs | BUP spec, registration flow, example client |
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
  - Port is simple: spawn a process, read/write stdin/stdout. Works with BUP as-is. Has IPC overhead (~1ms per message).
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

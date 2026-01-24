# Bughouse Chess Web Application

A real-time, multiplayer Bughouse chess platform built with Phoenix LiveView and Elixir.

## 🎯 Project Vision

Bughouse is a popular chess variant played by four players in two teams of two. This project aims to create the premier online platform for playing Bughouse chess, offering a seamless real-time experience with robust game tracking, social features, and eventually AI opponents.

**Target Audience:** Chess enthusiasts, competitive Bughouse players, and casual gamers looking for a fast-paced chess variant.

**Core Philosophy:** 
- Real-time gameplay with minimal latency
- Clean, intuitive user interface
- Fault-tolerant (handle disconnections gracefully)
- Free to play, community-focused

---

## 🎮 What is Bughouse?

Bughouse (also known as "Siamese Chess" or "Transfer Chess") is a fast-paced chess variant with these key rules:

- **4 Players, 2 Teams:** Players are paired into teams sitting opposite each other
- **2 Simultaneous Boards:** Each player plays their own game of chess
- **Piece Transfer:** When you capture a piece on your board, it becomes available for your teammate to place on their board
- **Drop Mechanic:** Players can use their turn to place a captured piece anywhere on their board (with restrictions)
- **Speed:** Typically played with short time controls (3-5 minutes per player)
- **Team Victory:** If either player on a team gets checkmated or runs out of time, their entire team loses

This creates a unique dynamic where players must balance their own game while coordinating piece transfers with their partner.

---

## ✨ Planned Features

### Phase 1: Core Gameplay (MVP)
**Status:** In Development

- [x] **Guest Play**
  - [x] Create games without an account
  - [x] Share invite links with 3 other players
  - [x] Join games via unique invite codes
  - [x] Join specific positions (board_1_white, board_1_black, etc.)
  - [x] Join random available positions
  - [ ] Play full Bughouse games anonymously (awaiting LiveView UI)

- [ ] **Real-Time Gameplay**
  - Two simultaneous chess boards rendered side-by-side
  - Click-to-move interface for piece movement
  - Click-to-drop interface for captured pieces
  - Live piece capture and transfer between boards
  - Chess clocks for all 4 players
  - Turn indicators showing whose move it is
  - Legal move validation in real-time

- [ ] **Game Rules Implementation**
  - Complete chess move validation (all pieces)
  - Special moves: castling, en passant, pawn promotion
  - Check and checkmate detection
  - Bughouse-specific rules:
    - Captured pieces transfer to teammate's pool
    - Piece drop mechanics with restrictions
    - No drops on 1st/8th rank for pawns
    - Both boards run simultaneously
  - Win conditions:
    - Checkmate on either board
    - Time expiration for any player
    - Team resignation (both players agree)

- [ ] **Fault Tolerance**
  - Handle player disconnections gracefully
  - Clocks continue running during disconnection
  - Reconnection restores game state
  - Players can refresh without losing their position
  - Game state persists in database

### Phase 2: User Accounts & Tracking
**Status:** Planned

- [ ] **Authentication System**
  - User registration with username/email/password
  - Secure login with bcrypt password hashing
  - Session management
  - Password reset flow
  - User profiles with basic info

- [ ] **Game History**
  - View all past games
  - See teammates and opponents for each game
  - Filter by win/loss/date
  - Pagination for large game lists
  - Link to game replay (future feature)

- [ ] **Social Features**
  - Friend system
  - Send/accept/reject friend requests
  - Friends list
  - Filter game history: "Games with Friends"
  - View friend profiles

### Phase 3: Enhanced Experience
**Status:** Future

- [ ] **Game Replay**
  - Step through any completed game move-by-move
  - Scrub timeline to jump to specific moments
  - Show captured pieces at each point in time
  - Export games in standard notation

- [ ] **Statistics & Rankings**
  - ELO/rating system
  - Win/loss records
  - Win rate by color/position
  - Average game length
  - Most frequent teammates/opponents
  - Leaderboards

- [ ] **Communication**
  - In-game chat between teammates
  - Post-game chat room
  - Emotes/quick reactions
  - Team voice chat integration (future)

- [ ] **Game Modes & Variants**
  - Custom time controls (1-min, 3-min, 5-min, unlimited)
  - Rated vs casual games
  - Private lobbies with passwords
  - Tournament brackets
  - Different chess variants (future)

### Phase 4: AI Integration (Reach Goal)
**Status:** Research

- [ ] **Rust-Based Chess AI**
  - Standalone Rust engine for move calculation
  - Minimax or Monte Carlo Tree Search algorithm
  - Bughouse-specific evaluation heuristics
  - Time management (faster moves when low on time)
  - Multiple difficulty levels (Easy/Medium/Hard)

- [ ] **AI Integration**
  - Fill empty lobby slots with AI
  - Choose AI difficulty before game starts
  - AI plays believably (slight delay on moves)
  - Track stats vs AI opponents separately

---

## 🏗️ Technical Architecture

### Technology Stack

**Backend:**
- **Elixir 1.14+** - Functional language, excellent for concurrent systems
- **Phoenix 1.7+** - Web framework with native WebSocket support
- **Phoenix LiveView** - Real-time, server-rendered UI without JavaScript frameworks
- **PostgreSQL 14+** - Primary database for game state, users, history
- **PubSub** - Real-time message broadcasting between players

**Frontend:**
- **Phoenix LiveView** - Server-rendered HTML with WebSocket updates
- **Tailwind CSS** - Utility-first CSS framework
- **Alpine.js** (via hooks) - Lightweight interactivity for complex UI elements
- **Unicode Chess Symbols** - ♔♕♖♗♘♙ for piece rendering

**Infrastructure:**
- **Fly.io** - Application hosting (Phoenix + PostgreSQL)
- **GitHub Actions** - CI/CD pipeline
- **Domain** - Custom domain with SSL

**Future/Optional:**
- **Rust** - Chess AI engine
- **Sentry/AppSignal** - Error monitoring
- **Redis** - Caching layer (if needed at scale)

### Why This Stack?

**Phoenix + LiveView:**
- Native WebSocket support (perfect for real-time chess)
- Server-side rendering reduces client-side complexity
- Excellent fault tolerance (BEAM/OTP platform)
- Built-in PubSub for multi-player synchronization
- Hot code reloading for fast development

**PostgreSQL:**
- JSONB support for flexible game state storage
- Strong ACID guarantees for critical data
- Excellent performance for read-heavy workloads
- Easy backups and replication

**Fly.io:**
- Excellent Elixir/Phoenix support
- Free tier for hobby projects
- Built-in PostgreSQL
- Easy deployment with `flyctl`

---

## 📊 Data Models

### Database Architecture Strategy

**Write-Once at Game Completion:**
- Game state managed in-memory during active gameplay (LiveView/GenServer)
- Chess logic handled by binbo-bughouse fork
- **Single database transaction at game end** writes:
  - Final game state (boards, moves, result)
  - Player rating updates
  - game_players records for stats

**Benefits:**
- Zero database bottleneck during gameplay
- Full replay capability via JSONB moves array
- Efficient stats queries via game_players join table
- Simple, fast implementation

### Core Schemas

**Player:**
```elixir
- id (uuid)
- display_name (string, unique)
- current_rating (integer, default: 1200)
- peak_rating (integer, default: 1200)
- total_games (integer, default: 0)
- wins, losses, draws (integer, default: 0)
- guest (boolean, default: true)
- email (string, nullable)
- inserted_at, updated_at (timestamps)
```

**Game:**
```elixir
- id (uuid)
- invite_code (string, unique, 8 chars)
- status (enum: waiting, in_progress, completed)
- board_1_white_id (uuid, references players)
- board_1_black_id (uuid, references players)
- board_2_white_id (uuid, references players)
- board_2_black_id (uuid, references players)
- time_control (string) - e.g., "10min", "3+2"
- moves (jsonb array) - Complete move history
- result (string) - "king_captured", "timeout", "draw"
- result_details (jsonb) - Structured result information
- result_timestamp (utc_datetime_usec)
- final_board_1_fen (text) - Final position for analytics
- final_board_2_fen (text)
- final_white_reserves (array of strings)
- final_black_reserves (array of strings)
- inserted_at, updated_at (timestamps)
```

**GamePlayer (Join Table - The "Magic Table" for Stats):**
```elixir
- id (uuid)
- game_id (uuid, references games)
- player_id (uuid, references players)
- position (string) - "board_1_white", "board_1_black", etc.
- color (string) - "white" or "black"
- board (integer) - 1 or 2
- rating_before (integer)
- rating_after (integer)
- rating_change (integer)
- won (boolean)
- outcome (enum: win, loss, draw, incomplete)
- created_at (timestamp)
```

**Friendship:**
```elixir
- id (uuid)
- player_id (uuid, references players)
- friend_id (uuid, references players)
- status (enum: pending, accepted, blocked)
- inserted_at, updated_at (timestamps)
```

### Move Structure (JSONB)

Each move in the `games.moves` array:

```json
{
  "player": 1,           // Player enum (1-4)
  "move_time": 2.5,      // Seconds into game (game clock)
  "notation": "e2e4",    // UCI notation
  "board": 1,            // Board number (1 or 2)
  "captured": "p"        // Optional: captured piece
}
```

**Player Enum Convention:**
- 1 = board_1_white
- 2 = board_1_black
- 3 = board_2_white
- 4 = board_2_black

### Analytics Queries Enabled

The game_players join table enables efficient queries for:
- ✅ Win/loss overall record
- ✅ Stats with specific friends
- ✅ Winrate by color (white/black)
- ✅ Rating history over time
- ✅ Winrate by time control
- ✅ Average move time (via JSONB query on moves)
- ✅ Performance trends
- ✅ Most common openings

---

## 🎨 User Interface Design

### Layout

```
┌─────────────────────────────────────────────────────────────┐
│  [Logo]  Bughouse Chess           [Login] [Sign Up]         │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│   ┌────────────────┐  ┌─────────────┐                       │
│   │  Board A       │  │ White Team  │                       │
│   │  (White vs     │  │ Captures:   │                       │
│   │   Black)       │  │ ♞ ♝ ♟       │                       │
│   │                │  │             │                       │
│   │  8x8 Grid      │  │ Timer: 3:45 │                       │
│   │  with pieces   │  │ Timer: 3:12 │                       │
│   └────────────────┘  └─────────────┘                       │
│                                                               │
│   ┌────────────────┐  ┌─────────────┐                       │
│   │  Board B       │  │ Black Team  │                       │
│   │  (White vs     │  │ Captures:   │                       │
│   │   Black)       │  │ ♘ ♗ ♙ ♖     │                       │
│   │                │  │             │                       │
│   │  8x8 Grid      │  │ Timer: 2:58 │                       │
│   │  with pieces   │  │ Timer: 3:01 │                       │
│   └────────────────┘  └─────────────┘                       │
│                                                               │
│   [Resign] [Draw Offer]        Turn: White (Board A)        │
└─────────────────────────────────────────────────────────────┘
```

### Key UI Elements

**Chess Board:**
- 8x8 grid with alternating light (#f0d9b5) and dark (#b58863) squares
- Unicode chess pieces (♔♕♖♗♘♙ / ♚♛♜♝♞♟)
- File labels (a-h) on bottom
- Rank labels (1-8) on left side
- Highlighted selected piece
- Highlighted valid move destinations
- Move animation (smooth piece movement)

**Captured Pieces Display:**
- Grouped by type
- Count badge for multiple pieces of same type
- Clickable to select for drop
- Visual indicator when piece selected

**Chess Clocks:**
- MM:SS format
- Active player's clock highlighted
- Red when <30 seconds remain
- Pulses when <10 seconds

**Game Lobby:**
- 4 player slots in a 2x2 grid
- Team indicators (Team White vs Team Black)
- "Open" button for empty slots
- Player names when filled
- "Start Game" button (enabled when 4 players)
- Shareable invite link prominently displayed

---

## 🔄 Real-Time Synchronization

### PubSub Topics

**Game Updates:**
```elixir
topic: "game:#{game_id}"
events: 
  - player_joined
  - player_left
  - move_made
  - piece_dropped
  - time_updated
  - game_ended
```

**Lobby Updates:**
```elixir
topic: "lobby:#{game_id}"
events:
  - slot_filled
  - slot_emptied
  - game_started
```

### State Management

- **Source of truth:** PostgreSQL database
- **In-memory cache:** LiveView assigns (per-connection state)
- **Broadcast:** PubSub for cross-player synchronization
- **Persistence:** Save to DB after each move/drop

### Connection Handling

1. **On Connect:** Load game state from DB
2. **On Move:** Validate → Save → Broadcast → Update all clients
3. **On Disconnect:** Mark player as disconnected, continue game
4. **On Reconnect:** Restore player position, sync current state

---

## 🧪 Testing Strategy

### Test Coverage Goals

- **Business Logic:** >80% coverage
- **LiveView Interactions:** Key user flows tested
- **Chess Engine:** 100% coverage (move validation critical)

### Test Types

**Unit Tests:**
- Chess move validation
- Board state transformations
- Bughouse piece transfer logic
- Win condition detection
- Time management

**Integration Tests:**
- Game creation flow
- Player join/leave
- Full game playthrough
- Reconnection scenarios

**LiveView Tests:**
- Lobby interactions
- Move input handling
- Real-time updates
- Error handling

### Test Data

Use ExMachina for factories:
- Standard chess positions
- Common bughouse scenarios
- Edge cases (castling, en passant, promotion)
- Checkmate patterns

---

## 🚀 Deployment Strategy

### Environments

**Development:**
- Local PostgreSQL
- Local Phoenix server
- Hot code reloading enabled

**Production:**
- Fly.io hosting (single US region)
- Fly.io managed PostgreSQL
- SSL via Fly.io
- Custom domain

### Deployment Process

```bash
# 1. Run tests
mix test

# 2. Build release
MIX_ENV=prod mix release

# 3. Deploy to Fly.io
fly deploy

# 4. Run migrations
fly ssh console -C "/app/bin/migrate"
```

### Monitoring

- Fly.io metrics dashboard
- Phoenix LiveDashboard (production)
- Error tracking via Logger
- (Future: Sentry/AppSignal integration)

### Backup Strategy

- Automatic daily PostgreSQL backups (Fly.io)
- 7-day retention
- Manual backup before major deployments

---

## 📈 Scalability Considerations

### Current Scale (Phase 1)

**Target:** 10-50 concurrent games (40-200 connected users)

**Infrastructure:**
- Single Fly.io VM (shared CPU)
- 1GB RAM
- Shared PostgreSQL instance

**Expected Performance:**
- <100ms move latency
- <50ms LiveView updates
- Handles 200+ WebSocket connections easily

### Future Scale (If Needed)

**1,000+ concurrent games:**
- Vertical scaling: Dedicated CPU, 2-4GB RAM
- Horizontal scaling: Multiple Fly.io instances
- PostgreSQL read replicas
- Redis for session store
- CDN for static assets

**Phoenix handles this well:**
- 2 million WebSocket connections per server (proven)
- Sub-millisecond message passing (BEAM VM)
- Built-in distributed system capabilities

---

## 🔐 Security Considerations

### Authentication

- Bcrypt password hashing (cost: 12)
- Secure session tokens
- CSRF protection (built into Phoenix)
- Rate limiting on login attempts (future)

### Authorization

- Users can only modify their own games
- Guest players assigned via session ID
- No direct database ID exposure (use UUIDs)

### Data Protection

- Passwords never stored in plain text
- User emails not publicly exposed
- Game history private by default

### Input Validation

- All moves validated server-side
- No trust in client-side state
- SQL injection prevention (Ecto)
- XSS prevention (Phoenix templates escape by default)

---

## 🛠️ Development Setup

### Prerequisites

- Elixir 1.14+ 
- Erlang/OTP 25+
- PostgreSQL 14+
- Node.js 18+ (for asset compilation)

### Installation

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/bughouse-chess.git
cd bughouse-chess

# Install dependencies
mix deps.get
npm install --prefix assets

# Create database
mix ecto.create
mix ecto.migrate

# Start Phoenix server
mix phx.server
```

Visit `http://localhost:4000`

### Configuration

Create `config/dev.secret.exs` (gitignored):

```elixir
import Config

config :bughouse, Bughouse.Repo,
  username: "YOUR_USERNAME",
  password: "",
  hostname: "localhost",
  database: "bughouse_dev"
```

---

## 📝 Code Organization

### Directory Structure

```
lib/
├── bughouse/                  # Business logic (contexts)
│   ├── accounts/              # User management
│   │   ├── user.ex
│   │   └── user_token.ex
│   ├── games/                 # Game management
│   │   ├── game.ex
│   │   └── game_server.ex
│   ├── chess/                 # Chess engine
│   │   ├── board.ex           # Board representation
│   │   ├── move.ex            # Move validation
│   │   ├── piece.ex           # Piece definitions
│   │   └── notation.ex        # FEN parsing/generation
│   ├── bughouse/              # Bughouse-specific logic
│   │   ├── capture_pool.ex    # Captured pieces management
│   │   └── drop.ex            # Piece drop mechanics
│   └── social/                # Social features
│       └── friendship.ex
├── bughouse_web/              # Web interface
│   ├── components/            # Reusable components
│   ├── controllers/           # Traditional controllers
│   ├── live/                  # LiveView modules
│   │   ├── game_live.ex       # Main game interface
│   │   ├── lobby_live.ex      # Game lobby
│   │   └── dashboard_live.ex  # User dashboard
│   ├── templates/             # HTML templates (if needed)
│   └── router.ex              # Routes definition
└── bughouse.ex                # Application entry point

test/
├── bughouse/                  # Business logic tests
│   ├── chess/
│   │   ├── board_test.exs
│   │   ├── move_test.exs
│   │   └── checkmate_test.exs
│   └── bughouse/
│       └── drop_test.exs
└── bughouse_web/              # Web layer tests
    └── live/
        └── game_live_test.exs
```

### Naming Conventions

**Modules:**
- Contexts: `Bughouse.Games`, `Bughouse.Accounts`
- Schemas: `Bughouse.Games.Game`, `Bughouse.Accounts.User`
- LiveViews: `BughouseWeb.GameLive`, `BughouseWeb.LobbyLive`

**Functions:**
- Public API: `Games.create_game/1`, `Games.make_move/3`
- Private helpers: `do_validate_move/2`, `calculate_captures/1`

**Variables:**
- Snake case: `game_state`, `player_id`, `captured_pieces`

---

## 🎓 Learning Resources

### Bughouse Chess

- [Bughouse Chess Rules](https://en.wikipedia.org/wiki/Bughouse_chess)
- [Chess.com Bughouse Guide](https://www.chess.com/terms/bughouse-chess)
- Study top players on lichess.org

### Phoenix & LiveView

- [Phoenix Guides](https://hexdocs.pm/phoenix/overview.html)
- [LiveView Documentation](https://hexdocs.pm/phoenix_live_view/)
- [Pragmatic Studio Phoenix Course](https://pragmaticstudio.com/phoenix)
- [Elixir School](https://elixirschool.com/)

### Chess Programming

- [Chess Programming Wiki](https://www.chessprogramming.org/)
- FEN notation standard
- PGN (Portable Game Notation) for game export

---

## 🤝 Contributing

This is currently a solo learning project, but suggestions and feedback are welcome!

### If You Want to Contribute

1. Open an issue describing your proposed feature
2. Wait for discussion/approval
3. Fork the repository
4. Create a feature branch
5. Submit a pull request

### Code Style

- Follow Elixir community conventions
- Run `mix format` before committing
- Add tests for new features
- Update documentation

---

## 📄 License

This project is licensed under the MIT License - see LICENSE file for details.

---

## 🗺️ Roadmap

### Q1 2026 (Current)
- [x] Project setup and architecture
- [x] Database schema (players, games, game_players, friendships)
- [x] binbo-bughouse fork integration
- [ ] Core chess engine implementation
- [ ] Bughouse mechanics
- [ ] Real-time gameplay (guest play)

### Q2 2026
- [ ] User authentication
- [ ] Game history tracking
- [ ] Friend system
- [ ] Production deployment

### Q3 2026
- [ ] Game replay feature
- [ ] Statistics and rankings
- [ ] Tournament system

### Q4 2026 / 2027
- [ ] AI opponent (Rust integration)
- [ ] Advanced features (voice chat, etc.)

---

## 📧 Contact

**Project Maintainer:** Viren Sawant
**Email:** viren.c.sawant@gmail.com
**GitHub:** https://github.com/vcsawant

---

## 🙏 Acknowledgments

- Phoenix Framework team for excellent documentation
- Elixir community for helpful resources
- Chess.com and Lichess for inspiration
- Bughouse chess community

---

## 📊 Project Status

**Current Phase:** Phase 1 - Core Gameplay (MVP)  
**Status:** In Active Development  
**Estimated Completion:** Q1-Q2 2025  
**Version:** 0.1.0 (Pre-release)

---

**Last Updated:** January 2026

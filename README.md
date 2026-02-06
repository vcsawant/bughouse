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
**Status:** In Progress

- [x] **Authentication System**
  - [x] Google OAuth integration
  - [x] Secure session management
  - [x] User profiles from OAuth data
  - [x] Display name from Google account
  - [x] Email confirmation tracking
  - [ ] GitHub OAuth (prepared for future)
  - [ ] Password-based authentication (optional)
  - [ ] Password reset flow

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

### Phase 4: Bot Players & Engine Ecosystem
**Status:** In Planning — see [BUGHOUSE_ENGINE_INTEGRATION.md](./BUGHOUSE_ENGINE_INTEGRATION.md) for full design doc

- [x] **Bot Registry & Lobby Integration**
  - [x] Bot schema: `players.is_bot` flag + `bots` table (type, health_url, supported_modes, per-mode ratings)
  - [x] Lobby UI: add/remove single and dual bots from open seats via inline dropdown
  - [ ] Health check system — external bots must be alive to join a game
  - [ ] Bot adapter wiring (connects lobby placement to BUP engine process)

- [ ] **BUP — Bughouse Universal Protocol**
  - Standardized stdin/stdout protocol for bughouse engines (modeled after UCI)
  - Supports two-board state, four clocks, reserves, and teammate piece requests
  - Language- and transport-agnostic: any engine that speaks BUP can connect
  - External bots connect via Phoenix Channel; internal bots via Erlang Port

- [ ] **Rust-Based Bughouse Engine**
  - Standalone Rust binary speaking BUP
  - Legal move generation (all pieces + drops)
  - Iterative deepening with alpha-beta pruning
  - Bughouse-specific scoring: reserves, drop threats, clock pressure, cross-board awareness
  - Parallel root search with Rayon
  - Piece request / teammate coordination signaling

- [ ] **Bot Ecosystem**
  - Bot-only games (all 4 positions are engines)
  - Separate bot rankings with Elo
  - Configurable difficulty tiers
  - External bot developer documentation

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

**Planned:**
- **Rust** - Bughouse engine (BUP protocol, parallel search via Rayon) — see [BUGHOUSE_ENGINE_INTEGRATION.md](./BUGHOUSE_ENGINE_INTEGRATION.md)
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
  - Produces spec-compliant **BFEN** (see [BFEN.md](./BFEN.md)):
    - Reserves in single-bracket format `[QRBNPqrbnp]`; empty reserves emit `[]`
    - Promoted pieces marked with `~` suffix in position string (e.g. `Q~`)
    - Parser accepts both single-bracket and legacy two-bracket reserve formats
    - Full FEN round-trip fidelity (emit → parse → emit is identity)
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
- rating_before (integer)
- rating_after (integer)
- rating_change (integer)
- won (boolean)
- outcome (enum: win, loss, draw, incomplete)
- created_at (timestamp)
```
> **Note:** Position, color, and board are not stored here — they are derived from the
> `games` table (`board_1_white_id`, etc.) where needed. This keeps `game_players` as a
> pure participation + rating record: exactly one row per player per game, regardless of
> whether the player is human or a dual-position bot.

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

### Guest Player Session Persistence

Guest players are persisted across page refreshes using HTTP session cookies:

1. **On first visit:** `BughouseWeb.UserAuth.on_mount/4` hook creates a guest player record in the database
2. **Session storage:** Player ID is written to session via `Phoenix.LiveView.put_session/3`
3. **On subsequent visits:** Same player ID is retrieved from session cookie and looked up in database
4. **If session player deleted:** New guest is created transparently and session is updated
5. **Session expiry:** Default 14 days (configurable via `:max_age` in session options)

**Session Configuration:**
- **Storage:** Cookie-based (signed, not encrypted)
- **Session key:** `"current_player_id"` (binary_id UUID)
- **Configured in:** `lib/bughouse_web/endpoint.ex`

**Debug Logging:**
- **Server logs:** Look for "Created guest player" or "Reusing existing guest player" in Phoenix logs
- **Client logs:** Open browser DevTools → Console → Look for "[Bughouse] GameLive mounted"

This ensures guests maintain their identity, position in games, and can refresh/reconnect without losing their place.

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

### Google OAuth Authentication Setup

The application supports Google OAuth for user authentication. To enable this feature:

#### 1. Create Google OAuth Credentials

1. Visit [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project: "Bughouse Chess"
3. Enable the "Google+ API" (or Google Identity services)
4. Navigate to "Credentials" → "Create Credentials" → "OAuth 2.0 Client ID"
5. Application type: **Web application**
6. Add authorized redirect URIs:
   - Development: `http://localhost:4000/auth/google/callback`
   - Production: `https://your-domain.com/auth/google/callback`
7. Copy the **Client ID** and **Client Secret**

#### 2. Configure Environment Variables

```bash
# Copy the example file
cp .env .env

# Edit .env with your credentials
export GOOGLE_CLIENT_ID=your-actual-client-id-here
export GOOGLE_CLIENT_SECRET=your-actual-client-secret-here
export GOOGLE_REDIRECT_URI=http://localhost:4000/auth/google/callback

# Load environment variables
source .env

# Start the server
mix phx.server
```

**Important:** Never commit `.env` to version control. It's already in `.gitignore`.

#### 3. Production Setup (Fly.io)

For production deployment on Fly.io:

```bash
# Set secrets
fly secrets set GOOGLE_CLIENT_ID=your-prod-client-id
fly secrets set GOOGLE_CLIENT_SECRET=your-prod-client-secret
fly secrets set GOOGLE_REDIRECT_URI=https://your-app.fly.dev/auth/google/callback

# Deploy
fly deploy
```

**Remember:** Update Google OAuth redirect URIs in the Cloud Console for production domain.

#### How It Works

- **Guest Players:** Users can play without signing in (Guest_XXXX)
- **OAuth Login:** Sign in with Google to save progress across devices
- **Display Name:** Pulled from Google (first name + last name), fallback to email
- **Session Persistence:** Database-backed sessions work across devices
- **Existing Games:** Prevents joining the same game twice

### Account Features

Once you've signed in with Google, you can access your account page with comprehensive features for managing your profile and viewing your game history.

#### Accessing Your Account

Authenticated users can access their account page by:
- Clicking the user icon in the navigation bar
- Selecting "Account" from the dropdown menu
- Navigating directly to `/account`

**Note:** Guest users cannot access the account page and will be redirected to `/login`.

#### Profile Tab

View and manage your account information:

- **Username**: Your unique identifier starting with @ (read-only)
- **Email**: Your registered email address from Google OAuth (read-only)
- **Display Name**: Your public name (editable - click the pencil icon to change)
- **Connected Accounts**: OAuth providers you've linked (Google, with GitHub coming soon)
- **Member Since**: Account creation date

The profile tab makes it easy to customize how you appear to other players while keeping your core account information secure.

#### Game History Tab

Track your chess performance over time with comprehensive statistics and game records:

**Rating Statistics:**
- **Current Rating**: Your active Elo rating
- **Peak Rating**: Your highest rating achieved
- **Total Games**: Complete count of games played
- **Record**: Win/Loss/Draw breakdown

**Rating History Graph:**
- Visual representation of your rating progression over time
- Interactive time period filters:
  - **1d**: Last 24 hours
  - **1m**: Last 30 days
  - **3m**: Last 90 days
  - **All**: Complete history
- Custom date range selector (coming soon)
- *Note: Full interactive graph with Chart.js coming in a future update*

**Recent Games Table:**
- Displays your last 100 games (paginated, 25 per page)
- Each game row shows:
  - **Game ID**: Unique invite code for the game (future: click to replay)
  - **Position**: Your board and color (e.g., "Board 1 White", "Board 2 Black")
  - **Teammate**: Your partner's username (Bughouse is a team game!)
  - **Opponents**: Both opposing players' usernames
  - **Result**: Win/Loss/Draw with color-coded badges
  - **Rating Change**: Points gained or lost (+/- with green/red indicators)
- Bughouse-specific team information respects the unique pairing:
  - Team 1: Board 1 White + Board 2 Black
  - Team 2: Board 1 Black + Board 2 White
- Username links to player profiles (coming soon)
- Guest players display as "guest" in a muted style

**Pagination:**
- Navigate through your game history 25 games at a time
- Up to 4 pages of recent games (100 total)
- Active page highlighted for easy navigation

#### Friends Tab

**Coming Soon!** Friend management and social features will be added in a future update, including:
- Send and accept friend requests
- View friends list with online status
- Challenge friends to games
- Head-to-head statistics
- Recent games with friends
- Friend activity feed

Stay tuned for these exciting social features that will make it even easier to play with your regular chess partners!

---

### Game Replay Viewer

After a game ends, you can watch a full replay with video-like playback controls that recreate the game exactly as it was played.

#### Watching Completed Games

**Access a Replay:**
- Click a game ID from your **Account > Game History** tab
- Navigate to `/game/view/:invite_code` directly
- Share replay URLs with friends to show them your games

#### Playback Features

**Video-Like Controls:**

- **Play/Pause**: Watch the game play out automatically with moves occurring at their actual timing
- **Speed Control**: Choose from 1x, 2x (default), 3x, 4x, or 5x playback speed
  - 2x speed is default for a good balance of speed and followability
  - 5x speed lets you quickly review long games
  - 1x speed recreates the exact real-time experience
- **Progress Bar with Scrubbing**: Drag the progress bar to jump to any point in the game instantly
  - Visual move markers show where moves occurred
  - Click anywhere on the bar to seek to that moment
- **Move Navigation**: Use Previous/Next buttons to step through moves one at a time

**What You'll See:**

- **Both Chess Boards**: Displayed side-by-side just like during the live game
- **All Four Player Clocks**: Counting down smoothly with precise timing
- **Captured Pieces**: Appearing in team reserves as they're captured
- **Piece Drops and Promotions**: Accurately recreated with proper piece placement
- **Game Result**: Final result and reason displayed (checkmate, timeout, resignation)

**Keyboard Shortcuts:**

Make navigation even faster with these keyboard controls:

- **Space**: Play/Pause
- **← (Left Arrow)**: Previous move
- **→ (Right Arrow)**: Next move
- **1-5 (Number Keys)**: Set playback speed (1x through 5x)
- **Home**: Jump to start (coming soon)
- **End**: Jump to end (coming soon)

#### How It Works

The replay system uses the complete move history with precise timestamps to recreate the game deterministically. Every move, capture, drop, and clock tick is replayed exactly as it happened, scaled by your chosen playback speed.

**Technical Details:**
- Moves are played at their actual timing intervals (e.g., if a player thought for 15 seconds, the replay pauses for 15 seconds at 1x speed, or 7.5 seconds at 2x speed)
- Clocks interpolate smoothly between moves for a polished viewing experience
- Complete board state (FEN and reserves) stored with every move for deterministic replay
- Instant scrubbing to any point - no reconstruction needed
- All playback happens client-side after initial load for smooth 60fps performance
- Works even if your internet connection drops during replay

**Implementation:**

The replay system captures complete board state (FEN and reserves) with every move during gameplay. This allows deterministic, instant replay without reconstructing positions. Each move stores:

- FEN notation for both boards (piece placement)
- Captured piece reserves for both teams
- Clock times for all four players
- Move timestamp for time-based playback

This approach trades ~9KB of storage per game for replay simplicity and speed. All chess logic stays server-side - JavaScript simply displays stored positions.

#### Use Cases

- **Learning**: Review your games to find mistakes and identify improvements
- **Sharing**: Show exciting games to friends or on social media
- **Analysis**: Study high-level games move-by-move at any speed
- **Entertainment**: Watch Bughouse games like watching a chess video
- **Coaching**: Teachers can use replays to demonstrate tactics and strategies

**Future Enhancements:**
- Move list sidebar with algebraic notation
- Analysis mode showing best moves and blunders
- Export replays as GIF/MP4 videos
- Add annotations and comments to specific moves
- Slow-motion playback (0.5x, 0.25x) for detailed analysis

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
- [ ] Bot registry + lobby integration (Phase 4A)
- [ ] BUP protocol + Rust engine first cut (Phase 4B-C)
- [ ] Engine heuristics iteration (Phase 4D)
- [ ] Bot-only games + rankings (Phase 4E)
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

# CLAUDE.md - AI Assistant Context

This document provides context for AI coding assistants (Claude, Cursor, etc.) working on the Bughouse Chess project.

## Project Overview

See [README.md](./README.md) for full project documentation. This is a Phoenix LiveView application for playing Bughouse chess (2v2 chess variant with piece transfers).

---

## Quick Context for AI Assistants

### What You're Working On
A real-time multiplayer Bughouse chess web application built with Phoenix and LiveView. Four players (two teams) play simultaneous chess games where captured pieces transfer to the teammate's board for placement.

### Tech Stack
- **Elixir 1.14+** with **Phoenix 1.7+**
- **Phoenix LiveView** for real-time UI
- **PostgreSQL** for data persistence
- **Tailwind CSS** for styling
- Deployment: **Fly.io**

### Current Development Phase
**Phase 1: Core Gameplay (MVP)**
- Implementing chess engine (move validation, board state)
- Building Bughouse-specific mechanics (piece transfers, drops)
- Creating real-time multiplayer UI with LiveView
- Guest play (no accounts yet)

---

## Code Conventions

### Module Organization
```elixir
# Contexts (business logic)
Bughouse.Games           # Game management
Bughouse.Chess           # Chess engine
Bughouse.Bughouse        # Bughouse-specific logic
Bughouse.Accounts        # User management (Phase 2)

# Web layer
BughouseWeb.GameLive     # Main game interface
BughouseWeb.LobbyLive    # Game lobby
BughouseWeb.Router       # Routes
```

### Naming Patterns
- **Modules:** PascalCase - `Bughouse.Chess.Board`
- **Functions:** snake_case - `validate_move/2`, `create_game/1`
- **Variables:** snake_case - `game_state`, `board_a`
- **LiveView events:** snake_case - `"select_square"`, `"make_move"`

### File Locations
- Business logic: `lib/bughouse/`
- Web interface: `lib/bughouse_web/`
- Tests: `test/` (mirrors `lib/` structure)
- Migrations: `priv/repo/migrations/`

---

## Key Architecture Decisions

### Why LiveView?
- Real-time updates without JavaScript framework overhead
- Server-side state management (simpler, more secure)
- Native WebSocket support perfect for chess
- Great developer experience with hot reloading

### State Management
- **Source of truth:** PostgreSQL database
- **Per-connection state:** LiveView socket assigns
- **Cross-player sync:** Phoenix PubSub
- **Pattern:** Update DB → Broadcast → All clients update

### Chess Board Representation
```elixir
%Board{
  squares: %{
    {0, 0} => %Piece{type: :rook, color: :white},
    {0, 1} => %Piece{type: :knight, color: :white},
    # ... coordinate-based map
  },
  active_color: :white,
  castling_rights: %{wk: true, wq: true, bk: true, bq: true},
  en_passant_target: nil,
  halfmove_clock: 0,
  fullmove_number: 1
}
```

### Database Schema (Current)
```elixir
# games table
- id (uuid)
- invite_code (string, unique)
- status (enum: waiting, in_progress, completed)
- board_state_a (jsonb)
- board_state_b (jsonb)
- white_team_captures (jsonb)
- black_team_captures (jsonb)
- player_1_id, player_2_id, player_3_id, player_4_id (string, nullable)
- player_1_time_ms, player_2_time_ms, player_3_time_ms, player_4_time_ms (integer)
- result (string, nullable)
- timestamps
```

---

## Working on Features

### Before Starting a Task
1. Read the task description in GitHub Issues
2. Review related code in the project
3. Check if tests exist for the area
4. Understand the acceptance criteria

### Implementation Pattern
1. **Write the test first** (TDD preferred for chess logic)
2. **Implement the function** in the appropriate context
3. **Add to LiveView** if UI changes needed
4. **Update database** if schema changes needed
5. **Run tests:** `mix test`
6. **Check formatting:** `mix format`

### Testing Commands
```bash
# Run all tests
mix test

# Run specific test file
mix test test/bughouse/chess/board_test.exs

# Run tests matching pattern
mix test --only move_validation

# Run with coverage
mix test --cover
```

### Common Tasks

**Adding a new LiveView:**
```bash
# Generate LiveView
mix phx.gen.live Games Lobby --no-schema

# Add route to router.ex
live "/game/:invite_code", GameLive
```

**Creating a migration:**
```bash
mix ecto.gen.migration create_games
# Edit file in priv/repo/migrations/
mix ecto.migrate
```

**Adding a new context function:**
```elixir
# In lib/bughouse/games.ex
def create_game(attrs \\ %{}) do
  %Game{}
  |> Game.changeset(attrs)
  |> Repo.insert()
end
```

---

## Chess Engine Implementation

### Move Validation Pattern
```elixir
def valid_moves(board, from_position) do
  piece = Board.get_piece(board, from_position)
  
  case piece.type do
    :pawn -> pawn_moves(board, from_position, piece.color)
    :knight -> knight_moves(board, from_position, piece.color)
    :bishop -> bishop_moves(board, from_position, piece.color)
    :rook -> rook_moves(board, from_position, piece.color)
    :queen -> queen_moves(board, from_position, piece.color)
    :king -> king_moves(board, from_position, piece.color)
  end
  |> Enum.filter(&legal_move?(board, from_position, &1))
end

defp legal_move?(board, from, to) do
  # Must not leave own king in check
  temp_board = apply_move(board, from, to)
  !in_check?(temp_board, board.active_color)
end
```

### Bughouse-Specific Rules
- Captured piece on Board A → Available in white_team_captures or black_team_captures
- Can drop piece on any empty square (except pawns on 1st/8th rank)
- Both boards run simultaneously (independent turn tracking)
- Team loses if either player gets checkmated or times out

---

## LiveView Patterns

### Mount Pattern
```elixir
def mount(%{"invite_code" => code}, session, socket) do
  if connected?(socket) do
    # Subscribe to game updates
    Phoenix.PubSub.subscribe(Bughouse.PubSub, "game:#{code}")
  end
  
  game = Games.get_game_by_invite_code!(code)
  
  {:ok, assign(socket, 
    game: game,
    selected_square: nil,
    current_user: get_user_from_session(session)
  )}
end
```

### Event Handling Pattern
```elixir
def handle_event("select_square", %{"pos" => pos}, socket) do
  valid_moves = Chess.valid_moves(socket.assigns.game.board_a, pos)
  
  {:noreply, assign(socket,
    selected_square: pos,
    highlighted_squares: valid_moves
  )}
end

def handle_event("make_move", %{"from" => from, "to" => to}, socket) do
  case Games.make_move(socket.assigns.game, from, to) do
    {:ok, updated_game} ->
      # Broadcast to other players
      Phoenix.PubSub.broadcast(
        Bughouse.PubSub,
        "game:#{updated_game.id}",
        {:move_made, updated_game}
      )
      {:noreply, assign(socket, game: updated_game)}
    
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, reason)}
  end
end
```

### PubSub Pattern
```elixir
def handle_info({:move_made, updated_game}, socket) do
  {:noreply, assign(socket, game: updated_game)}
end
```

---

## Common Pitfalls to Avoid

### ❌ Don't
- Trust client-side move validation (always validate on server)
- Store game state only in LiveView assigns (persist to DB)
- Use blocking operations in LiveView (use Task.async for long operations)
- Hardcode player IDs (use session-based guest IDs)
- Forget to broadcast updates to all connected players

### ✅ Do
- Validate all moves server-side
- Save game state to database after each move
- Use PubSub for cross-player synchronization
- Handle disconnections gracefully
- Write tests for chess logic (especially edge cases)
- Use Ecto changesets for data validation
- Follow Phoenix conventions

---

## Debugging Tips

### LiveView Debugging
```elixir
# In LiveView, inspect socket assigns
require Logger
Logger.debug("Socket assigns: #{inspect(socket.assigns)}")

# In templates, inspect any variable
<%= inspect(@game, pretty: true) %>
```

### Database Queries
```bash
# Open database console
psql -U your_username -d bughouse_dev

# In psql
\dt              # List tables
\d games         # Describe games table
SELECT * FROM games WHERE status = 'in_progress';
```

### IEx Debugging
```bash
# Start with IEx
iex -S mix phx.server

# In IEx
alias Bughouse.{Games, Chess}
game = Games.get_game!("game-id")
Chess.valid_moves(game.board_a, {0, 0})
```

---

## Performance Considerations

### Current Scale Target
- 10-50 concurrent games (40-200 connected users)
- <100ms move latency
- <50ms LiveView update time

### Optimization Priorities (when needed)
1. Database indexing (invite_code, player_ids)
2. Limit PubSub message size (send diffs, not full state)
3. Lazy load game history
4. Add caching for read-heavy queries

### Don't Optimize Yet
- Single server handles this fine
- Phoenix can handle 2M+ WebSocket connections
- PostgreSQL can handle this query load easily
- Premature optimization wastes time

---

## Testing Philosophy

### What to Test Thoroughly
- ✅ Chess move validation (100% coverage goal)
- ✅ Bughouse piece transfer logic
- ✅ Win condition detection
- ✅ Game state transitions

### What to Test Lightly
- ⚠️ Basic CRUD operations (covered by integration tests)
- ⚠️ UI rendering (manual testing fine for now)
- ⚠️ Third-party library behavior

### Test Data Strategy
Use ExMachina factories for common scenarios:
```elixir
# test/support/factory.ex
def game_factory do
  %Game{
    invite_code: sequence(:invite_code, &"CODE#{&1}"),
    status: :waiting,
    board_state_a: Chess.Board.new(),
    board_state_b: Chess.Board.new(),
    # ...
  }
end
```

---

## Security Checklist

When implementing features, ensure:
- [ ] All user input is validated
- [ ] Moves are validated server-side
- [ ] Users can only access their own data
- [ ] No database IDs exposed in URLs (use UUIDs/codes)
- [ ] CSRF tokens present on forms
- [ ] Passwords are hashed (never plain text)
- [ ] SQL injection not possible (use Ecto)

---

## Getting Help

### Documentation
- Phoenix: https://hexdocs.pm/phoenix/
- LiveView: https://hexdocs.pm/phoenix_live_view/
- Ecto: https://hexdocs.pm/ecto/

### When Stuck
1. Check existing tests for examples
2. Review similar code in the project
3. Read Phoenix guides
4. Check Elixir Forum: https://elixirforum.com/

---

## Git Workflow

### Commit Messages
Follow conventional commits:
```
feat: add chess board rendering
fix: correct en passant validation
test: add checkmate detection tests
docs: update README with deployment steps
refactor: simplify move validation logic
```

### Branch Naming
```
feature/task-1.1-environment-setup
feature/chess-engine-move-validation
fix/castling-validation-bug
```

### Before Committing
```bash
mix test           # All tests pass
mix format         # Code formatted
mix credo          # Linting (if configured)
```

---

## Quick Reference

### Start Development
```bash
mix phx.server
# Visit http://localhost:4000
```

### Run Tests
```bash
mix test
mix test --cover
mix test test/bughouse/chess/board_test.exs
```

### Database
```bash
mix ecto.create        # Create database
mix ecto.migrate       # Run migrations
mix ecto.rollback      # Rollback last migration
mix ecto.reset         # Drop, create, migrate
```

### Generate Code
```bash
mix phx.gen.live Context Schema table field:type
mix ecto.gen.migration migration_name
```

### Production
```bash
MIX_ENV=prod mix release
fly deploy
```

---

## Current Focus (Phase 1)

### In Progress
- Chess engine implementation (Milestone 3)
- Board representation and move validation
- Check/checkmate detection

### Up Next
- Bughouse-specific mechanics (Milestone 4)
- Real-time gameplay UI (Milestone 5)
- Guest play functionality

### Not Yet Started
- User authentication (Phase 2)
- Game history tracking
- Friend system
- AI integration (Phase 4)

---

## Questions to Ask Before Implementing

1. **Does this need to be real-time?** (Use LiveView/PubSub)
2. **Does this need to persist?** (Add database field)
3. **Can users cheat if this is client-side?** (Validate on server)
4. **Will this scale to 100 concurrent games?** (Usually yes)
5. **Is there a Phoenix convention for this?** (Follow it)

---

## Remember

- **Phoenix/LiveView handles the hard parts** (WebSockets, state management)
- **Validate everything server-side** (chess moves, drops, game state)
- **Test your chess logic thoroughly** (this is the most complex part)
- **Keep it simple** (don't over-engineer early)
- **Follow Phoenix conventions** (they exist for good reasons)

---

**This document should give you everything you need to work effectively on this project. When in doubt, refer to the main README.md for architectural context, or the Phoenix guides for framework-specific questions.**

**Happy coding! ♟️**

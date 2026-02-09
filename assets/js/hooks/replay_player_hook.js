/**
 * ReplayPlayer Hook - Client-side playback engine for game replays
 *
 * Handles:
 * - Smooth 60fps playback with requestAnimationFrame
 * - Playback speed control (1x - 5x)
 * - Progress bar scrubbing
 * - Keyboard shortcuts
 * - Clock interpolation for smooth countdown
 * - Checkpoint-based state reconstruction
 */
export const ReplayPlayer = {
  mounted() {
    // Parse data from server
    this.moveHistory = JSON.parse(this.el.dataset.moves || '[]');

    // Use server-calculated duration (includes buffer to show final position)
    this.totalDuration = parseInt(this.el.dataset.totalDuration || '0');

    // Game end metadata (for timeout clock rundown)
    this.gameEndReason = this.el.dataset.gameEndReason || null;
    this.timeoutPosition = this.el.dataset.timeoutPosition || null;

    // Playback state
    this.isPlaying = false;
    this.playbackSpeed = 2.0;
    this.currentTimestamp = 0;
    this.currentMoveIndex = -1;

    // Animation frame tracking
    this.animationFrameId = null;
    this.lastFrameTime = 0;

    // Move animation state
    this.moveAnimating = false;
    this.moveAnimationTimer = null;
    this.pendingAnimationFinish = null;
    this.pendingSlide = null; // FLIP animation waiting for DOM update
    this.skipAnimation = false;

    // Cache clock DOM elements for direct updates
    this.clockElements = {
      board_1_white: null,
      board_1_black: null,
      board_2_white: null,
      board_2_black: null
    };

    // Track last displayed clock values and active state to avoid unnecessary DOM updates
    this.lastDisplayedClocks = null;
    this.lastDisplayedActiveClocks = null;

    // Cache progress bar elements for smooth interpolation
    this.progressFillElement = null;
    this.progressIndicatorElement = null;

    // Set up all event listeners
    this.setupEventListeners();

    // Cache which clocks are active after the last move (for timeout rundown)
    this.postGameActiveClocks = this.gameEndReason === 'timeout'
      ? this.computeActiveClocksAfterLastMove()
      : new Set();

    // Initialize clock display and active state at starting position
    this.initializeStartingPosition();

    // Initialize progress bar at 0%
    this.updateProgressBar();
  },

  /**
   * Called by LiveView after DOM patching. Used to trigger FLIP animations
   * that were queued by animateSlide() — the piece has now been moved to its
   * destination by LiveView, so we can animate from old position to new.
   */
  updated() {
    if (this.pendingSlide) {
      const params = this.pendingSlide;
      this.pendingSlide = null;
      this.startSlideAnimation(params);
    }
  },

  /**
   * Initialize clocks and active state at starting position
   */
  initializeStartingPosition() {
    // Get initial time from first move or use 10 minutes as default
    const initialTime = this.moveHistory.length > 0
      ? this.moveHistory[0].board_1_black_time
      : 600000; // 10 minutes default

    // Set all clocks to initial time
    const initialClocks = {
      board_1_white: initialTime,
      board_1_black: initialTime,
      board_2_white: initialTime,
      board_2_black: initialTime
    };

    // White players are active at start
    const activeClocks = new Set([]);

    // Update display
    this.updateClockDOM(initialClocks, activeClocks);
  },

  /**
   * Set up all DOM event listeners
   */
  setupEventListeners() {
    // Play/pause button
    const playPauseBtn = document.getElementById('replay-play-pause');
    if (playPauseBtn) {
      playPauseBtn.addEventListener('click', () => this.togglePlay());
    }

    // Speed buttons
    document.querySelectorAll('[data-action="set-speed"]').forEach(btn => {
      btn.addEventListener('click', (e) => {
        const speed = parseFloat(e.target.dataset.speed);
        this.setSpeed(speed);
      });
    });

    // Progress bar scrubbing (click and drag)
    const progressBar = document.getElementById('replay-progress');
    if (progressBar) {
      let isDragging = false;

      const seek = (e) => {
        const rect = progressBar.getBoundingClientRect();
        const percent = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
        this.seekToPercent(percent);
      };

      // Click to seek
      progressBar.addEventListener('click', seek);

      // Drag to seek
      progressBar.addEventListener('mousedown', (e) => {
        isDragging = true;
        const wasPlaying = this.isPlaying;
        this.pause();  // Pause while dragging
        seek(e);

        // Store whether we were playing so we can resume after drag
        this._wasPlayingBeforeDrag = wasPlaying;
      });

      document.addEventListener('mousemove', (e) => {
        if (isDragging) {
          seek(e);
        }
      });

      document.addEventListener('mouseup', () => {
        if (isDragging) {
          isDragging = false;
          // Optionally resume playback if it was playing before drag
          // (Uncomment if you want auto-resume)
          // if (this._wasPlayingBeforeDrag) {
          //   this.play();
          // }
        }
      });
    }

    // Keyboard shortcuts
    this.keydownHandler = (e) => {
      // Ignore if user is typing in an input
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
        return;
      }

      if (e.code === 'Space') {
        e.preventDefault();
        this.togglePlay();
      } else if (e.code === 'ArrowLeft') {
        e.preventDefault();
        this.previousMove();
      } else if (e.code === 'ArrowRight') {
        e.preventDefault();
        this.nextMove();
      } else if (['Digit1', 'Digit2', 'Digit3', 'Digit4', 'Digit5'].includes(e.code)) {
        e.preventDefault();
        const speed = parseInt(e.code.charAt(e.code.length - 1));
        this.setSpeed(speed);
      }
    };

    document.addEventListener('keydown', this.keydownHandler);
  },

  /**
   * Toggle between play and pause
   */
  togglePlay() {
    if (this.isPlaying) {
      this.pause();
    } else {
      this.play();
    }
  },

  /**
   * Start playback
   */
  play() {
    // If at the end, restart from beginning
    if (this.currentTimestamp >= this.totalDuration) {
      this.seekToPercent(0);
    }

    this.isPlaying = true;
    this.lastFrameTime = performance.now();
    this.pushEvent("playing_changed", { playing: true });
    this.tick();
  },

  /**
   * Pause playback
   */
  pause() {
    this.isPlaying = false;
    if (this.animationFrameId) {
      cancelAnimationFrame(this.animationFrameId);
      this.animationFrameId = null;
    }
    this.pushEvent("playing_changed", { playing: false });
  },

  /**
   * Animation loop - called every frame during playback
   */
  tick() {
    // Exit immediately if not playing (prevents race conditions)
    if (!this.isPlaying) {
      this.animationFrameId = null;
      return;
    }

    const currentTime = performance.now();
    const deltaTime = currentTime - this.lastFrameTime;
    this.lastFrameTime = currentTime;

    // Freeze game time while a piece is sliding. The tick loop keeps running
    // so we can resume immediately when the animation finishes, but we don't
    // advance the timestamp or trigger new state changes.
    if (!this.moveAnimating) {
      // Advance playback based on speed
      const gameTimeDelta = deltaTime * this.playbackSpeed;
      this.currentTimestamp += gameTimeDelta;

      // Check if we reached the end
      if (this.currentTimestamp >= this.totalDuration) {
        this.currentTimestamp = this.totalDuration;
        this.pause();
        return;  // Exit immediately after pausing
      }

      // Update progress bar smoothly (60fps interpolation)
      this.updateProgressBar();

      // Update clocks locally via DOM (~1fps when seconds change)
      this.updateClocksLocally(this.currentTimestamp);

      // Update full state (FEN, reserves) only on move boundaries
      this.updateStateAtTimestamp(this.currentTimestamp);
    }

    // Schedule next frame only if still playing (double-check to prevent race conditions)
    if (this.isPlaying) {
      this.animationFrameId = requestAnimationFrame(() => this.tick());
    }
  },

  /**
   * Set playback speed
   */
  setSpeed(speed) {
    this.playbackSpeed = speed;
    // Notify LiveView to update UI
    this.pushEvent("speed_changed", { speed });
  },

  /**
   * Seek to a specific percentage of the game
   */
  seekToPercent(percent) {
    const timestamp = this.totalDuration * percent;
    this.seekToTimestamp(timestamp);
  },

  /**
   * Seek to a specific timestamp
   */
  seekToTimestamp(timestamp) {
    this.currentTimestamp = Math.max(0, Math.min(timestamp, this.totalDuration));

    // Cancel any in-progress move animation
    this.cancelMoveAnimation();

    // Force immediate update (even when paused), skip animations for seeks
    this.currentMoveIndex = -1;
    this.skipAnimation = true;
    this.updateProgressBar();  // Update progress bar immediately
    this.updateClocksLocally(this.currentTimestamp);
    this.updateStateAtTimestamp(this.currentTimestamp);
    this.skipAnimation = false;
  },

  /**
   * Find the last move at or before the given timestamp
   */
  findMoveAtTimestamp(timestamp) {
    for (let i = this.moveHistory.length - 1; i >= 0; i--) {
      if (this.moveHistory[i].timestamp <= timestamp) {
        return this.moveHistory[i];
      }
    }
    return null;
  },

  /**
   * Update clocks locally via DOM manipulation
   * Only updates DOM when the displayed second value changes (~1fps)
   */
  updateClocksLocally(timestamp) {
    // Special handling for before first move
    if (this.moveHistory.length > 0 && timestamp < this.moveHistory[0].timestamp) {
      this.updateClocksBeforeFirstMove(timestamp);
      return;
    }

    const prevMove = this.findMoveBeforeTimestamp(timestamp);
    const nextMove = this.findMoveAfterTimestamp(timestamp);

    if (!prevMove) return;

    // Calculate interpolated clock values
    const interpolatedClocks = {};

    ['board_1_white', 'board_1_black', 'board_2_white', 'board_2_black'].forEach(pos => {
      const prevTime = prevMove[`${pos}_time`];

      if (nextMove) {
        const nextTime = nextMove[`${pos}_time`];
        const clockDiff = prevTime - nextTime;

        if (clockDiff > 0) {
          // This clock is counting down - interpolate it
          const ratio = (timestamp - prevMove.timestamp) /
                       (nextMove.timestamp - prevMove.timestamp);
          interpolatedClocks[pos] = Math.round(Math.max(0, prevTime - (clockDiff * ratio)));
        } else {
          // This clock is frozen - use prevMove value
          interpolatedClocks[pos] = prevTime;
        }
      } else if (this.gameEndReason === 'timeout' && this.postGameActiveClocks.has(pos)) {
        // Timeout game: continue counting down active clocks after last move
        const elapsed = timestamp - prevMove.timestamp;
        interpolatedClocks[pos] = Math.max(0, prevTime - elapsed);
      } else {
        // No next move (or inactive clock in timeout) - use prevMove value
        interpolatedClocks[pos] = prevTime;
      }
    });

    // Determine which clocks are active (counting down)
    // Use a threshold to avoid false positives from rounding errors
    // Low threshold (5ms) allows for fast premoves while filtering out timing jitter
    const ACTIVE_THRESHOLD_MS = 5;
    const activeClocks = new Set();
    if (nextMove) {
      ['board_1_white', 'board_1_black', 'board_2_white', 'board_2_black'].forEach(pos => {
        const prevTime = prevMove[`${pos}_time`];
        const nextTime = nextMove[`${pos}_time`];
        const timeDiff = prevTime - nextTime;
        if (timeDiff > ACTIVE_THRESHOLD_MS) {
          activeClocks.add(pos);  // This clock is counting down significantly
        }
      });
    } else if (this.gameEndReason === 'timeout') {
      // After last move in timeout game: show active clocks until they hit 0
      this.postGameActiveClocks.forEach(pos => {
        if (interpolatedClocks[pos] > 0) {
          activeClocks.add(pos);
        }
      });
    }

    // Update DOM if clock values OR active state changed
    if (this.shouldUpdateClockDisplay(interpolatedClocks, activeClocks)) {
      this.updateClockDOM(interpolatedClocks, activeClocks);
      this.lastDisplayedClocks = interpolatedClocks;
      this.lastDisplayedActiveClocks = activeClocks;
    }
  },

  /**
   * Update clocks before the first move
   * Both white players' clocks count down from initial time
   */
  updateClocksBeforeFirstMove(timestamp) {
    const firstMove = this.moveHistory[0];

    // Initial time is what black players have at first move (they haven't moved yet)
    const initialTime = firstMove.board_1_black_time;

    // Both white players' clocks count down from game start
    const whiteTimeElapsed = timestamp;

    const interpolatedClocks = {
      board_1_white: Math.max(0, initialTime - whiteTimeElapsed),
      board_1_black: initialTime,
      board_2_white: Math.max(0, initialTime - whiteTimeElapsed),
      board_2_black: initialTime
    };

    // White players are active before first move
    const activeClocks = new Set(['board_1_white', 'board_2_white']);

    if (this.shouldUpdateClockDisplay(interpolatedClocks, activeClocks)) {
      this.updateClockDOM(interpolatedClocks, activeClocks);
      this.lastDisplayedClocks = interpolatedClocks;
      this.lastDisplayedActiveClocks = activeClocks;
    }
  },

  /**
   * Check if any clock's displayed second value or active state changed
   * Avoids unnecessary DOM updates (reduces from 60fps to ~1fps)
   */
  shouldUpdateClockDisplay(newClocks, newActiveClocks) {
    if (!this.lastDisplayedClocks) return true;

    // Check if any clock's second value changed
    for (const pos of ['board_1_white', 'board_1_black', 'board_2_white', 'board_2_black']) {
      const oldSeconds = Math.floor(this.lastDisplayedClocks[pos] / 1000);
      const newSeconds = Math.floor(newClocks[pos] / 1000);

      if (oldSeconds !== newSeconds) {
        return true;  // At least one clock changed seconds
      }
    }

    // Check if active state changed for any clock
    if (this.lastDisplayedActiveClocks) {
      for (const pos of ['board_1_white', 'board_1_black', 'board_2_white', 'board_2_black']) {
        const wasActive = this.lastDisplayedActiveClocks.has(pos);
        const isActive = newActiveClocks.has(pos);

        if (wasActive !== isActive) {
          return true;  // Active state changed for this clock
        }
      }
    }

    return false;  // No clocks changed seconds and active state unchanged
  },

  /**
   * Update progress bar based on current timestamp
   * Provides smooth 60fps progress bar animation
   */
  updateProgressBar() {
    // Find or cache the progress bar elements
    if (!this.progressFillElement) {
      this.progressFillElement = document.querySelector('[data-progress-fill]');
      this.progressIndicatorElement = document.querySelector('[data-progress-indicator]');
    }

    if (this.totalDuration > 0) {
      const progressPercent = (this.currentTimestamp / this.totalDuration) * 100;
      const clampedPercent = Math.min(100, Math.max(0, progressPercent));

      // Update fill width
      if (this.progressFillElement) {
        this.progressFillElement.style.width = `${clampedPercent}%`;
      }

      // Update indicator position (offset by half its width: 8px)
      if (this.progressIndicatorElement) {
        this.progressIndicatorElement.style.left = `calc(${clampedPercent}% - 8px)`;
      }
    }
  },

  /**
   * Update clock DOM elements - uses textContent for instant, jitter-free updates
   */
  updateClockDOM(clocks, activeClocks = new Set()) {
    ['board_1_white', 'board_1_black', 'board_2_white', 'board_2_black'].forEach(pos => {
      // Find or cache the clock container
      if (!this.clockElements[pos]) {
        this.clockElements[pos] = document.getElementById(`clock-${pos}`);
      }

      const clockContainer = this.clockElements[pos];
      if (clockContainer && clocks[pos] !== undefined) {
        const timeMs = clocks[pos];
        const totalSeconds = Math.floor(timeMs / 1000);
        const minutes = Math.floor(totalSeconds / 60);
        const seconds = totalSeconds % 60;

        // Update minutes and seconds directly (bypasses DaisyUI --value for performance)
        const minutesSpan = clockContainer.querySelector('[data-minutes]');
        const secondsSpan = clockContainer.querySelector('[data-seconds]');

        if (minutesSpan) {
          minutesSpan.textContent = minutes;
        }
        if (secondsSpan) {
          const secondsStr = seconds.toString().padStart(2, '0');
          secondsSpan.textContent = secondsStr;
        }

        // Determine urgency and active state for clock styling
        const isActive = activeClocks.has(pos);
        let urgency = 'normal';
        if (timeMs <= 10000) urgency = 'critical';
        else if (timeMs <= 30000) urgency = 'low';

        const stateClass = `chess-clock-state-${urgency}-${isActive ? 'active' : 'inactive'}`;

        // Replace previous state class (tracked via data attribute)
        const oldState = clockContainer.dataset.clockState;
        if (oldState && oldState !== stateClass) {
          clockContainer.classList.remove(oldState);
        }
        clockContainer.dataset.clockState = stateClass;
        clockContainer.classList.add(stateClass);

        // Pulse animation for critical + active
        if (urgency === 'critical' && isActive) {
          clockContainer.classList.add('animate-pulse');
        } else {
          clockContainer.classList.remove('animate-pulse');
        }

        // Active data attribute (for other consumers)
        if (isActive) {
          clockContainer.setAttribute('data-active', 'true');
        } else {
          clockContainer.removeAttribute('data-active');
        }
      }
    });
  },

  /**
   * Find the last move before or at the given timestamp
   * Returns null if timestamp is before the first move
   */
  findMoveBeforeTimestamp(timestamp) {
    for (let i = this.moveHistory.length - 1; i >= 0; i--) {
      if (this.moveHistory[i].timestamp <= timestamp) {
        return this.moveHistory[i];
      }
    }
    return null;
  },

  /**
   * Find the first move after the given timestamp
   */
  findMoveAfterTimestamp(timestamp) {
    for (let i = 0; i < this.moveHistory.length; i++) {
      if (this.moveHistory[i].timestamp > timestamp) {
        return this.moveHistory[i];
      }
    }
    return null;
  },

  /**
   * Compute which clocks are active after the last move.
   * On each board, the opponent of the last mover has their clock running.
   * If no moves were made on a board, white's clock is active (starting position).
   */
  computeActiveClocksAfterLastMove() {
    const active = new Set();

    const lastMoveBoard1 = [...this.moveHistory].reverse().find(m => m.board === 1);
    const lastMoveBoard2 = [...this.moveHistory].reverse().find(m => m.board === 2);

    active.add(lastMoveBoard1
      ? this.getOpponentPosition(lastMoveBoard1.position)
      : 'board_1_white');

    active.add(lastMoveBoard2
      ? this.getOpponentPosition(lastMoveBoard2.position)
      : 'board_2_white');

    return active;
  },

  /**
   * Get the opponent position on the same board.
   */
  getOpponentPosition(position) {
    const opponents = {
      'board_1_white': 'board_1_black',
      'board_1_black': 'board_1_white',
      'board_2_white': 'board_2_black',
      'board_2_black': 'board_2_white'
    };
    return opponents[position];
  },

  /**
   * Go to the previous move
   */
  previousMove() {
    if (this.currentMoveIndex > 0) {
      const move = this.moveHistory[this.currentMoveIndex - 1];
      this.seekToTimestamp(move.timestamp);
    }
  },

  /**
   * Go to the next move
   */
  nextMove() {
    if (this.currentMoveIndex < this.moveHistory.length) {
      const move = this.moveHistory[this.currentMoveIndex];
      this.seekToTimestamp(move.timestamp);
    }
  },

  /**
   * Update state at a specific timestamp.
   * During playback: steps one move at a time (currentMoveIndex + 1) so
   * every move gets a chance to animate, even when rapid engine moves
   * cause the timestamp to jump past several at once.
   * During seeks: jumps directly to the target move (no animation).
   */
  updateStateAtTimestamp(timestamp) {
    let move, newMoveIndex, shouldAnimate;

    if (this.skipAnimation) {
      // Seeking: jump directly to the target move
      move = this.findMoveAtTimestamp(timestamp);
      if (!move) return;
      newMoveIndex = this.moveHistory.indexOf(move);
      shouldAnimate = false;
    } else {
      // Playback: step to the NEXT move only, never skip ahead
      const nextIdx = this.currentMoveIndex + 1;
      if (nextIdx >= this.moveHistory.length) return;

      const nextMove = this.moveHistory[nextIdx];
      if (nextMove.timestamp > timestamp) return; // Not time yet

      move = nextMove;
      newMoveIndex = nextIdx;

      // Safety: if previous animation is still running, finish it first
      if (this.moveAnimating) {
        this.finishCurrentAnimation();
      }
      shouldAnimate = !this.moveAnimating;
    }

    if (newMoveIndex === this.currentMoveIndex) return;

    const oldMoveIndex = this.currentMoveIndex;
    this.currentMoveIndex = newMoveIndex;

    // Check if move has FEN data (old games may not have FEN stored)
    if (!move.board_1_fen || !move.board_2_fen) {
      this.pause();
      return;
    }

    // Push FEN, reserves to LiveView (only when crossing move boundaries)
    // Clocks are updated locally via DOM, not sent to LiveView
    const state = {
      board_1_fen: move.board_1_fen,
      board_2_fen: move.board_2_fen,
      board_1_white_reserves: move.board_1_white_reserves || [],
      board_1_black_reserves: move.board_1_black_reserves || [],
      board_2_white_reserves: move.board_2_white_reserves || [],
      board_2_black_reserves: move.board_2_black_reserves || [],
      move_index: newMoveIndex
    };

    if (shouldAnimate && move.type === 'move' && move.notation && move.notation.length >= 4) {
      this.animateSlide(move, oldMoveIndex, state);
    } else if (shouldAnimate && move.type === 'drop' && move.notation) {
      this.animateDrop(move, oldMoveIndex, state);
    } else {
      this.pushEvent("update_state", state);
    }
  },

  // ── Move Animation Methods ──────────────────────────────────────────

  /**
   * Animate a piece sliding using the FLIP technique.
   *
   * FLIP = First, Last, Invert, Play:
   * 1. FIRST: snapshot the piece's screen position before the DOM update
   * 2. Push state to LiveView (DOM gets patched with new FEN)
   * 3. LAST: (in updated() → startSlideAnimation) find the piece at its new position
   * 4. INVERT: apply a reverse transform so it visually appears at the old position
   * 5. PLAY: animate the transform to (0,0) so it slides into place
   *
   * This approach works WITH LiveView's DOM patching instead of racing against it.
   */
  animateSlide(move, oldMoveIndex, state) {
    const from = move.notation.substring(0, 2);
    const boardNum = move.board;
    const isFlipped = boardNum === 2;

    const grid = this.getBoardGrid(boardNum);
    if (!grid) { this.pushEvent("update_state", state); return; }

    const fromIdx = this.algebraicToGridIndex(from, isFlipped);
    const fromSquare = grid.children[fromIdx];
    if (!fromSquare) { this.pushEvent("update_state", state); return; }

    // FIRST: snapshot where the piece is right now
    const firstRect = fromSquare.getBoundingClientRect();

    const to = move.notation.substring(2, 4);
    const toIdx = this.algebraicToGridIndex(to, isFlipped);

    this.moveAnimating = true;

    // Store params for the animation — started by updated() after DOM patch
    this.pendingSlide = {
      firstRect,
      toIdx,
      boardNum,
      duration: Math.max(200, 450 - 50 * this.playbackSpeed)
    };

    // Push state to LiveView — triggers DOM patch, then updated() callback
    this.pushEvent("update_state", state);
  },

  /**
   * Run the FLIP slide animation after LiveView has patched the DOM.
   * Called from updated() when pendingSlide is set.
   */
  startSlideAnimation({ firstRect, toIdx, boardNum, duration, dropInfo }) {
    const grid = this.getBoardGrid(boardNum);
    if (!grid) { this.moveAnimating = false; return; }

    const destSquare = grid.children[toIdx];
    if (!destSquare) { this.moveAnimating = false; return; }

    const destPiece = destSquare.querySelector('.chess-piece');
    if (!destPiece) { this.moveAnimating = false; return; }

    // LAST: where the piece is now (at destination, after DOM update)
    const lastRect = destSquare.getBoundingClientRect();

    // INVERT: offset from new position back to old position
    const dx = firstRect.left - lastRect.left;
    const dy = firstRect.top - lastRect.top;

    // Skip if no visual movement (shouldn't happen, but safety check)
    if (dx === 0 && dy === 0) { this.moveAnimating = false; return; }

    // Allow the piece to render outside the destination square during slide
    destSquare.style.overflow = 'visible';

    // Flash the reserve button for drops — find fresh from DOM after patch
    const flashedBtn = dropInfo
      ? this.findReservePieceButton(dropInfo.position, dropInfo.piece)
      : null;
    if (flashedBtn) {
      flashedBtn.style.animation = 'none';
      flashedBtn.offsetHeight;
      flashedBtn.style.animation = `replay-reserve-flash ${duration}ms ease-out`;
    }

    // Instantly position piece at old location (reverse transform)
    destPiece.classList.add('replay-sliding');
    destPiece.style.transition = 'none';
    destPiece.style.transform = `translate(${dx}px, ${dy}px)`;

    // Force reflow so the reverse transform is applied before animation
    destPiece.offsetHeight;

    // PLAY: animate to actual position (0,0)
    destPiece.style.transition = `transform ${duration}ms ease`;
    destPiece.style.transform = 'translate(0, 0)';

    this.pendingAnimationFinish = () => {
      if (this.moveAnimationTimer) {
        clearTimeout(this.moveAnimationTimer);
        this.moveAnimationTimer = null;
      }
      destPiece.classList.remove('replay-sliding');
      destPiece.style.transition = '';
      destPiece.style.transform = '';
      destSquare.style.overflow = '';
      if (flashedBtn) flashedBtn.style.animation = '';
      this.moveAnimating = false;
      this.pendingAnimationFinish = null;
    };

    this.moveAnimationTimer = setTimeout(() => {
      if (this.pendingAnimationFinish) this.pendingAnimationFinish();
    }, duration);
  },

  /**
   * Animate a piece drop using the FLIP technique.
   * Snapshots the reserve button position, pushes state, then
   * startSlideAnimation slides the piece from the reserve to the board.
   */
  animateDrop(move, oldMoveIndex, state) {
    const boardNum = move.board;
    const isFlipped = boardNum === 2;

    // Drop notation is "P@e4" (piece@square) — extract destination and piece
    const atIdx = move.notation.indexOf('@');
    const destAlgebraic = atIdx >= 0 ? move.notation.substring(atIdx + 1) : move.notation;
    const notationPiece = atIdx >= 0 ? move.notation.substring(0, atIdx).toLowerCase() : null;

    // Determine which piece was dropped (three strategies):
    // 1. From the notation itself (most reliable)
    // 2. Read FEN at destination square
    // 3. Diff reserves before/after
    const boardFen = boardNum === 1 ? move.board_1_fen : move.board_2_fen;
    const fenPiece = this.getPieceAtSquare(boardFen, destAlgebraic);
    const diffPiece = this.getDroppedPieceType(oldMoveIndex, move);
    const droppedPiece = notationPiece || fenPiece || diffPiece;

    // Find the source rect: specific reserve button, or the reserves container
    let firstRect = null;
    if (droppedPiece) {
      const reserveBtn = this.findReservePieceButton(move.position, droppedPiece);
      if (reserveBtn) {
        firstRect = reserveBtn.getBoundingClientRect();
      }
    }
    if (!firstRect) {
      // Fallback: use the reserves container center
      const reservesContainer = this.findReservesContainer(move.position);
      if (reservesContainer) {
        firstRect = reservesContainer.getBoundingClientRect();
      }
    }

    if (!firstRect) { this.pushEvent("update_state", state); return; }

    const toIdx = this.algebraicToGridIndex(destAlgebraic, isFlipped);
    const duration = Math.max(200, 450 - 50 * this.playbackSpeed);

    this.moveAnimating = true;

    // Reuse the same pendingSlide mechanism — startSlideAnimation works
    // for any source rect (board square or reserve button)
    this.pendingSlide = {
      firstRect,
      toIdx,
      boardNum,
      duration,
      // Store drop info so startSlideAnimation can find the button fresh from DOM
      dropInfo: droppedPiece ? { position: move.position, piece: droppedPiece } : null
    };

    // Push state to LiveView — triggers DOM patch, then updated() callback
    this.pushEvent("update_state", state);
  },

  /**
   * Cancel any in-progress move animation without completing it.
   * Used for seeks/jumps where the pending state is stale.
   */
  cancelMoveAnimation() {
    this.pendingSlide = null;
    if (this.moveAnimationTimer) {
      clearTimeout(this.moveAnimationTimer);
      this.moveAnimationTimer = null;
    }
    this.moveAnimating = false;
    this.pendingAnimationFinish = null;

    // Clean up any lingering animation styles
    document.querySelectorAll('.replay-sliding').forEach(el => {
      el.classList.remove('replay-sliding');
      el.style.transition = '';
      el.style.transform = '';
      // Restore overflow on parent square
      if (el.parentElement) {
        el.parentElement.style.overflow = '';
      }
    });
  },

  /**
   * Instantly complete the current animation (snap piece to final position).
   * Used when the next sequential move arrives before the current
   * animation finishes (e.g. rapid engine moves).
   */
  finishCurrentAnimation() {
    if (this.pendingSlide) {
      // Animation was waiting for DOM update — just skip it
      this.pendingSlide = null;
      this.moveAnimating = false;
      return;
    }
    if (this.moveAnimationTimer) {
      clearTimeout(this.moveAnimationTimer);
      this.moveAnimationTimer = null;
    }
    if (this.pendingAnimationFinish) {
      this.pendingAnimationFinish();
    }
  },

  // ── Animation Helpers ───────────────────────────────────────────────

  /**
   * Get the grid container element for a board number
   */
  getBoardGrid(boardNum) {
    const wrapper = document.getElementById(`replay-board-${boardNum}`);
    return wrapper?.querySelector('[data-chess-board] > div');
  },

  /**
   * Convert algebraic notation (e.g. "e4") to a CSS grid child index.
   * Board 1 is unflipped, Board 2 is flipped.
   */
  algebraicToGridIndex(algebraic, isFlipped) {
    const file = algebraic.charCodeAt(0) - 97; // a=0, h=7
    const rank = parseInt(algebraic[1]);        // 1-8

    if (isFlipped) {
      // Flipped: rank 1 at top, file h on left
      const row = rank - 1;
      const col = 7 - file;
      return row * 8 + col;
    } else {
      // Normal: rank 8 at top, file a on left
      const row = 8 - rank;
      const col = file;
      return row * 8 + col;
    }
  },

  /**
   * Determine which piece type was dropped by comparing reserves before/after.
   * Returns a lowercase letter ('p','n','b','r','q') or null.
   */
  getDroppedPieceType(oldMoveIndex, currentMove) {
    const posKey = `${currentMove.position}_reserves`;
    const prevReserves = oldMoveIndex >= 0
      ? (this.moveHistory[oldMoveIndex][posKey] || [])
      : [];
    const newReserves = currentMove[posKey] || [];

    const count = (arr) => {
      const c = {};
      arr.forEach(p => { c[p] = (c[p] || 0) + 1; });
      return c;
    };

    const oldCounts = count(prevReserves);
    const newCounts = count(newReserves);

    for (const piece of ['q', 'r', 'b', 'n', 'p']) {
      if ((oldCounts[piece] || 0) > (newCounts[piece] || 0)) {
        return piece;
      }
    }
    return null;
  },

  /**
   * Read the piece at a given square from a FEN string.
   * Returns a lowercase letter ('p','n','b','r','q','k') or null.
   * Handles full FEN (with active color, castling, etc.) and BFEN (with brackets).
   */
  getPieceAtSquare(fen, algebraic) {
    if (!fen || !algebraic || algebraic.length < 2) return null;
    const file = algebraic.charCodeAt(0) - 97; // a=0, h=7
    const rank = parseInt(algebraic[1]);        // 1-8
    if (isNaN(rank) || file < 0 || file > 7) return null;
    const row = 8 - rank;                       // FEN starts from rank 8

    // Extract only the piece placement part:
    // strip BFEN brackets and any FEN fields after a space
    const placement = fen.split(/[\s[]/)[0];
    const rows = placement.split('/');
    if (row < 0 || row >= rows.length) return null;

    const fenRow = rows[row];
    if (!fenRow) return null;

    let col = 0;
    for (const ch of fenRow) {
      if (ch >= '1' && ch <= '8') {
        col += parseInt(ch);
      } else if (ch === '~') {
        // Skip promoted piece marker
        continue;
      } else {
        if (col === file) return ch.toLowerCase();
        col++;
      }
    }
    return null;
  },

  /**
   * Find the reserve piece button in the DOM for a given position and piece type.
   * Navigates from the clock element (which has a known ID) to the reserves section.
   */
  findReservePieceButton(position, pieceLetter) {
    return document.querySelector(`#reserves-${position} [phx-value-piece="${pieceLetter}"]`);
  },

  /**
   * Find the reserves container element for a given position.
   * Used as a fallback when the specific piece button can't be identified.
   */
  findReservesContainer(position) {
    return document.getElementById(`reserves-${position}`);
  },

  /**
   * Cleanup when the component is destroyed
   */
  destroyed() {
    // Cancel any ongoing animation
    if (this.animationFrameId) {
      cancelAnimationFrame(this.animationFrameId);
    }
    this.cancelMoveAnimation();

    // Remove event listeners
    if (this.keydownHandler) {
      document.removeEventListener('keydown', this.keydownHandler);
    }
  }
};

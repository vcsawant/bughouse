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

    // Use server-calculated duration (includes 3s buffer to show final position)
    this.totalDuration = parseInt(this.el.dataset.totalDuration || '0');

    // Playback state
    this.isPlaying = false;
    this.playbackSpeed = 2.0;
    this.currentTimestamp = 0;
    this.currentMoveIndex = -1;

    // Animation frame tracking
    this.animationFrameId = null;
    this.lastFrameTime = 0;

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

    // Initialize clock display and active state at starting position
    this.initializeStartingPosition();

    // Initialize progress bar at 0%
    this.updateProgressBar();
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

    // Force immediate update (even when paused)
    this.currentMoveIndex = -1;
    this.updateProgressBar();  // Update progress bar immediately
    this.updateClocksLocally(this.currentTimestamp);
    this.updateStateAtTimestamp(this.currentTimestamp);
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
      } else {
        // No next move - use prevMove value
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

        // Update active state styling (matches game_live appearance)
        const isActive = activeClocks.has(pos);
        if (isActive) {
          clockContainer.setAttribute('data-active', 'true');
          // Add active styling classes (full visual treatment)
          clockContainer.classList.add('ring-4', 'ring-primary', 'ring-opacity-50');
          clockContainer.classList.add('bg-primary', 'text-primary-content', 'border-primary');
          // Remove inactive styling
          clockContainer.classList.remove('bg-base-200', 'text-base-content', 'border-base-300', 'opacity-60');
        } else {
          clockContainer.removeAttribute('data-active');
          // Remove active styling classes
          clockContainer.classList.remove('ring-4', 'ring-primary', 'ring-opacity-50');
          clockContainer.classList.remove('bg-primary', 'text-primary-content', 'border-primary');
          // Add inactive styling
          clockContainer.classList.add('bg-base-200', 'text-base-content', 'border-base-300', 'opacity-60');
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
   * Update state at a specific timestamp
   * Only pushes to LiveView when crossing move boundaries (FEN/reserves change)
   */
  updateStateAtTimestamp(timestamp) {
    // Find the last move at or before this timestamp
    const move = this.findMoveAtTimestamp(timestamp);

    if (!move) {
      // Before first move - show starting position
      return;
    }

    const newMoveIndex = this.moveHistory.indexOf(move);

    // Only update LiveView when we cross move boundaries
    // Clocks are updated locally via DOM (see updateClocksLocally)
    if (newMoveIndex === this.currentMoveIndex) {
      return;
    }

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
      // Each player has their own reserves
      board_1_white_reserves: move.board_1_white_reserves || [],
      board_1_black_reserves: move.board_1_black_reserves || [],
      board_2_white_reserves: move.board_2_white_reserves || [],
      board_2_black_reserves: move.board_2_black_reserves || [],
      move_index: newMoveIndex
    };

    this.pushEvent("update_state", state);
  },

  /**
   * Cleanup when the component is destroyed
   */
  destroyed() {
    // Cancel any ongoing animation
    if (this.animationFrameId) {
      cancelAnimationFrame(this.animationFrameId);
    }

    // Remove event listeners
    if (this.keydownHandler) {
      document.removeEventListener('keydown', this.keydownHandler);
    }
  }
};

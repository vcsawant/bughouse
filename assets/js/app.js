// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/bughouse"
import topbar from "../vendor/topbar"
import {ReplayPlayer} from "./hooks/replay_player_hook"

// Shared clock state manager - ensures all clocks tick in sync
const ClockManager = {
  // Single master interval for all clocks
  interval: null,

  // List of registered clock hooks (max 4 in Bughouse)
  clocks: [],

  // Start the master interval if not already running
  start() {
    if (!this.interval) {
      this.interval = setInterval(() => {
        this.tick()
      }, 1000)
    }
  },

  // Stop the master interval (when all clocks destroyed)
  stop() {
    if (this.interval) {
      clearInterval(this.interval)
      this.interval = null
    }
  },

  // Tick all registered active clocks
  tick() {
    let hasActiveClock = false

    for (const clock of this.clocks) {
      if (clock.active && clock.timeMs > 0) {
        hasActiveClock = true
        clock.timeMs = Math.max(0, clock.timeMs - 1000)
        clock.updateDisplay()
      }
    }

    // Stop the interval if no clocks are active (e.g., game ended)
    if (!hasActiveClock && this.clocks.length > 0) {
      this.stop()
    }
  },

  // Register a clock hook
  register(clock) {
    this.clocks.push(clock)
    this.start()
  },

  // Unregister a clock hook
  unregister(clock) {
    const index = this.clocks.indexOf(clock)
    if (index > -1) {
      this.clocks.splice(index, 1)
    }
    if (this.clocks.length === 0) {
      this.stop()
    }
  }
}

// Chess Clock Countdown Hook
// Counts down client-side and reconciles with server updates
const ChessClockCountdown = {
  mounted() {
    // Initialize time and active state
    this.timeMs = parseInt(this.el.dataset.timeMs) || 0
    // Check if data-active attribute exists (boolean attribute pattern)
    // Phoenix renders: active={true} → data-active (no value), active={false} → no attribute
    this.active = this.el.hasAttribute('data-active')

    // Get countdown elements (direct text spans)
    this.minutesEl = this.el.querySelector('[data-minutes]')
    this.secondsEl = this.el.querySelector('[data-seconds]')

    // Register with the shared manager
    ClockManager.register(this)

    // Initial display update
    this.updateDisplay()
  },

  updated() {
    // Re-query DOM elements in case LiveView replaced them during re-render
    this.minutesEl = this.el.querySelector('[data-minutes]')
    this.secondsEl = this.el.querySelector('[data-seconds]')

    // Reconcile with server time
    const newTimeMs = parseInt(this.el.dataset.timeMs) || 0
    // Check if data-active attribute exists (boolean attribute pattern)
    const newActive = this.el.hasAttribute('data-active')

    // Determine if we should reset the time
    const isStateChanging = newActive !== this.active
    const isInactive = !this.active && !newActive
    const drift = Math.abs(this.timeMs - newTimeMs)
    const hasSignificantDrift = drift > 2000 // More than 2 seconds off

    // Only reset time when:
    // 1. Clock state is changing (becoming active/inactive)
    // 2. Clock is currently inactive (always sync inactive clocks)
    // 3. Time has drifted significantly from server (desync recovery)
    if (isStateChanging || isInactive || hasSignificantDrift) {
      this.timeMs = newTimeMs
    }
    // Otherwise, let active clock continue counting smoothly

    // Update active state - ClockManager will handle ticking based on this flag
    this.active = newActive
    this.updateDisplay()
  },


  updateDisplay() {
    if (!this.minutesEl || !this.secondsEl) {
      return
    }

    const totalSeconds = Math.floor(this.timeMs / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60

    // Update clock display directly via textContent (instant, no jitter)
    this.minutesEl.textContent = minutes
    this.secondsEl.textContent = seconds.toString().padStart(2, '0')
  },

  destroyed() {
    // Unregister from the shared manager
    ClockManager.unregister(this)
  }
}

// Chess piece hover preview hook
const ChessPieceHover = {
  mounted() {
    const square = this.el.dataset.square
    const board = this.el.dataset.board

    // Show hover preview on mouseenter
    this.el.addEventListener("mouseenter", (e) => {
      // Only show hover if we're hovering over a piece
      const hasPiece = this.el.querySelector(".chess-piece") !== null
      if (hasPiece) {
        this.pushEvent("hover_piece", { square, board })
      }
    })

    // Clear hover preview on mouseleave
    this.el.addEventListener("mouseleave", (e) => {
      this.pushEvent("unhover_piece", {})
    })
  }
}

// Chess piece drag-and-drop hook
const ChessPieceDrag = {
  mounted() {
    this.draggedSquare = null
    this.draggedPiece = null
    this.setupDragAndDrop()
  },

  updated() {
    // Re-apply dragging state if still in drag
    // This handles LiveView re-renders that replace DOM elements
    if (this.draggedSquare) {
      const currentPiece = this.el.querySelector(`[data-square="${this.draggedSquare}"] .chess-piece`)
      if (currentPiece) {
        currentPiece.classList.add('is-being-dragged')
        this.draggedPiece = currentPiece // Update reference to new DOM element
      }
    }
  },

  setupDragAndDrop() {
    const boardElement = this.el

    // Handle drag start on pieces
    boardElement.addEventListener("dragstart", (e) => {
      // Check if we're dragging a piece (not the square itself)
      if (e.target.classList.contains("chess-piece")) {
        const square = e.target.dataset.square
        const board = boardElement.dataset.board

        console.log("[Drag] Starting drag from square:", square, "on board:", board)
        this.draggedSquare = square
        this.draggedPiece = e.target

        // Select the piece (triggers server validation and highlighting)
        this.pushEvent("select_square", { square, board })

        // Visual feedback - hide the original piece to simulate picking it up
        e.dataTransfer.effectAllowed = "move"
        e.dataTransfer.setData("text/plain", square)

        // Create a custom drag image for better visual feedback
        // Clone the piece to use as drag image
        const dragImage = e.target.cloneNode(true)
        dragImage.style.position = 'absolute'
        dragImage.style.top = '-1000px' // Move offscreen
        dragImage.style.opacity = '0.9'
        dragImage.classList.remove('is-being-dragged') // Don't fade the drag image
        document.body.appendChild(dragImage)

        // Set the custom drag image (offset to center of cursor)
        e.dataTransfer.setDragImage(dragImage, 25, 25)

        // Clean up the temporary drag image after a short delay
        setTimeout(() => document.body.removeChild(dragImage), 0)

        // Hide the original piece using CSS class (survives LiveView re-renders)
        // Use setTimeout to avoid affecting the drag image
        setTimeout(() => {
          e.target.classList.add('is-being-dragged')
        }, 0)
      } else {
        console.log("[Drag] Drag started but target is not a chess-piece:", e.target)
      }
    })

    // Handle drag end (cleanup)
    boardElement.addEventListener("dragend", (e) => {
      if (e.target.classList.contains("chess-piece")) {
        // Remove the dragging class
        e.target.classList.remove('is-being-dragged')

        // Also remove from the tracked piece if it's different (due to LiveView re-render)
        if (this.draggedPiece && this.draggedPiece !== e.target) {
          this.draggedPiece.classList.remove('is-being-dragged')
        }

        this.draggedSquare = null
        this.draggedPiece = null
      }
    })

    // Handle drag over (allow drop on valid squares)
    boardElement.addEventListener("dragover", (e) => {
      if (this.draggedSquare) {
        e.preventDefault() // Allow drop
        e.dataTransfer.dropEffect = "move"
      }
    })

    // Handle drop
    boardElement.addEventListener("drop", (e) => {
      e.preventDefault()

      if (!this.draggedSquare) {
        console.log("[Drag] Drop event but no draggedSquare set")
        return
      }

      // Find the square we dropped on
      const dropTarget = e.target.closest('[data-square]')
      if (dropTarget) {
        const toSquare = dropTarget.dataset.square
        const board = boardElement.dataset.board

        console.log("[Drag] Dropped on square:", toSquare, "from:", this.draggedSquare)

        // If dropping on the same square, just deselect
        if (toSquare === this.draggedSquare) {
          console.log("[Drag] Same square, deselecting")
          this.pushEvent("deselect_all", {})
        } else {
          console.log("[Drag] Different square, attempting move")
          // Attempt the move (server will validate)
          // The existing select_square handler will handle move logic
          this.pushEvent("select_square", { square: toSquare, board })
        }
      } else {
        console.log("[Drag] No drop target found")
      }

      // Clean up - dragend will also fire and handle cleanup
    })

    // Visual feedback on drag enter/leave
    boardElement.addEventListener("dragenter", (e) => {
      const target = e.target.closest('[data-square]')
      if (target && this.draggedSquare && target.dataset.square !== this.draggedSquare) {
        target.classList.add("drag-over")
      }
    })

    boardElement.addEventListener("dragleave", (e) => {
      const target = e.target.closest('[data-square]')
      if (target) {
        target.classList.remove("drag-over")
      }
    })
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {
    ...colocatedHooks,
    ChessClockCountdown,
    ChessPieceHover,
    ChessPieceDrag,
    ReplayPlayer
  },
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}


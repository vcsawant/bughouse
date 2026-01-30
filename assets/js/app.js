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

// Chess Clock Countdown Hook
// Counts down client-side and reconciles with server updates
const ChessClockCountdown = {
  mounted() {
    this.timeMs = parseInt(this.el.dataset.timeMs) || 0
    // Check if data-active attribute exists (boolean attribute pattern)
    // Phoenix renders: active={true} → data-active (no value), active={false} → no attribute
    this.active = this.el.hasAttribute('data-active')

    // Get countdown elements (the inner spans with --value style)
    // DaisyUI countdown structure: <span class="countdown"><span style="--value:X"></span></span>
    const minutesContainer = this.el.querySelector('[data-minutes]')
    const secondsContainer = this.el.querySelector('[data-seconds]')

    // Get the inner span elements that hold the --value
    this.minutesEl = minutesContainer?.querySelector('span')
    this.secondsEl = secondsContainer?.querySelector('span')

    // Start countdown if active
    if (this.active) {
      this.startCountdown()
    }

    this.updateDisplay()
  },

  updated() {
    // Reconcile with server time
    const newTimeMs = parseInt(this.el.dataset.timeMs) || 0
    // Check if data-active attribute exists (boolean attribute pattern)
    const newActive = this.el.hasAttribute('data-active')

    // Update time from server (reconciliation)
    this.timeMs = newTimeMs

    // Handle active state change
    if (newActive && !this.active) {
      this.startCountdown()
    } else if (!newActive && this.active) {
      this.stopCountdown()
    }

    this.active = newActive
    this.updateDisplay()
  },

  startCountdown() {
    if (this.countdownInterval) {
      clearInterval(this.countdownInterval)
    }

    // Update every 1000ms for second precision (MM:SS format)
    this.countdownInterval = setInterval(() => {
      if (this.timeMs > 0) {
        this.timeMs = Math.max(0, this.timeMs - 1000)
        this.updateDisplay()
      } else {
        this.stopCountdown()
      }
    }, 1000)
  },

  stopCountdown() {
    if (this.countdownInterval) {
      clearInterval(this.countdownInterval)
      this.countdownInterval = null
    }
  },

  updateDisplay() {
    if (!this.minutesEl || !this.secondsEl) {
      return
    }

    const totalSeconds = Math.floor(this.timeMs / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60

    // Update DaisyUI countdown values on the inner span elements
    this.minutesEl.style.setProperty('--value', minutes)
    this.secondsEl.style.setProperty('--value', seconds)
  },

  destroyed() {
    this.stopCountdown()
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {
    ...colocatedHooks,
    ChessClockCountdown
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


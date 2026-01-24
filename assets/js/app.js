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

// Chess Clock Monitoring Hook
// Detects when timer updates are stale (connection lag/disconnect)
const ChessClockMonitor = {
  mounted() {
    this.checkInterval = setInterval(() => this.checkStaleness(), 1000)
    this.lagWarning = this.el.querySelector('[data-lag-warning]')
    this.activeIndicator = this.el.querySelector('[data-active-indicator]')
  },

  updated() {
    // Reset staleness check when we receive an update
    this.lastUpdateTime = Date.now()
    if (this.lagWarning) {
      this.lagWarning.classList.add('hidden')
    }
  },

  checkStaleness() {
    const lastUpdate = parseInt(this.el.dataset.lastUpdate) || Date.now()
    const now = Date.now()
    const staleness = now - lastUpdate

    // Show warning if no update in 5 seconds
    const STALE_THRESHOLD = 5000

    if (staleness > STALE_THRESHOLD && this.lagWarning) {
      this.lagWarning.classList.remove('hidden')

      // Also dim the active indicator if present
      if (this.activeIndicator) {
        this.activeIndicator.style.opacity = '0.3'
      }
    } else {
      if (this.lagWarning) {
        this.lagWarning.classList.add('hidden')
      }
      if (this.activeIndicator) {
        this.activeIndicator.style.opacity = '1'
      }
    }
  },

  destroyed() {
    if (this.checkInterval) {
      clearInterval(this.checkInterval)
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {
    ...colocatedHooks,
    ChessClockMonitor
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


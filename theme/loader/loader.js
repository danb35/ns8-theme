
;/* ns8-theme loader. Appended to cluster-admin's config.production.js by the
   ns8-theme module. See DESIGN.md section 3.3. Must never throw into core. */
(function () {
  try {
    var NS = window.NS8_THEME_CONF || {};
    var MODES = ["light", "dark", "system"];
    var COOKIE = "ns8_theme";
    var root = document.documentElement;

    function readMode() {
      var m = document.cookie.match(/(?:^|;\s*)ns8_theme=(light|dark|system)/);
      return m ? m[1] : (MODES.indexOf(NS.default) >= 0 ? NS.default : "system");
    }

    function writeMode(mode) {
      document.cookie =
        COOKIE + "=" + mode + "; path=/cluster-admin; max-age=31536000; samesite=strict" +
        (location.protocol === "https:" ? "; secure" : "");
    }

    // Shell stylesheet: present for dark/system, with a media query for system.
    function applyShell(mode) {
      var link = document.getElementById("ns8-theme-css");
      if (mode === "light") {
        if (link) link.parentNode.removeChild(link);
      } else {
        if (!link) {
          link = document.createElement("link");
          link.id = "ns8-theme-css";
          link.rel = "stylesheet";
          link.href = NS.css;
          document.head.appendChild(link);
        }
        if (mode === "system") link.media = "(prefers-color-scheme: dark)";
        else link.removeAttribute("media");
      }
      root.setAttribute("data-ns8-theme", mode);
      var meta = document.querySelector('meta[name="color-scheme"]');
      if (!meta) {
        meta = document.createElement("meta");
        meta.name = "color-scheme";
        document.head.appendChild(meta);
      }
      meta.content = mode === "light" ? "light" : mode === "dark" ? "dark" : "light dark";
    }

    // App iframes get their theme from core.css, chosen by nginx from the
    // cookie, so a reload is all they need.
    function reloadApps() {
      var frames = document.querySelectorAll("iframe");
      for (var i = 0; i < frames.length; i++) {
        try { frames[i].contentWindow.location.reload(); } catch (e) {}
      }
    }

    var LABEL = { light: "Light theme", dark: "Dark theme", system: "Theme follows system" };
    var ICON = {
      light: '<path d="M16 12.005a4 4 0 1 1-4 4 4.005 4.005 0 0 1 4-4m0-2a6 6 0 1 0 6 6 6 6 0 0 0-6-6zM5.394 6.813l1.414-1.415 3.506 3.506L8.9 10.318zM2 15.005h5v2H2zM5.394 25.197l3.505-3.506 1.414 1.414-3.506 3.506zM15 25.005h2v5h-2zM21.687 23.106l1.414-1.415 3.506 3.506-1.414 1.415zM25 15.005h5v2h-5zM21.687 8.904l3.506-3.506 1.414 1.415-3.506 3.505zM15 2.005h2v5h-2z"/>',
      dark: '<path d="M13.502 5.414a15.075 15.075 0 0 0 11.594 18.194 11.113 11.113 0 0 1-7.975 3.39c-.138 0-.278.005-.418 0a11.094 11.094 0 0 1-3.2-21.584M14.98 3a1.002 1.002 0 0 0-.175.016 13.096 13.096 0 0 0 1.825 25.981c.164.006.328 0 .49 0a13.072 13.072 0 0 0 10.703-5.555 1.01 1.01 0 0 0-.783-1.565A13.08 13.08 0 0 1 15.89 4.38 1.015 1.015 0 0 0 14.98 3z"/>',
      system: '<path d="M16 4a12 12 0 1 0 12 12A12.014 12.014 0 0 0 16 4zm0 22V6a10 10 0 0 1 0 20z"/>'
    };

    var mode = readMode();
    applyShell(mode);

    function makeButton() {
      var b = document.createElement("button");
      b.id = "ns8-theme-toggle";
      b.type = "button";
      b.className = "bx--header__action";
      b.style.cssText = "display:inline-flex;align-items:center;justify-content:center";
      function paint() {
        var next = MODES[(MODES.indexOf(mode) + 1) % MODES.length];
        b.setAttribute("aria-label", LABEL[mode] + ". Switch to " + LABEL[next].toLowerCase());
        b.title = LABEL[mode];
        b.innerHTML =
          '<svg focusable="false" fill="currentColor" width="20" height="20" viewBox="0 0 32 32" aria-hidden="true">' +
          ICON[mode] + "</svg>";
      }
      b.addEventListener("click", function () {
        mode = MODES[(MODES.indexOf(mode) + 1) % MODES.length];
        writeMode(mode);
        applyShell(mode);
        paint();
        reloadApps();
      });
      paint();
      return b;
    }

    // The header is rendered by Vue after this script runs, and may be
    // re-rendered: keep the button attached to the global actions area.
    function attach() {
      if (NS.toggle === false) return;
      var bar = document.querySelector(".bx--header__global");
      if (!bar || document.getElementById("ns8-theme-toggle")) return;
      bar.insertBefore(makeButton(), bar.firstChild);
    }
    var obs = new MutationObserver(attach);
    function start() {
      attach();
      obs.observe(document.body, { childList: true, subtree: true });
    }
    if (document.body) start();
    else document.addEventListener("DOMContentLoaded", start);
  } catch (e) {
    if (window.console) console.warn("ns8-theme loader:", e);
  }
})();

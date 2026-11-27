# ns8-theme — dark mode for NS8 cluster-admin as a standalone module

Status: design draft, 2026-11-27; owner decisions recorded in §10. Nothing built or tested on a node yet.
Source basis: ns8-core `main` as of 2026-11-23, ns8-ui-lib 2.2.2, ns8-traefik,
ns8-kickstart, @carbon/themes 10.55.6, carbon-components 10.59.2 (what core's
`yarn.lock` resolves).

## 1. Goals and non-goals

Goals

- A polished dark theme for the cluster-admin shell **and** every app UI shown
  in its iframes, with no change to ns8-core, ns8-traefik or any app module.
- Three modes per browser: **Light**, **Dark**, **System** (follows
  `prefers-color-scheme`). A cluster-wide default set by the admin.
- No flash of the light theme on load, in the shell or in app iframes.
- Fails safe: if the module is stopped, broken or removed, cluster-admin looks
  and works exactly as stock.
- Structured so the palette is data (a token file), leaving the door open to the
  general theme switcher later.

Non-goals (v1)

- Arbitrary user themes, a theme editor, per-user server-side preferences.
- Theming anything outside `/cluster-admin` (app web UIs such as Nextcloud,
  Roundcube, Matomo).
- Restyling layout, spacing or typography.

## 2. How the stock UI is put together (the facts the design rests on)

| Fact | Where | Consequence |
|---|---|---|
| Carbon v10 is compiled with static SCSS colors (white theme + NethServer brand overrides). No CSS custom properties. | `core/ui/src/styles/_carbon.scss`, `_branding.scss` | Dark mode is an override stylesheet, not a variable swap. |
| Carbon v10 is end-of-life and frozen. | npm: last 10.x releases | Generated Carbon overrides stay valid across core releases. |
| `index.html` loads `config/config.production.js` — unhashed, synchronous, before the app bundle. | `core/ui/public/index.html` | A script appended to it runs before Vue mounts: no flash, full control of `<head>`. |
| Every app iframe links `/cluster-admin/css/core.css` by absolute path. App iframes run no core script. | `ns8-kickstart/ui/public/index.html`, `core/build-image.sh` | CSS appended to `core.css` themes every app with no JS. |
| Modules bundle ns8-ui-lib (at their own pinned version) and Carbon *helpers only* (vars, type, breakpoints), not Carbon component CSS. ns8-ui-lib injects its component styles at runtime from JS. | `ns8-ui-lib/build/rollup.config.js` (`css: true`), `ns8-kickstart/ui/src/styles` | ns8-ui-lib overrides must be selector-based and version-tolerant (no `data-v-*` hashes). |
| App modules' own styles carry very few colors (mail ≈8, samba ≈4, nextcloud/webtop/kickstart 0). | survey of 4 modules | Per-app patches are small and optional. |
| Core and ns8-ui-lib together hard-code ≈45 colors; the shell header, app drawer, notification drawer, toasts and log viewer are already dark. | grep inventory, §6 | The hand-written layer is small and enumerable. |
| api-server serves the UI from `/var/lib/nethserver/cluster/ui` on `127.0.0.1:9311`; Traefik routes `/cluster-admin` there at priority **100000**, stripping the prefix. | `ns8-traefik/.../create-module/60cluster_admin` | A route at higher priority for an exact path wins. |
| `traefik@node:routeadm` → `set-route` accepts `instance` (any name), `url`, `path`, `priority` (no upper bound), no `host` = all hosts; it builds `Path(p) \|\| PathPrefix(p/)`. | `ns8-traefik/.../set-route/20writeconfig` | The module can shadow exactly two files and nothing else. |
| Routing is hash-mode; `index.html` loads once per session. | `core/ui/src/router/index.js` | One injection per page load is enough. |

## 3. Architecture

```
browser ── /cluster-admin/config/config.production.js ──┐
        ── /cluster-admin/css/core.css ─────────────────┤ Traefik, priority 100100
        ── everything else under /cluster-admin ────────┼──────────────► api-server :9311 (stock)
                                                        ▼
                                         ns8-theme nginx (127.0.0.1:$TCP_PORT)
                                           │  proxy_pass original from :9311
                                           │  append loader JS / dark CSS
                                           └─ serves /theme/*.css from the image
```

### 3.1 Module shape

- Rootless NS8 module, one container: nginx (unprivileged image), host network,
  listening on `127.0.0.1:${TCP_PORT}` (`org.nethserver.tcp-ports-demand=1`).
- Labels: `org.nethserver.authorizations=traefik@node:routeadm`,
  `org.nethserver.max-per-node=1`, flags `no_data_backup` (config is tiny and in
  Redis; see §9).
- Two Traefik routes, both priority **100100**, no host:
  - `${MODULE_ID}-cfg` → path `/cluster-admin/config/config.production.js`
  - `${MODULE_ID}-css` → path `/cluster-admin/css/core.css`
  The module's nginx receives the full path (no `strip_prefix`).
- The shell's dark stylesheet is not served by nginx (only the two exact paths
  are routed to it). It ships in the module's own UI directory, which core
  extracts from the image and serves as a normal app UI:
  `/cluster-admin/apps/${MODULE_ID}/theme/dark.css`. No third route needed.

### 3.2 Theme selection: a cookie, decided server-side

Cookie `ns8_theme=light|dark|system`, `Path=/cluster-admin`, `SameSite=Strict`,
1 year. Missing cookie → cluster default (Redis, rendered into nginx env).

Why a cookie and not `localStorage`: app iframes run no core JS, so they cannot
read `localStorage` before first paint. nginx can read the cookie and pick the
right `core.css` variant, so iframes are correct from the first byte with zero
JavaScript and zero changes to app modules.

nginx (sketch):

```nginx
# Tested on a test node 2026-11-27 (nginx 1.27, core 3.25.1).
map $cookie_ns8_theme $ns8_theme { default $ns8_default; light light; dark dark; system system; }

server {
    listen 127.0.0.1:${TCP_PORT};
    proxy_http_version 1.1;
    proxy_set_header Accept-Encoding "";   # appended body must be plain text
    proxy_set_header If-Modified-Since ""; # never let api-server answer 304:
    proxy_set_header If-None-Match "";     # the variant depends on the cookie
    proxy_hide_header Last-Modified;
    proxy_hide_header ETag;
    addition_types text/css text/javascript application/javascript; # default is text/html only
    gzip on;                               # stock core.css is served gzipped; keep it so
    gzip_comp_level 6;                     # level 1 (default) gave 85 KB vs stock 61 KB
    gzip_types text/css text/javascript application/javascript;
    gzip_vary on;

    location = /cluster-admin/css/core.css {
        proxy_pass http://127.0.0.1:9311/css/core.css;
        add_after_body /_variant/core.css;   # add_after_body takes no variables...
        add_header Cache-Control "no-cache" always;
        add_header Vary "Cookie" always;
    }
    location = /cluster-admin/config/config.production.js {
        proxy_pass http://127.0.0.1:9311/config/config.production.js;
        add_after_body /_variant/loader.js;
        add_header Cache-Control "no-cache" always;
    }
    # ...so the subrequest picks the variant file itself.
    location = /_variant/core.css  { internal; root /srv; try_files /_variant/core-$ns8_theme.css =404; }
    location = /_variant/loader.js { internal; root /srv; }
}
```

`core-light.css` is empty. `core-dark.css` = the override layers (§5) under `:root`-prefixed selectors.
`core-system.css` = the same rules wrapped in
`@media (prefers-color-scheme: dark) { … }`. Both are built at image build time.

### 3.3 Shell loader (appended to `config.production.js`)

Runs synchronously before the Vue bundle. About 60 lines, no dependencies:

1. Read the cookie (fallback `window.NS8_THEME_DEFAULT`, which nginx also
   appends).
2. Insert `<link rel="stylesheet" href="/cluster-admin/apps/<id>/theme/dark.css">`
   into `<head>` — with `media="(prefers-color-scheme: dark)"` in System mode,
   omitted in Light mode. Set `<meta name="color-scheme">` and
   `document.documentElement.dataset.ns8Theme` (lets per-app patches and the
   toggle style themselves).
3. Add the toggle (§7) once the header exists (MutationObserver on `#core`,
   re-inserting if Vue re-renders the header).
4. On toggle: write the cookie, swap the `<link>` media/presence in the shell
   immediately, and reload the current app iframe (`iframe.contentWindow.location.reload()`)
   so its `core.css` variant is re-fetched. No full-page reload.
5. Tag each app iframe's `<html>` with `data-ns8-app="<module name>"` on load
   (same origin) so per-app patch rules can target it.

The loader must never throw into core: whole body in `try { … } catch {}`, and
`window.CONFIG` is defined by the original file before our code runs.

### 3.4 Fail-safe

The real risk of this design is that while the routes exist and nginx is down,
Traefik returns 502 for `config.production.js` and the **whole cluster-admin UI
fails to load** (no `window.CONFIG`).

Mitigations, in order:

1. The systemd unit adds the routes in `ExecStartPost` and removes them in
   `ExecStopPost` (via `agent` → `traefik` `set-route` / `delete-route`). Routes
   exist only while nginx is running. `Restart=always` with a short delay.
2. nginx proxies with a tight `proxy_connect_timeout`; if api-server itself is
   down the stock UI is down too, so no extra harm.
3. `destroy-module` deletes both routes before anything else.
4. Documented break-glass, runnable from any node shell:
   `api-cli run module/traefik1/delete-route --data '{"instance":"theme1-cfg"}'`
   (and `-css`).

## 4. The dark palette

Base: Carbon v10 **g100** surfaces (the shell header and drawers are already
g100-styled, so the page joins them seamlessly), with the NethServer brand blue
re-tuned for dark backgrounds. All ratios are WCAG 2.x contrast, computed.

### 4.1 Surfaces and text

| Token | Value | Notes |
|---|---|---|
| `ui-background` | `#161616` | page |
| `ui-01` (layer 1: tiles, cards, tables) | `#262626` | 1.20 vs page — rely on borders, see below |
| `ui-02` / `ui-03` (layer 2, subtle borders) | `#393939` | |
| `ui-04` (strong border) | `#6f6f6f` | 3.0:1 vs layer 1 (non-text minimum) |
| `ui-05` | `#f4f4f4` | |
| `field-01` | `#262626` · `field-02` `#393939` | |
| `text-01` | `#f4f4f4` | 16.5:1 page, 13.8:1 layer |
| `text-02` | `#c6c6c6` | 8.9:1 layer |
| `text-03` (placeholder) | `#8d8d8d` | 4.6:1 field |
| `text-05` (helper) | `#a8a8a8` | 6.4:1 layer |
| `icon-01` / `icon-02` | `#f4f4f4` / `#c6c6c6` | |
| `hover-ui` / `active-ui` / `selected-ui` | `#353535` / `#525252` / `#393939` | Carbon g100 |
| `disabled-01/02/03` | `#262626` / `#525252` / `#8d8d8d` | |
| `overlay-01` | `rgba(0,0,0,.65)` | |
| `skeleton-01/02` | `#353535` / `#525252` | |

Tiles on the page get a `1px solid #393939` border; on g100 the 1.2:1 layer
step alone reads as flat, and NS8 is tile-heavy (dashboard, software center).

### 4.2 Brand and interactive

| Token | Light (stock) | Dark | Contrast |
|---|---|---|---|
| `interactive-01` primary button | `#00a2de` | `#0073a1` | white text 5.3:1 (stock light is 2.9:1) |
| `hover-primary` | `#0094ca` | `#00668f` | 6.4:1 |
| `active-primary` | `#0085b7` | `#005a7e` | 7.6:1 |
| `interactive-04` / `focus` / `link-01` | `#00a2de` | `#55d1ff` (focus, links), `#33b5e5` (selected/check/toggle fill) | 10.3:1 page, 8.6:1 layer |
| `link-02`, `hover-primary-text` | `#0090de` | `#7cdcff` | 7.5:1 on layer 2 |
| `interactive-02` secondary button | — | `#6f6f6f`, hover `#606060` | Carbon g100 |
| `interactive-03` tertiary / ghost | `#00a2de` | border+text `#55d1ff`, hover fill `#55d1ff` + text `#161616` | |
| `highlight` (selected row, search hit) | `#caf1ff` | `#003a52` | text 11:1 |
| `visited-link` | — | `#be95ff` | |

Focus ring: `#55d1ff`, not Carbon's white — keeps the brand visible and is
distinguishable from white text.

### 4.3 Status colors

| Role | Dark value | On layer 1 | Replaces |
|---|---|---|---|
| error text/icon (`support-01`, `text-error`) | `#ff8389` | 6.4:1 | `#da1e28` (3.0:1 — fails) |
| danger button (`danger-01`) | `#da1e28`, hover `#b81921` | white 5.0:1 | unchanged |
| success (`support-02`) | `#42be65` | 6.3:1 | |
| warning text (`.ns-warning`, `$ns-warning-color`) | `#ff832b` | 6.2:1 | unchanged |
| warning status/icons (`$ns-warning-status-color`) | `#eb991e` | 6.6:1 | unchanged |
| caution/yellow (`support-03`) | `#f1c21b` | 9.0:1 | unchanged |
| info (`support-04`) | `#55d1ff` | 8.6:1 | `#0090de` |
| muted/disabled-ish text (`.ns-gray`-style `#767676`) | `#8d8d8d` | 4.6:1 | `#767676` (3.3:1) |

Inline notifications use Carbon g100's low-contrast style (`#262626` body, 3px
left bar in the status color, status-colored icon) rather than the light
theme's tinted backgrounds, which turn muddy on dark.

### 4.4 Elevation

Dark UIs lose shadow-based depth. Modals, menus, combo box lists and overflow
menus use layer 2 (`#393939`) plus `box-shadow: 0 2px 8px rgba(0,0,0,.6)`.
Modal backdrop stays `rgba(0,0,0,.65)`.

### 4.5 The palette is data

All of §4 lives in one `theme/dark.tokens.json` (Carbon token names + the
`ns-*` extras). Both the generated layer and the hand-written SCSS read it, so
re-tuning a color is a one-line change and a second theme is a second file.

## 5. Override layers

Everything below is prefixed with `:root` (raises specificity by one class so
it beats Carbon's flat selectors and Vue's `.x[data-v-…]` scoped selectors
without needing order guarantees), and with `!important` only where the stock
rule has it.

| Layer | Content | Built how | Size est. |
|---|---|---|---|
| L1 Carbon | Every Carbon v10 component rule whose color differs between white+brand and dark-tokens. | **Differential compile** at image build: compile `carbon-components@10.59.2` SCSS twice (stock tokens; dark tokens), parse both with PostCSS, keep only declarations whose values differ, emit with `:root` prefix. | ~60–120 KB unminified |
| L2 Core shell | `_core.scss` token uses (≈35) + the ≈25 hard-coded colors in core `.vue` files (§6). Selectors by class, no `data-v`. | Hand-written SCSS, same differential trick applied to `_core.scss` / `_utils.scss` for the token-based part. | small |
| L3 ns8-ui-lib | ≈30 token uses + ≈28 hard-coded colors in `Ns*` components. Class-based selectors that hold across ui-lib 1.x/2.x. | Hand-written. | small |
| L4 Per-app patches | Keyed by `html[data-ns8-app="mail"]` etc. Start empty; add as found. | Hand-written. | tiny |
| L5 Media | Lottie, logos, images (§6.3). | Hand-written. | tiny |

Shell gets L1–L5 via `dark.css`; iframes get the same file content appended
to `core.css`. One build artifact, two delivery paths.

## 6. Known hard-coded colors to cover

### 6.1 Core (`core/ui/src`)

- `_core.scss`: `#eb991e`, `#ff832b`, `#767676` status/muted helpers.
- `EditAcmeServerModal`, `ImportUsersModal`, `ImportBackupDestinationModal`:
  `#da1e28` error text/borders → `#ff8389`.
- `EditRepositoryModal`, `AddRepositoryModal`: `background-color: #ffffff`
  (provider logo tiles) → keep a light plate deliberately (§6.3).
- `TaskTreeHierarchy`: `#000` tree lines → `#6f6f6f`.
- `SettingsSubscription`: `#525252` text → `#c6c6c6`.
- `GlobalSearch`, `AppDrawer`, `NotificationDrawer`, `LogOutput`: already dark;
  verify only.

### 6.2 ns8-ui-lib (`src/lib-components`)

- `NsPasswordInput`: strength meter `#f4f4f4` / `#ffffff` / `#c6c6c6` track →
  `#393939` / `#525252`; fill `#198038` → `#42be65`.
- `NsTextInput` `#525252`, `NsTimePicker` `#797979` labels → `#c6c6c6`.
- `NsProgress` `#e0e0e0` track → `#393939`; `#00a2de` → `#33b5e5`.
- `NsByteSlider`, `NsSlider` `#da1e28` → `#ff8389`.
- `NsComboBox`, `NsComboSearchBox` `#f1c21b` / `#a8a8a8`: OK on dark, verify.
- `NsTile` `#c6c6c6`, `NsToastNotification` (already dark): verify.
- `NsCircleTimer` default color prop `#00a2de` (inline SVG attribute — CSS
  `stroke` override with `!important`).
- `_tokens.scss` / `_branding.scss`: compiled into each module at its pinned
  version — covered by L3 selectors, not by recompiling.

### 6.3 Images and animation

- Lottie: `GhostLottie` (8 uses), `GearsLottie` (10), `RocketLottie` (3) are
  drawn for light backgrounds; `GhostDarkBgLottie` exists and is already used
  in dark spots. CSS cannot swap the JSON, so: target the Lottie `<svg>` paths
  by fill color (`path[fill="rgb(…)"]`) and recolor to the dark palette. Fallback:
  `filter: invert(.88) hue-rotate(180deg)` on the container.
- App logos (PNG, arbitrary, mostly drawn for white): show on a light rounded
  plate (`#f4f4f4`, 4px padding, 4px radius) in the software center and app
  pages. Inverting third-party logos is worse than a plate. Same for backup
  provider logos (already on `#ffffff` tiles — leave).
- Login page logo and loading screen: the loading screen is already `#393939`.

## 7. User interface

- **Toggle (decided):** an icon button in the Carbon header's global actions, left of the
  notifications icon — `Light / Dark / System` cycling, with `aria-label` and a
  tooltip. Inserted by the loader; re-attached by a MutationObserver if Vue
  re-renders the header. If that proves fragile, drop it and keep only the
  module's app page.
- **Module app page** (`/apps/theme1`): cluster default mode, a live preview of
  common components in both themes, and a "report a broken screen" hint that
  says how to capture the selector.
- **Login page:** honors the cookie/default; no toggle there.

## 8. Actions and lifecycle

| Action / event | Does |
|---|---|
| `create-module` | Check this node is the leader (warn, don't fail, if not). Write default `system` to Redis (decided default). |
| `configure-module` | `{"default_theme": "light|dark|system"}` → Redis, render nginx env, restart. |
| `get-configuration` | Return it, plus "is leader" and "routes active". |
| systemd `ExecStartPost` / `ExecStopPost` | Add / remove the two routes (§3.4). |
| `destroy-module` | Remove routes, then the container. |
| event `leader-changed` | If this node lost leadership: remove routes, log a warning that the module should be reinstalled on the new leader. |

## 9. Testing

- Robot suite (module template style): install → routes present at priority
  100100 → `config.production.js` contains the loader and still defines
  `window.CONFIG` → `core.css` has the dark tail with cookie `dark`, none with
  `light` → stop service → routes gone and stock files served → remove module →
  routes gone.
- Visual regression: Playwright against a test cluster, screenshots of a fixed
  page list (dashboard, software center, nodes, settings tabs, backup modals,
  domains/users, one app each of mail/samba/nextcloud/webtop) in light/dark;
  automated contrast check (axe-core) on the dark set.
- Upgrade check per core release: diff core's `core.css` and the hard-coded
  color inventory (§6) against the previous release; the inventory script lives
  in the repo.

## 10. Open questions

**Decided (2026-11-27)**

- **Name:** `ns8-theme`.
- **Default mode** for users with no cookie: **System**.
- **Toggle:** header button. If keeping it attached to the Carbon header proves
  fragile, fall back to the module's own app page only.
- **Palette:** §4 accepted as proposed, including the deep primary blue
  `#0073a1` with white text (checked in a mock-up preview page).
- **App logos:** keep the light backing in dark mode. It doesn't look great,
  but it's better than putting a dark background behind logos that weren't
  designed for one. Room to refine the plate (softer gray, smaller padding).
- **Distribution:** public. That means a public GitHub repository, the image
  on ghcr.io, GPL-3.0 like the rest of NS8, the Robot and visual tests in §9
  from the first release, and nothing specific to one cluster in the repo.

**Still open**

1. **Accent override:** expose a single "accent color" setting in v1, or keep
   it fixed until the general theme switcher?

**Things to verify on a real node before building**

2. ~~**Does `set-route` accept a priority above 100000 and does Traefik honor it
   over the core `cluster-admin-https` router?**~~ **Answered yes, 2026-11-27**,
   on a test node (core 3.25.1). `set-route` accepted
   `priority: 100100` and a path with no host. Both routes overrode the stock
   files on every hostname tried (127.0.0.1, the LAN IP, the node FQDN). HTTP
   redirected to HTTPS. Neighbouring paths (`/cluster-admin/`, the hashed
   `app~*.css`, `config/`, `api/`) still reached api-server. Removing the
   routes with `delete-route` restored the stock files byte for byte and left no
   config file or Redis key behind.
3. **Does a path-only route (no host) collide** with any existing catch-all or
   host-based route at high priority (e.g. apps configured with a default
   virtual host)? Partly answered: on the test node the
   host-less routes beat every hostname tried, and host-based app routes
   (Nextcloud, SOGo, WebTop) use default priorities 2–3, far below. Still
   worth checking a cluster with a custom catch-all route.
4. ~~**`add_after_body` + `proxy_pass`** with api-server's static handler~~
   **Answered yes, 2026-11-27**, on a test node with
   `nginx:1.27-alpine` behind the priority-100100 routes. The cookie picked the
   variant (`light` = byte-identical stock file, `dark`, `system`; no cookie or
   an unknown value fell back to the default). The config script kept working
   with the loader appended, and conditional requests with old validators got a
   full 200. Four things the first sketch got wrong, now fixed in §3.2:
   `add_after_body` takes no variables (pick the file in an internal location
   with `try_files`); `addition_types` must list CSS and JS; validators must be
   stripped both ways, or api-server can answer 304 for the wrong variant;
   and **stock `core.css` is served gzipped while the override wasn't**
   (620 KB uncompressed), so nginx needs `gzip on`.
   **Follow-up test, same day:** with `gzip on`, `core.css` went out gzipped
   (85 KB on the wire at the default level 1, against 61 KB stock; the sketch
   now sets level 6) and decompressed to the exact stock bytes plus the variant.
   `Vary` carries both `Accept-Encoding` and `Cookie`. **Browser load in Chrome
   passed:** with the routes in place and the OS in dark mode (System variant),
   the shell started normally (`window.CONFIG` set, Vue mounted, no console
   errors on a fresh reload), the loader ran (`data-ns8-theme="system"`, its
   stylesheet inserted), and the Nextcloud app iframe loaded the overridden
   `core.css` (4,093 rules, variant rule present) and rendered. One expected
   lesson: app pages paint their own content backgrounds (`bx--content`, tiles),
   so body-level rules alone leave most of the page light. That is what L1/L2
   are for. Not tried in the browser: switching the cookie, because the Chrome
   extension can't read or set cookies; curl covered the cookie variants.
5. **Browser caching of stock `core.css`:** gin sends `Last-Modified`; browsers
    that cached it before install may keep serving it heuristically until
    revalidation. Confirm one hard reload is enough, and whether the 502 risk
    in §3.4 has a caching angle (a cached good file masks a dead route).
6. **Leader-only?** api-server runs on every node; is cluster-admin ever used
    via a worker node's address? If yes, install per node.
7. **Module removal event ordering:** does the core `remove-module` path run
    our `destroy-module` early enough that routes never point at a dead
    service?
8. ~~**Calling Traefik from systemd hooks.**~~ **Answered yes, 2026-11-27**,
   with the first module image on the test node (core 3.25.1).
   `runagent manage-routes up|down` from `ExecStartPost`/`ExecStop`/`ExecStopPost`
   adds and removes the routes; one call logged a WebSocket retry and then
   succeeded. Measured: install starts the theme with no further step; a
   clean stop removes the routes before nginx stops; killing nginx leaves
   stock cluster-admin for about 10 s until systemd restarts it and the
   routes return; `configure-module` takes about 10 s, mostly Traefik task
   round trips. Route tasks are marked `isNotificationHidden` so they stay
   out of the notification drawer, and a runtime marker stops the
   `ExecStopPost` cleanup from repeating the `ExecStop` one.
9. **ns8-ui-lib major versions in the wild:** the selector-based L3 layer
    assumes class names are stable across ui-lib 1.x and 2.x. Check which
    majors installed apps actually ship.

**Things that need building to answer**

10. **Size and accuracy of the differential Carbon compile (L1).** Estimate is
    60–120 KB; if much bigger, consider shipping only the components NS8 uses.
11. **Lottie recoloring by fill selector** — works if the animations use a
    small fixed set of fills; needs a look at the JSON.
12. **Screens nobody inventoried:** third-party apps' own pages, the API docs
    link, the backup download page, error pages. Find them with the visual
    regression pass.

**Longer-term risks**

13. Core can rename or hash `config.production.js`, change its load order, or
    change the cluster-admin route priority in any release. Each breaks the
    theme (not the UI, given §3.4). Track with the Robot suite on core updates.
14. If upstream ever adopts CSS custom properties (the clean core approach),
    this module becomes a token file plus a toggle — L1–L3 can be deleted.

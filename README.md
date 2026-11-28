# ns8-theme

Dark mode for the NethServer 8 cluster-admin web interface, as a standalone
module. Nothing in ns8-core or in any app module is patched.

- **Light, Dark, or follow the system setting**, chosen per browser with a
  button in the cluster-admin header.
- **Covers app pages too.** The settings pages of every installed app (Mail,
  Nextcloud, SOGo, …) are themed with no change to those apps.
- **No flash of white.** The choice is a cookie that the server reads, so pages
  arrive already themed.
- **Fails safe.** If the module is stopped, broken or removed, cluster-admin is
  exactly stock.

## How it works

cluster-admin loads two files that this module can take over without touching
core: `config/config.production.js` (a small script loaded before the UI) and
`css/core.css` (the stylesheet every app page links). The module runs nginx and
adds two Traefik routes, at a priority just above core's, that send those two
paths to it. nginx fetches the stock file from core's API server and appends:

- to `config.production.js`, a loader that adds the dark stylesheet to the
  shell and puts the theme button in the header;
- to `core.css`, the dark rules (or a `prefers-color-scheme` version of them,
  or nothing), picked from the `ns8_theme` cookie.

The routes exist only while nginx is running: the service adds them once nginx
answers and removes them when it stops.

The dark stylesheet is generated at build time from NS8's own sources: the core
UI and ns8-ui-lib SCSS are compiled twice, once with the stock colors and once
with the dark palette, and only the declarations that differ are kept. A short
hand-written layer covers colors that NS8 hard-codes. See
[DESIGN.md](DESIGN.md) for the full design, the palette and its contrast
checks, and the open questions.

## Install

Install it on the **leader node**, the node whose address you use for
cluster-admin.

From the Software Center: add the danb35 software repository once (in
cluster-admin, **Settings → Software repositories → Add repository**, URL
`https://danb35.github.io/ns8-repomd/`), then install **theme**. Or from a
shell on the leader node, replacing `1` with the leader's node ID:

    api-cli run add-repository --data '{"name":"danb35","url":"https://danb35.github.io/ns8-repomd/","status":true}'
    add-module theme 1

`add-module theme` installs the newest release from the repository; without the
repository, use the image directly: `add-module ghcr.io/danb35/theme:latest 1`.

The theme is active immediately, following each browser's system setting.
Reload cluster-admin to see it.

## Configure

From the app's **Settings** page in cluster-admin, or:

    api-cli run module/theme1/configure-module --data '{"default_theme": "system", "show_toggle": true}'

| Field | Values | Meaning |
|---|---|---|
| `default_theme` | `system`, `light`, `dark` | Theme for browsers where nobody has used the header button |
| `show_toggle` | `true`, `false` | Show the Light / Dark / System button in the header |

A choice made with the header button is stored in that browser (the
`ns8_theme` cookie) and wins over the default.

## Uninstall

    remove-module --no-preserve theme1

Removing the module also removes its routes, so cluster-admin goes back to
stock.

## Troubleshooting

**Not dark right after installing (or app pages stay light).** Browsers cache
cluster-admin's stock files for a while. The theme replaces a cached stock
`core.css` by itself the first time the shell loads, but a cached stock
`config.production.js` it cannot reach: do one hard reload (Shift-Reload, or
Cmd/Ctrl-Shift-R) of cluster-admin. Other browsers and computers are not
affected.

**cluster-admin won't load after installing.** Remove the two routes by hand
from any node shell, then investigate (replace `traefik1` with the node's
Traefik instance):

    api-cli run module/traefik1/delete-route --data '{"instance": "theme1-cfg"}'
    api-cli run module/traefik1/delete-route --data '{"instance": "theme1-css"}'

**A screen looks wrong in dark mode.** Please open an issue with a screenshot,
the page's address and, if you can, the element's class names from the
browser's developer tools.

Service logs:

    journalctl _UID=$(id -u theme1)

## Development

- `theme/` generates the stylesheets: `npm ci && npm run build` writes
  `theme/dist/`. `theme/tokens/dark.json` is the palette; hand-written rules are
  in `theme/overrides/`; the header loader is `theme/loader/loader.js`.
- `imageroot/` is the module backend: `bin/expand-config` renders the nginx
  config, `bin/manage-routes` adds and removes the Traefik routes.
- `ui/` is the module's settings page.
- `build-images.sh` builds everything into one image.
- `tests/` holds the Robot Framework integration tests.

Each GitHub push builds an image tagged with the branch name; see
`.github/workflows/publish-images.yml`.

## License

GPL-3.0-or-later, like NethServer 8. See [LICENSE](LICENSE).

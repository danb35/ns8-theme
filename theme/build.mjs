// SPDX-License-Identifier: GPL-3.0-or-later
//
// Generate the ns8-theme dark override stylesheets.
//
// Method (DESIGN.md section 5): compile NS8's own SCSS twice -- once exactly as
// NS8 does (light), once with the dark tokens -- and keep only the declarations
// whose values differ. Sources: the core UI (global styles and every .vue style
// block) and ns8-ui-lib (component style blocks). Hand-written rules for
// hard-coded colors, images and elevation are appended afterwards.
//
// Environment:
//   NS8_CORE_REF  ns8-core git tag to read the core UI sources from

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { Readable } from "node:stream";
import * as sass from "sass";
import postcss from "postcss";
import * as tar from "tar";
import * as carbonThemes from "@carbon/themes";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CACHE = path.join(HERE, ".cache");
const DIST = path.join(HERE, "dist");
const NODE_MODULES = path.join(HERE, "node_modules");
const CORE_REF = process.env.NS8_CORE_REF || "3.25.1";
const PREFIX = ":root:root"; // +2 classes: beats Carbon's flat selectors and Vue's .x[data-v-…]
// Parts of the shell that stock NS8 already draws dark (header, side menu,
// drawers, toasts, log viewer). Their light-theme rules use inverse tokens on
// purpose; regenerating them with dark tokens would turn them light.
// Prefix match on purpose: .bx--side-nav also covers .bx--side-nav__link etc.
const SKIP = /\.(?:bx--header|bx--side-nav|core-side-nav|app-side-nav|app-side-menu|app-drawer|notification-drawer|global-search|bx--toast-notification|ns-toast|log-output|logs-output)/;

const log = (...a) => console.error("[theme]", ...a);

// ---------------------------------------------------------------- sources

async function fetchCoreSources() {
  const dest = path.join(CACHE, `ns8-core-${CORE_REF}`);
  if (fs.existsSync(path.join(dest, "core/ui/src/App.vue"))) return dest;
  fs.mkdirSync(dest, { recursive: true });
  const url = `https://codeload.github.com/NethServer/ns8-core/tar.gz/refs/tags/${CORE_REF}`;
  log("downloading", url);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`download failed: ${res.status} ${url}`);
  await new Promise((resolve, reject) => {
    Readable.fromWeb(res.body)
      .pipe(tar.x({ cwd: dest, strip: 1, filter: (p) => /\/core\/ui\/src\//.test(p) }))
      .on("finish", resolve)
      .on("error", reject);
  });
  return dest;
}

// Copy a tree twice: "light" untouched, "dark" with every _branding.scss emptied
// (the light brand colors are set without !default and would override ours).
function makeVariants(srcDir, name) {
  const out = {};
  for (const mode of ["light", "dark"]) {
    const dir = path.join(CACHE, "variants", mode, name);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.cpSync(srcDir, dir, { recursive: true });
    if (mode === "dark") {
      for (const f of walk(dir)) {
        if (path.basename(f) === "_branding.scss") fs.writeFileSync(f, "// emptied by ns8-theme\n");
      }
    }
    out[mode] = dir;
  }
  return out;
}

function* walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) yield* walk(p);
    else yield p;
  }
}

// ---------------------------------------------------------------- dark tokens

function darkPrelude() {
  const spec = JSON.parse(fs.readFileSync(path.join(HERE, "tokens/dark.json"), "utf8"));
  const base = carbonThemes[spec.base];
  const vars = {};
  for (const [k, v] of Object.entries(base)) {
    if (typeof v !== "string" || !/^(#|rgb)/.test(v)) continue;
    vars[carbonThemes.formatTokenName(k)] = v;
  }
  Object.assign(vars, spec.tokens);
  const lines = Object.entries(vars).map(([k, v]) => `$${k}: ${v};`);
  // ns8-ui-lib's own variables (set with !default there)
  for (const [k, v] of Object.entries(spec.ns)) lines.push(`$${k}: ${v};`);
  return { scss: lines.join("\n") + "\n", spec };
}

// ---------------------------------------------------------------- compile

const tildeImporter = {
  findFileUrl(url) {
    if (!url.startsWith("~")) return null;
    return pathToFileURL(path.join(NODE_MODULES, url.slice(1)));
  },
};

function compile(source, file, prelude) {
  const res = sass.compileString(prelude + source, {
    url: pathToFileURL(file),
    loadPaths: [NODE_MODULES],
    importers: [tildeImporter],
    style: "expanded",
    quietDeps: true,
    logger: sass.Logger.silent,
  });
  return res.css;
}

// Vue scoped-style combinators sass can't use as selectors.
function cleanVueScss(src) {
  return src
    .replace(/::v-deep\s*/g, " ")
    .replace(/:deep\(([^)]*)\)/g, " $1")
    .replace(/>>>/g, " ")
    .replace(/\/deep\//g, " ");
}

function styleBlocks(vueFile) {
  const text = fs.readFileSync(vueFile, "utf8");
  const blocks = [];
  for (const m of text.matchAll(/<style([^>]*)>([\s\S]*?)<\/style>/g)) {
    if (!/lang=["']scss["']/.test(m[1])) continue; // plain CSS has no tokens
    blocks.push(cleanVueScss(m[2]));
  }
  return blocks;
}

// ---------------------------------------------------------------- diff

// Flatten a stylesheet to: key (at-rule chain + selector) -> Map(prop -> "value !important")
function index(css) {
  const rules = new Map();
  const keyframes = new Map();
  const root = postcss.parse(css);
  root.walkAtRules(/keyframes$/, (node) => {
    keyframes.set(`@${node.name} ${node.params}`, node.toString());
  });
  root.walkRules((node) => {
    if (SKIP.test(node.selector)) return;
    let chain = [];
    for (let p = node.parent; p && p.type !== "root"; p = p.parent) {
      if (p.type === "atrule") {
        if (/keyframes$/.test(p.name) || p.name === "font-face") return;
        chain.unshift(`@${p.name} ${p.params}`);
      }
    }
    const key = chain.join("\u0001") + "\u0002" + node.selector;
    let decls = rules.get(key);
    if (!decls) rules.set(key, (decls = new Map()));
    node.each((d) => {
      if (d.type === "decl") decls.set(d.prop, d.value + (d.important ? " !important" : ""));
    });
  });
  return { rules, keyframes };
}

// origin "global": Carbon and core's global styles. They load before ours,
// so an unprefixed copy wins by source order and stays no stronger than
// stock (a boosted `a {}` would override the side menu's own link colors).
// origin "component": .vue style blocks, which Vue scopes as .x[data-v-…]
// and which load after ours, so they get the :root:root boost.
function diff(lightCss, darkCss, out, origin) {
  const L = index(lightCss);
  const D = index(darkCss);
  for (const [key, decls] of D.rules) {
    const ld = L.rules.get(key) || new Map();
    for (const [prop, val] of decls) {
      if (ld.get(prop) === val) continue;
      const okey = origin + "\u0003" + key;
      if (!out.rules.has(okey)) out.rules.set(okey, new Map());
      out.rules.get(okey).set(prop, val);
    }
  }
  for (const [k, txt] of D.keyframes) if (L.keyframes.get(k) !== txt) out.keyframes.set(k, txt);
}

function prefixSelector(sel, origin) {
  if (origin === "global") return sel.split(/,(?![^(]*\))/).map((s) => s.trim()).join(",\n");
  return sel
    .split(/,(?![^(]*\))/)
    .map((s) => {
      s = s.trim();
      if (/^html\b/.test(s)) return PREFIX + s.slice(4);
      if (/^:root\b/.test(s)) return PREFIX + s.slice(5);
      return `${PREFIX} ${s}`;
    })
    .join(",\n");
}

function emit(out) {
  const root = postcss.root();
  const containers = new Map([["", root]]);
  for (const [okey, decls] of out.rules) {
    const [origin, key] = okey.split("\u0003");
    const [chainStr, selector] = key.split("\u0002");
    const chain = chainStr ? chainStr.split("\u0001") : [];
    let parent = root;
    let acc = "";
    for (const at of chain) {
      acc += "\u0001" + at;
      if (!containers.has(acc)) {
        const m = at.match(/^@(\S+)\s*(.*)$/);
        const node = postcss.atRule({ name: m[1], params: m[2] });
        parent.append(node);
        containers.set(acc, node);
      }
      parent = containers.get(acc);
    }
    const rule = postcss.rule({ selector: prefixSelector(selector, origin) });
    for (const [prop, val] of decls) {
      const important = / !important$/.test(val);
      rule.append(postcss.decl({ prop, value: val.replace(/ !important$/, ""), important }));
    }
    parent.append(rule);
  }
  let css = root.toString();
  for (const txt of out.keyframes.values()) css += "\n" + txt;
  return css;
}

// ---------------------------------------------------------------- main

async function main() {
  fs.mkdirSync(CACHE, { recursive: true });
  fs.rmSync(DIST, { recursive: true, force: true });
  fs.mkdirSync(DIST, { recursive: true });

  const { scss: prelude, spec } = darkPrelude();
  const core = await fetchCoreSources();
  const coreV = makeVariants(path.join(core, "core/ui/src"), "core");
  const libV = makeVariants(path.join(NODE_MODULES, "@nethserver/ns8-ui-lib/src"), "ui-lib");

  const out = { rules: new Map(), keyframes: new Map() };
  const stats = { core_ref: CORE_REF, blocks: 0, skipped: [] };

  for (const [name, v] of [["core", coreV], ["ui-lib", libV]]) {
    for (const lightFile of walk(v.light)) {
      if (!lightFile.endsWith(".vue")) continue;
      const rel = path.relative(v.light, lightFile);
      const darkFile = path.join(v.dark, rel);
      const lb = styleBlocks(lightFile);
      const db = styleBlocks(darkFile);
      for (let i = 0; i < lb.length; i++) {
        try {
          const lc = compile(lb[i], lightFile, "");
          const dc = compile(db[i], darkFile, prelude);
          const origin = name === "core" && rel === "App.vue" ? "global" : "component";
          diff(lc, dc, out, origin);
          stats.blocks++;
        } catch (e) {
          stats.skipped.push(`${name}/${rel}#${i}: ${String(e.message).split("\n")[0]}`);
        }
      }
    }
  }

  let generated = emit(out);
  stats.generated_rules = out.rules.size;

  // Hand-written layers (DESIGN.md section 5, L2b-L5)
  const tokenVars = prelude;
  const hand = compile(
    fs.readFileSync(path.join(HERE, "overrides/_index.scss"), "utf8"),
    path.join(HERE, "overrides/_index.scss"),
    tokenVars
  );

  const banner = `/* ns8-theme dark layer. Generated from ns8-core ${CORE_REF} and ns8-ui-lib; do not edit. */\n`;
  const dark = banner + generated + "\n/* hand-written overrides */\n" + hand;
  fs.writeFileSync(path.join(DIST, "dark.css"), dark);
  fs.writeFileSync(path.join(DIST, "core-dark.css"), "\n" + dark);
  fs.writeFileSync(
    path.join(DIST, "core-system.css"),
    "\n@media (prefers-color-scheme: dark) {\n" + dark + "\n}\n"
  );
  fs.writeFileSync(path.join(DIST, "core-light.css"), "");
  fs.copyFileSync(path.join(HERE, "loader/loader.js"), path.join(DIST, "loader.js"));

  stats.bytes = { dark: Buffer.byteLength(dark) };
  fs.writeFileSync(path.join(DIST, "stats.json"), JSON.stringify(stats, null, 2));
  log(`blocks compiled: ${stats.blocks}, skipped: ${stats.skipped.length}, rules: ${stats.generated_rules}, dark.css: ${stats.bytes.dark} bytes`);
  for (const s of stats.skipped) log("skipped", s);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

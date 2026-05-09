# bobo-koreader

KOReader plugin + Rust backend for reading manga. Shows up as **bobo** in KOReader.

## Architecture

- `frontend/bobo.koplugin/` — Lua plugin loaded by KOReader
- `backend/` — Rust HTTP server, communicates over Unix socket `/tmp/bobo.sock`
- `backend/shared/` — core logic and SQLite DB (`~/.bobo/database.db`)
- `backend/server/` — HTTP routes and request handling

## Dev

```bash
# Rust (requires DATABASE_URL for sqlx macros)
export DATABASE_URL=sqlite:///tmp/bobo-dev.db
cd backend/shared && cargo sqlx db create && cargo sqlx migrate run
cd backend && cargo test --all
cargo clippy --all-targets -- -D warnings

# Lua tests (requires LuaJIT)
busted --lua luajit -C frontend/bobo.koplugin .
```

## CI / Releases

- PRs and main: `.github/workflows/ci.yml` runs Rust clippy + tests and Lua unit tests
- Merging to main: `.github/workflows/build.yml` cross-compiles for all targets and publishes a GitHub Release via semantic-release

Use conventional commits (`feat:`, `fix:`) — semantic-release derives the version from them.

## Key conventions

- No upstream branding (tachibana-shin/rakuyomi was the fork source — all URLs point to `evanspn/bobo-koreader`)
- sqlx query macros require `DATABASE_URL` at compile time; CI sets it to a temp SQLite file
- Lua tests must run under LuaJIT (`goto` keyword used in `findNextChapter.lua`)
- **Every new Lua feature or bug fix must include tests** — add a `*_spec.lua` file alongside the module (e.g. `MangaReader_spec.lua` next to `MangaReader.lua`). Run `busted --lua luajit -C frontend/bobo.koplugin .` and confirm all tests pass before pushing.
- **Read [`docs/src/contributing/koreader-ui-guide.md`](docs/src/contributing/koreader-ui-guide.md) before touching any file under `frontend/bobo.koplugin/`** — it documents the KOReader widget patterns and busted-stubbing gotchas (lazy `dimen`, scrollbar widths, `_G.G_reader_settings`, colon-vs-dot stubs, Trapper coroutine errors) that this plugin has hit repeatedly.

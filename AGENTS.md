<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# Repository Guidelines

## Project Structure

- `tauri-app/`: main application workspace (run most commands here)
  - `tauri-app/src/`: Vue 3 + TypeScript UI (`main.ts`, `App.vue`, icons/assets)
  - `tauri-app/src-tauri/`: Tauri v2 Rust backend
    - `tauri-app/src-tauri/src/main.rs`: Rust entrypoint
    - `tauri-app/src-tauri/src/lib.rs`: Tauri commands + multi-webview logic
    - `tauri-app/src-tauri/tauri.conf.json`: app config (window, CSP, bundling)
    - `tauri-app/src-tauri/capabilities/`: permission capabilities
- Generated/large dirs (do not commit): `tauri-app/node_modules/`, `tauri-app/src-tauri/target/`, `tauri-app/dist/`

## Build, Test, and Development Commands

Run from `tauri-app/` unless noted:

- `pnpm install`: install frontend deps (lockfile: `tauri-app/pnpm-lock.yaml`)
- `pnpm tauri dev`: run Vite + Tauri dev app
- `pnpm dev`: frontend-only Vite server (port `1420`)
- `pnpm build`: typecheck (`vue-tsc`) + Vite production build
- `pnpm preview`: preview the production build

Rust-only (from `tauri-app/src-tauri/`):

- `cargo build`: compile backend
- `cargo fmt` / `cargo clippy`: formatting/lint (recommended)

## Coding Style & Naming

- TypeScript/Vue: 2-space indentation; prefer `camelCase` for variables and `PascalCase` for components.
- Rust: `rustfmt` default style; use `snake_case` for Tauri command names.
- Frontend ↔ backend IPC pattern:
  - Rust: add `#[tauri::command] fn my_command(...) { ... }` and register in `tauri::generate_handler![...]` in `tauri-app/src-tauri/src/lib.rs`.
  - Frontend: call `invoke("my_command", { ... })` from `@tauri-apps/api/core`.

## Testing Guidelines

No dedicated test suite is included yet. Before opening a PR, at minimum run:

- `pnpm build` (ensures TypeScript/Vue typecheck passes)
- `cargo test` (if Rust tests exist in your change)

## Commit & Pull Request Guidelines

Git history may not be available in all checkouts. Use clear, imperative commit messages (recommended: Conventional Commits, e.g., `feat: add site editor`).

PRs should include:

- What changed + why, and any UX screenshots for UI changes
- Notes on security-sensitive changes (CSP, capabilities, webview behavior)

## Security & Configuration Notes

This app embeds external sites in webviews and injects scripts. Be cautious when adjusting:

- `tauri-app/src-tauri/tauri.conf.json` (CSP)
- `tauri-app/src-tauri/capabilities/default.json` (permissions)

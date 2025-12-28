# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Tauri v2 desktop application with a Vue 3 + TypeScript frontend and Rust backend. The project follows the standard Tauri monorepo structure with frontend code in `tauri-app/` and Rust backend in `tauri-app/src-tauri/`.

## Development Commands

All commands should be run from the `tauri-app/` directory:

```bash
# Install dependencies (uses pnpm)
pnpm install

# Start development server (runs both frontend and Tauri)
pnpm tauri dev

# Build for production
pnpm tauri build

# Frontend-only development (Vite dev server)
pnpm dev

# Type check TypeScript without emitting files
pnpm exec vue-tsc --noEmit

# Preview production build
pnpm preview
```

## Architecture

### Frontend (tauri-app/src/)
- **Framework**: Vue 3 with `<script setup>` SFC syntax
- **Build Tool**: Vite (dev server runs on port 1420)
- **Language**: TypeScript with strict mode enabled
- **Entry Point**: `src/main.ts` initializes the Vue app
- **Main Component**: `src/App.vue` contains the root component

### Backend (tauri-app/src-tauri/)
- **Language**: Rust (edition 2021)
- **Entry Point**: `src/main.rs` (minimal, calls into `lib.rs`)
- **Core Logic**: `src/lib.rs` contains the `run()` function and Tauri commands
- **Library Name**: `tauri_app_lib` (uses `_lib` suffix to avoid naming conflicts on Windows)
- **Build Types**: staticlib, cdylib, and rlib

### Tauri Configuration
- **Config File**: `src-tauri/tauri.conf.json`
- **App Identifier**: `com.zhangshuo.tauri-app`
- **Window Size**: 800x600 default
- **Dev Server**: Frontend served at `http://localhost:1420`
- **Build Output**: Frontend builds to `../dist` (relative to src-tauri)

## Frontend-Backend Communication

Tauri uses a command-based IPC system:

1. **Rust Side**: Define commands with `#[tauri::command]` attribute in `src-tauri/src/lib.rs`
2. **Registration**: Add commands to `.invoke_handler(tauri::generate_handler![command_name])`
3. **Frontend Side**: Import and call with `invoke("command_name", { args })` from `@tauri-apps/api/core`

Example workflow:
- Rust: `#[tauri::command] fn greet(name: &str) -> String { ... }`
- Register: `tauri::generate_handler![greet]`
- Vue: `await invoke("greet", { name: "World" })`

## Key Dependencies

**Frontend:**
- `@tauri-apps/api`: Tauri's JavaScript/TypeScript API
- `@tauri-apps/plugin-opener`: Plugin for opening URLs/files

**Backend:**
- `tauri`: Core Tauri framework (v2)
- `tauri-plugin-opener`: Rust side of opener plugin
- `serde` + `serde_json`: Serialization for IPC

## TypeScript Configuration

The project uses strict TypeScript with:
- Target: ES2020
- Module Resolution: bundler mode (Vite)
- JSX: preserve (for Vue)
- Strict mode enabled with unused variable checks

## Mobile Support

The codebase includes mobile entry point support via `#[cfg_attr(mobile, tauri::mobile_entry_point)]` in `lib.rs`, though mobile-specific configuration would need to be added to tauri.conf.json to build for iOS/Android.

## Build Process

**Development:**
1. Vite starts frontend dev server on port 1420
2. Tauri watches Rust code and rebuilds on changes
3. HMR enabled for Vue components

**Production:**
1. `pnpm build` runs TypeScript type checking and Vite build
2. Vite outputs to `dist/` directory
3. Tauri bundles the application with the compiled frontend
4. Creates platform-specific installers (Windows, macOS, Linux)

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

**叩问 (KouWen)** — an AI Skills Platform for Mobile built with Flutter. It's an AI chat app that loads "skills" (markdown files with YAML frontmatter containing system prompts and metadata) to specialize conversations. Skills are sourced from built-in assets, GitHub/Gitee repositories, and a skill market catalog. Chat uses any OpenAI-compatible API with streaming responses.

## Commands

```bash
# Environment setup (needed in each new terminal)
export PATH="/usr/local/flutter/bin:$PATH"
export ANDROID_SDK_ROOT=/usr/local/android-sdk
export ANDROID_HOME=/usr/local/android-sdk
export DISPLAY=:14.0

# Static analysis
flutter analyze

# Run all tests (8 unit tests)
flutter test

# Run a specific test directory
flutter test test/engine/
flutter test test/data/

# Debug build
flutter build apk --debug

# Release build (signed APK)
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# Google Play bundle
flutter build appbundle

# One-shot: debug build + install + launch on emulator
flutter build apk --debug && \
  adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk && \
  adb -s emulator-5554 shell am start -n com.kouwen.app/.MainActivity
```

### Emulator management

```bash
# Start emulator (background, ~30-60s cold start)
/usr/local/android-sdk/emulator/emulator \
  -avd test_phone -no-window -no-audio \
  -gpu swiftshader_indirect -no-boot-anim -no-metrics &

# Wait for readiness
until adb get-state 2>/dev/null | grep -q device; do sleep 2; done

# Screenshot, click, text input, logs, kill — see COMMANDS.md for full reference
```

### Development workflow

```bash
flutter analyze   # 2-5 seconds — catch syntax/type errors
flutter test      # 3-5 seconds — run unit tests
# If both pass → rebuild and install for manual testing
```

## Architecture

### Dependency injection & state management

Riverpod is used throughout. Top-level providers are defined in `lib/providers.dart`:
- `dbProvider` — singleton `AppDatabase`
- Repo providers (`skillRepoProvider`, `conversationRepoProvider`, `modelConfigRepoProvider`)
- Service providers (`apiServiceProvider`, `githubServiceProvider`, `modelManagerProvider`, `secureStorageProvider`)

UI state uses `StateNotifier` + `StateNotifierProvider` (e.g., `ChatNotifier`, `InstallerNotifier`, `SkillInstallNotifier`). Async read-only data uses `FutureProvider` (e.g., `installedSkillsProvider`, `modelConfigsProvider`).

### Data layer (`lib/data/`)

- **`models.dart`** — Domain types: `Skill`, `Conversation`, `Message` (with `MessageRole` enum), `ModelConfig`. All have `toMap()` / `fromMap()` for SQLite serialization. `Skill` supports hierarchical nesting via `parentId` and `isCollection`.
- **`database.dart`** — SQLite via sqflite. Schema version 4. Tables: `installed_skills`, `conversations`, `messages`, `model_configs`. Uses migrations for upgrades. Unique index on `(name, parent_id)` to prevent duplicate skill installs.
- **`repositories.dart`** — Repository classes wrapping `AppDatabase`: `SkillRepository`, `ConversationRepository`, `ModelConfigRepository`. Each handles CRUD + transactions (cascading deletes, dedup checks).
- **`skill_market_service.dart`** — Market catalog loaded from `assets/skills/catalog.json`. `MarketSkill` model with install state tracking. Can install individual skills (download YAML from GitHub/Gitee) or entire collections (scan repo, create parent + children).
- **`skill_source_store.dart`** — Persists user-added custom GitHub/Gitee skill sources in secure storage.

### Engine layer (`lib/engine/`)

- **`skill_parser.dart`** — Parses skill files in two formats: SKILL.md (YAML frontmatter + markdown body, preferred) and legacy YAML. Returns `ParsedSkill` with name, version, system prompt, category, capabilities, etc. Auto-guesses category and icon from skill name keywords.
- **`skill_router.dart`** — Multi-dimensional skill matching: matches user input against installed skills using category keyword hits (+20 each), Chinese name match (+35), system prompt word overlap (+3/hit), description match (+5), and skill name match (+30). Scores ≥ 25 auto-load the skill; scores ≥ 8 show as suggestions. Cache of parsed skills keyed by `id:version`.
- **`prompt_builder.dart`** — Builds the messages array for the LLM API: system prompt, recent history (up to 20 rounds), and user input. Optionally prepends template content.
- **`skill_intro.dart`** — `SkillIntroBuilder` maps raw skill names to Chinese display names, descriptions, usage guides, and sample questions. Uses a hardcoded name map (~100 entries), keyword-based fallback, and defaults derived from skill domains.

### Services layer (`lib/services/`)

- **`api_service.dart`** — Streaming chat via OpenAI-compatible API (`/v1/chat/completions`). Handles SSE parsing, auto-retry (3 attempts for connection errors/5xx), timeout configuration. `detectSearchParam()` returns model-native search parameters for DeepSeek, Qwen, Kimi.
- **`model_manager.dart`** — Orchestrates `ModelConfigRepository` + `SecureStorageService` for CRUD on model configs (alias, URL, model name, API key).
- **`github_service.dart`** — GitHub/Gitee API client for repos, files, PRs, issues. Gitee uses `?access_token=` query param auth.
- **`github_skill_loader.dart`** — Scans GitHub/Gitee repos for skill files (SKILL.md or YAML). Detects structured repos (skills under `skills/` dir) vs flat repos. Supports collection detection (subdirectories of skills). Downloads and parses individual skill content.
- **`github_skill_source.dart`** — `SkillSource` data class for repo references.
- **`web_search_service.dart`** — Web search via Jina Reader (free, no API key). `s.jina.ai` for search, `r.jina.ai` for full-page content fetch. Formats results for LLM context injection.
- **`file_attachment_service.dart`** — Camera capture via `image_picker`, file picking via `file_picker`. Extracts text from text files (up to 500KB, truncated at 10K chars). Supports txt, md, json, xml, csv, log, code files, PDF, images.
- **`secure_storage_service.dart`** — Wraps `flutter_secure_storage` for API keys, GitHub/Gitee tokens, and custom skill sources.

### Feature-based UI (`lib/features/`)

- **`chat/`** — Main chat functionality. `ChatNotifier` (in `providers/chat_provider.dart`) is the largest state machine: creates conversations, loads skills, sends messages with streaming, auto-matches skills via `SkillRouter`, triggers web search on time-sensitive queries, handles API keys. Screens: `ChatScreen`, `ChatListScreen`, `GithubBrowserScreen`. Widgets: `ChatBubble`, `ChatInputBar`, `ConversationTile`.
- **`skills/`** — Skill management. `InstallerNotifier` handles bulk install from GitHub scans with progress tracking and retry. `SkillInstallNotifier` handles uninstall with cache invalidation. Screens: `SkillMarketScreen`, `SkillDetailScreen`, `SkillEditScreen`, `MySkillsScreen`, `GithubSkillScreen`. Widgets: `SkillCard`.
- **`settings/`** — Model config CRUD, GitHub/Gitee connection, skill sources management.

### Widget tests limitation

Widget tests require platform-specific plugins (sqflite, secure_storage) and cannot run in the test environment. All tests are unit tests focused on engine, data, and service layers (`test/engine/`, `test/data/`, `test/services/`).

### Signing (release builds)

Keystore: `android/app/kouwen.keystore`, alias: `kouwen`, password: `kouwen123`. SHA-256: `82ecac4ff0a44cb683c4431f50d660f7d598173edf012fccaedfc121f8ce4541`.

### Skill format

Skills use SKILL.md format: YAML frontmatter between `---` delimiters, followed by markdown body used as the system prompt. Required frontmatter field: `name`. Optional: `version`, `author`, `description`. The parser auto-infers category and icon from the name.

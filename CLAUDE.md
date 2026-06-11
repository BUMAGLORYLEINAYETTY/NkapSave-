# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**NkapSave** — "Intelligent financial management for Cameroon." A Flutter app
(mobile + web) backed by a FastAPI/Postgres API. Core features: expense
tracking, savings goals, Njangi (digital rotating-savings/tontine groups),
Mobile Money auto-save (MTN/Orange via Campay), and **NkapBot**, an
Anthropic-Claude assistant with semantic RAG over the user's own financial data.

This is a single repo with two halves:
- **Flutter app** — repo root (`lib/`, `pubspec.yaml`).
- **FastAPI backend** — `backend/` (its own Python venv, `.env`, `requirements.txt`).

In production the Flutter **web** build is served as static files *by* the
FastAPI app, so one server hosts both the UI and the `/api/v1` endpoints.

## Commands

### Full stack (recommended for local dev)
```bash
bash run.sh          # pub get → flutter build web → activate venv → pip install → uvicorn on :8000
```
This builds Flutter web and serves it through FastAPI. App → http://localhost:8000,
API docs → http://localhost:8000/api/docs. Use this when you need the served-web flow.

### Flutter (iterating on the app)
```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000   # web against local backend
flutter run                                                              # device/emulator (defaults to 10.0.2.2:8000)
flutter analyze                          # lint / static analysis (rules in analysis_options.yaml)
flutter test                             # all tests
flutter test test/path/to/foo_test.dart  # a single test file
flutter test --name "substring"          # a single test by name
```
Hot-reload dev does **not** use `run.sh` (that does a full web build). Point the
app at the backend with `--dart-define=API_BASE_URL=...`. Defaults live in
`lib/core/config/env.dart`: web → `localhost:8000`, mobile → `10.0.2.2:8000`
(Android-emulator host alias). API prefix is `/api/v1`.

### Code generation (required after touching generated code)
Riverpod providers, Freezed models, json_serializable, and Hive adapters are
codegen. After editing any annotated source, regenerate:
```bash
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch  --delete-conflicting-outputs   # leave running while developing
```

### Backend (iterating on the API)
```bash
cd backend
source venv/bin/activate
uvicorn main:app --reload --port 8000
alembic upgrade head            # apply migrations (production path)
alembic revision -m "message"   # new migration
```
Backend config is read from `backend/.env` (see `backend/.env.example`) via
pydantic-settings. `SECRET_KEY` is validated for strength and will refuse to
start if weak. NkapBot needs `ANTHROPIC_API_KEY`; RAG embeddings prefer
`VOYAGE_API_KEY` and fall back to a lexical mode with no key.

## Architecture

### Flutter — feature-first clean architecture
Code is organized by feature under `lib/features/<feature>/` (auth, dashboard,
expenses, savings, njangi, profile, notifications, chat, admin), each split into:
- `data/` — `datasources/` (API calls) + `models/`
- `domain/` — `entities/` + `usecases/`
- `presentation/` — `providers/` (Riverpod) + `screens/` + `widgets/`

Shared infrastructure lives in `lib/core/`. **Read core before adding a feature**
— most cross-cutting behavior is already centralized there.

**State management:** Riverpod (`flutter_riverpod` + `riverpod_generator`).
`ProviderScope` wraps the app in `lib/main.dart`.

**Networking — `lib/core/services/api_service.dart`:** a *static facade* over a
single Dio client (call sites use `ApiService.dio`). Access/refresh tokens are
kept in `FlutterSecureStorage` (Keychain / EncryptedSharedPrefs). The interceptor
implements **refresh-once-and-replay**: on a 401 it tries `/auth/refresh` a single
time, replays the original request on success, and otherwise clears tokens.
`ApiService.authState` (a `ValueNotifier`) fires on login / logout / session
expiry.

**Routing — `lib/core/router/app_router.dart`:** one `GoRouter`. Its
`refreshListenable` is wired to `ApiService.authState`, so auth changes
re-run the redirect and bounce expired sessions to `/login`. The four main tabs
(`/home`, `/expenses`, `/savings`, `/njangi`) live under a `ShellRoute`
(`MainShell`). Routes are also **feature-gated**: `/expenses`, `/savings`,
`/njangi` redirect to `/home` unless enabled in `UserPreferences` (see
`AppFeature` in `lib/core/preferences/app_feature.dart`).

### Design system — single source of truth (enforce consistency)
All UI must use these tokens; **do not hard-code colors, fonts, radii, or
off-grid spacing in screens.**
- `lib/core/constants/app_colors.dart` — `AppColors` exposes **theme-aware
  getters** (`bg`, `surface1..4`, `text1..3`, `border1..3`) plus constant brand
  colors (`primary` violet `#A855F7`, `magenta` `#D946EF`, `accent` `#FFB627`)
  and hero gradients.
- `lib/core/constants/app_palette.dart` — `AppPalette`, a Material 3
  `ThemeExtension`, read via `context.palette.*`.
- `lib/core/constants/app_text_styles.dart` — `AppTextStyles` (DM Sans via
  `google_fonts`): `h1..h4`, `body`, `bodyMuted`, `caption`, `label`, etc.
- `lib/core/widgets/` — reuse `NkapButton`, `NkapCard`, `NkapChip`,
  `NkapTextField` before building bespoke widgets.
- Conventions: radius **16** (buttons/inputs), **20** (cards); spacing on an
  **8/16** rhythm.

**Theme switching is unusual:** screens read `AppColors.*` *static getters*
(resolved at read-time from `UserPreferences.themeMode`), **not** `Theme.of`.
When the user flips the theme, `UserPreferences.notifyListeners()` rebuilds the
root `MaterialApp` (it's wrapped in an `AnimatedBuilder` in `main.dart`), and
every screen re-reads the freshly-resolved color. So a new screen needs no
`Theme` plumbing to be theme-aware — just use `AppColors.*`.

There is a `.claude/agents/stitch-design-reviewer.md` agent that revamps screens
from Google Stitch HTML exports while enforcing these tokens.

### Backend — FastAPI, async SQLAlchemy
`backend/main.py` is the entrypoint. Layers: `routers/` (HTTP) → `services/`
(business logic) → `models/` (SQLAlchemy 2.0 async ORM). `core/` holds
`config.py` (pydantic-settings), `database.py` (async engine, `asyncpg`),
`security.py` (JWT/bcrypt), and `migrations.py`.

- All routers mount under **`/api/v1`**. Docs at `/api/docs`, health at `/api/health`.
- **Dev vs prod schema:** in non-production the lifespan handler auto-runs
  `Base.metadata.create_all` + idempotent `run_dev_migrations`. **Production uses
  Alembic** (`backend/alembic/`) and locks down CORS (`ALLOWED_ORIGINS` required).
- **`APScheduler`** runs background jobs (reminders, auto-save sweeps), started/
  stopped in the lifespan handler.
- **NkapBot** (`routers/nkapbot.py` + `services/nkapbot_*`, `prompt_builder.py`,
  `embeddings.py`): Anthropic Claude (`ANTHROPIC_MODEL`) answering over a RAG
  context built from the user's own expenses/savings/njangi data; embeddings via
  Voyage/OpenAI with a lexical fallback.
- Integrations: Campay (Mobile Money), Twilio, Firebase Admin (push), pytesseract
  (receipt OCR), reportlab/openpyxl (PDF/Excel exports).

### Cross-cutting gotchas
- **KYC is currently disabled.** Frontend flag `kKycEnabled = false`
  (`lib/core/constants/feature_flags.dart`) hides the UI/gates; the backend
  `kyc` router is left on disk but **unregistered** in `backend/main.py`. Keep
  both sides in sync if re-enabling.
- **Feature flags** (`feature_flags.dart`) are the single switch for whether a
  surface appears at all — prefer flipping a flag over deleting UI.
- Frontend ↔ backend contract is the `/api/v1` REST surface; when changing an
  endpoint, update both the router and the corresponding feature `datasource`.

# CNC Partner

Mobile app for **Care n Clean** service partners and their field teams — the
phone-native companion to the Carencleanss partner web portal. One app, three
roles: **Partner (admin)**, **Driver**, and **Crew**. Partners run their
business (bookings, team, vans, earnings, catalog); drivers run their route;
crew run jobs on site.

Built with **Flutter** + **Riverpod**, talking to the CNC CRM backend.

---

## Table of contents

- [Features](#features)
- [Roles](#roles)
- [Tech stack](#tech-stack)
- [Architecture](#architecture)
- [Project structure](#project-structure)
- [Getting started](#getting-started)
- [Configuration](#configuration)
- [Running](#running)
- [Building releases](#building-releases)
- [App icon](#app-icon)
- [CI/CD](#cicd)
- [Backend & API](#backend--api)
- [Conventions](#conventions)
- [Troubleshooting](#troubleshooting)

---

## Features

**Auth & security**
- Email/password login scoped to the `partner` portal
- Forgot password (pre-fills the email typed on login), reset & first-time set
  password with a live rules checklist
- Change password while signed in
- **Biometric quick-login** (Face ID / fingerprint) with **multi-account
  picker** — saved sessions, armed after first login, expired-token fallback
- Token stored in secure storage; auto session restore + expiry watch; 401 →
  sign-out

**Partner (admin)**
- Dashboard with tappable KPI tiles (today / next 7 days / workers / vans) and a
  wallet earnings card — each routes to the relevant screen
- Bookings: search, **quick status filter chips** + a filter sheet (status +
  date range) with removable applied-filter chips; cards show the real reference
  (`CNC-B-####`), payout, schedule; **optimistic status updates** on
  accept/start/complete
- Booking detail screen: full info + **team assign / unassign** flow + lifecycle
  actions (accept / decline / start-with-OTP / complete)
- Workers: list with redesigned cards, inline status change, full add/edit form
  (name, country-code phone, role, zone, status, auto-assign, home address)
- Vans: list with redesigned cards, inline status change, add/edit form (name,
  plate, code, seats, primary zone, **driver**, status, auto-assign, parking)
- Earnings: wallet balance + lifetime totals + **settlement transactions list**
- Reviews: rating summary with half-stars + a distribution histogram
- Business profile: full web-parity view (identity, contact, location,
  commercial, compliance, bank details) with an editable subset
- **Service requests**: 3-tab module — Catalog (Vertical → Category → Service
  tree with **item checkboxes** that auto-link), My linked services, and
  new-service requests + history
- Schedule (day view)

**Driver**
- Route map (Google Maps) with stops + turn-by-turn navigate, today summary

**Crew**
- Jobs: accept / decline / start (customer OTP) / complete, before/after photo
  capture, today summary

**Shared / UX**
- Role-adaptive bottom navigation + role-aware Profile hub
- Light **and** dark theme (follows system), adaptive status bar
- Shimmer loaders, empty/error states, toasts, button busy/disabled states
- Onboarding + splash, permission handling, country-code phone picker, legal
  (Terms / Privacy) and account-deletion screens
- Local notifications (push/FCM is config-gated — see below)

---

## Roles

The signed-in user's JWT carries the role(s). The app adapts navigation and
screens accordingly:

| Role      | JWT signal                         | Lands on    |
| --------- | ---------------------------------- | ----------- |
| Partner   | `role: partner`                    | Dashboard   |
| Driver    | `workerRoles` contains `driver`    | Route       |
| Crew      | `workerRoles` contains `crew`      | Jobs        |

A worker can hold multiple roles (e.g. crew + driver); the shell shows the tabs
they're entitled to.

---

## Tech stack

- **Flutter** (Dart SDK `^3.11.5`)
- **State management:** `flutter_riverpod` (Notifier + Provider)
- **Networking:** `dio` (interceptors for auth + friendly errors)
- **Routing:** `go_router` (role-guarded redirects)
- **Storage:** `flutter_secure_storage` (token, saved accounts) +
  `shared_preferences` (small flags)
- **Auth:** `jwt_decoder`, `local_auth` (biometrics)
- **Maps & links:** `google_maps_flutter`, `url_launcher`
- **Media & UI:** `image_picker`, `shimmer`, `fluttertoast`, `intl`
- **Notifications & permissions:** `flutter_local_notifications`,
  `permission_handler`
- **Tooling:** `flutter_lints`, `flutter_launcher_icons`

---

## Architecture

- **Feature-first** layout under `lib/features/`, shared infrastructure under
  `lib/core/`, reusable widgets under `lib/widgets/`.
- **Repositories** own all API calls and map JSON → models. **Riverpod
  providers** expose repositories; screens watch controllers / call repos.
- **AuthController** (`Notifier<AuthState>`) is the single source of truth for
  the session; it wires the Dio client's token + 401 handler and runs an expiry
  timer.
- **Theme** is runtime brightness-aware via a mutable `AppColors` palette +
  a single `AppTheme.current`.

---

## Project structure

```
lib/
├── main.dart                 # App root, theme + lifecycle + brightness
├── core/
│   ├── auth/                 # AuthController, AuthRepository, JwtUser,
│   │                         #   BiometricService, PasswordRules
│   ├── config/               # Env (API_URL, maps key, portal)
│   ├── network/              # ApiClient (Dio) + ApiException + envelope helpers
│   ├── notifications/        # NotificationService (local notifications)
│   ├── router/               # go_router config + role guards
│   ├── storage/              # AuthStorage (token, saved accounts, flags)
│   └── theme/                # AppColors, AppTheme
├── features/
│   ├── auth/                 # login, forgot/reset/set/change password
│   ├── bookings/             # shared booking models
│   ├── driver/               # route map + repository
│   ├── legal/                # Terms, Privacy, delete account
│   ├── onboarding/ splash/   # first-run + splash
│   ├── partner/              # dashboard, bookings(+detail), workers(+form),
│   │                         #   vans(+form), earnings, profile, schedule,
│   │                         #   requests, service requests, models, repository
│   ├── profile/              # role-aware Profile hub + worker profile
│   ├── reviews/              # ratings + reviews
│   ├── settings/             # notifications settings
│   ├── shell/                # RoleShell (bottom nav), unauthorized
│   └── worker/               # crew jobs, bookings, OTP dialog, today summary
└── widgets/                  # app_states, app_toast, brand_logo, phone_field,
                              #   status_badge, ...
```

---

## Getting started

Prerequisites: a recent **Flutter** stable channel (Dart `^3.11.5`), Xcode
(iOS) and/or Android SDK.

```bash
git clone git@github.com:hassan-t8/cnc-partner.git
cd cnc-partner
flutter pub get
```

---

## Configuration

All config is compile-time via `--dart-define` (see `lib/core/config/env.dart`):

| Key                  | Default                                        | Purpose                         |
| -------------------- | ---------------------------------------------- | ------------------------------- |
| `API_URL`            | `https://dev.api.crm.cnc.marifahlabs.com`      | Backend base URL                |
| `GOOGLE_MAPS_API_KEY`| _(empty)_                                      | Driver route map                |

Example:

```bash
flutter run --dart-define=API_URL=https://dev.api.crm.cnc.marifahlabs.com \
            --dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY
```

**Push notifications (FCM)** are not enabled by default — add your
`google-services.json` (Android) / `GoogleService-Info.plist` (iOS) and wire
Firebase to turn them on. Local notifications work out of the box.

---

## Running

```bash
flutter devices                 # list connected devices/simulators
flutter run -d <device-id>      # run on a specific device
flutter run -d chrome           # web (for quick UI checks)
```

Platform notes:
- **iOS** deploy target is **14.0** (required by Google Maps).
- **Android** uses core-library desugaring (required by
  `flutter_local_notifications`) and a `FlutterFragmentActivity` (required by
  `local_auth`).

---

## Building releases

```bash
flutter build apk --release                 # universal APK (~55 MB)
flutter build apk --release --split-per-abi # smaller per-device APKs (~20-25 MB)
flutter build appbundle --release           # Play Store .aab
flutter build ios --release                 # iOS (then archive in Xcode)
```

> The release build currently signs Android with the **debug** key (fine for
> sideloading/testing, not for the Play Store). Add a real keystore +
> `signingConfig` before publishing.

---

## App icon

Launcher icons are generated from the brand mark with `flutter_launcher_icons`:

```bash
dart run flutter_launcher_icons
```

Source images live in `assets/images/`
(`CNC-Partner-icon-1024-fullbleed.png`). Config is in `pubspec.yaml` under
`flutter_launcher_icons` (Android adaptive + iOS, alpha removed).

---

## CI/CD

GitHub Actions (`.github/workflows/build.yml`) builds the app automatically:

- **On push / PR to `main`** and **manual dispatch** → runs `flutter analyze`,
  builds the universal + per-ABI APKs, and uploads them as the
  `cnc-partner-apks` artifact (Actions → run → Artifacts).
- **On a `v*` tag** (`git tag v1.0.0 && git push --tags`) → also publishes a
  **GitHub Release** with the APKs attached.

Artifacts require a GitHub login to download; for public install links use a
tagged Release on a public repo, or a distribution service (Firebase App
Distribution / Diawi).

---

## Backend & API

The app talks to the CNC CRM backend (default
`https://dev.api.crm.cnc.marifahlabs.com`). Highlights:

- **Auth:** `POST /api/users/login` (`{email, password, portal: "partner"}`),
  password reset/set endpoints, `PUT /api/users/update-password`
- **Partner bookings:** `GET /booking/getPartnerBookings`,
  `/booking/:id/partner-accept|decline|start|complete`
- **Team assignment:** `GET|POST /booking-assignments`,
  `DELETE /booking-assignments/:id`
- **Workers / vans / zones:** `/workers`, `/vans`, `/zones/flat`
- **Earnings:** `GET /settlement/wallet/:partnerId/statement`
- **Reviews:** `/partner/me/rating-summary`, `/workers/me/rating-summary`
- **Partner profile:** `GET /partner/:id`, `PUT /partner/update/:id`
- **Catalog / service requests:** `/catalog/partner/catalog-tree`,
  `/catalog/partner/my-services`, `/catalog/partner/services` (link / syncItems),
  `/catalog/partner/service-requests`
- **Worker self-service:** `/workers/me/profile|bookings|today-summary`,
  attachments upload
- **Driver:** `/routing/driver/:workerId/day`

Responses are typically `{ success, data }`; some (e.g. `GET /partner/:id`)
nest under a named key — the repositories handle the unwrapping.

---

## Conventions

- **Commits:** imperative, scoped (`cnc_partner: ...`).
- **Lint:** `flutter analyze` must be clean (CI enforces it).
- **No secrets in the repo** — pass keys via `--dart-define` / CI secrets.
- **Assets** are never deleted; new images go under `assets/images/`.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `Vertical viewport was given unbounded height` | Don't nest a `ListView` inside another scrollable; use a bounded `Column`/placeholder. |
| `RenderFlex overflowed by N px` | Wrap fixed rows in `FittedBox`/`Expanded`; check fixed widths on small screens. |
| iOS build fails on Google Maps | Ensure iOS deploy target ≥ 14.0 (`Podfile` + project). |
| Android release fails on desugaring | `isCoreLibraryDesugaringEnabled = true` + the desugar dependency are set in `android/app/build.gradle.kts`. |
| Biometric login does nothing | Device must have biometrics enrolled; `MainActivity` must extend `FlutterFragmentActivity`. |
| New app icon not showing on simulator | Delete the app and reinstall (icon cache). |

---

_Internal Care n Clean project. Not for public distribution._

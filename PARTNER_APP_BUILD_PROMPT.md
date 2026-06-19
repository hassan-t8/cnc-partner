# CNC Partner — Flutter App Build Prompt (A‑to‑Z Spec)

> **What this is.** A complete build prompt for the **cnc_partner** Flutter mobile app, derived from a full analysis of the existing **Carencleanss_Partner** Next.js web portal (`carenclean-partner-portal`). The app is a mobile client for cleaning‑service **partner companies** and their **field workers** (crew + drivers), talking to the same backend the portal uses.
>
> **Source of truth.** The web portal at `Carencleanss_Partner/` is the functional reference. For exact API endpoints, **`src/lib/api.ts` is authoritative** (it defines every helper + the exact path). Page files sometimes wrap those helpers, so when an endpoint looks ambiguous, read `api.ts`. The two analyses disagreed on a few paths (e.g. `partnerApi.listBookings()` → `GET /booking/getPartnerBookings` per `api.ts`, vs. `/partner/bookings` inferred from a page) — **verify every endpoint against `api.ts` before wiring it.**
>
> **Backend base URL:** env `API_URL` (portal uses `NEXT_PUBLIC_API_URL`, default `http://localhost:3001`). Dev backend in this monorepo: `https://dev.api.crm.cnc.marifahlabs.com` (confirm with the team).

---

## 0. Goal & High‑Level Requirements

Build a production‑quality Flutter app (Android + iOS) that mirrors the partner portal's functionality with a **mobile‑first, field‑worker‑friendly** UX. It must:

1. Support **three roles** from one login, routing each to its own home (see §2).
2. Be fully **backend‑driven** (no hardcoded data); reuse the portal's exact endpoints, payloads, and response shapes.
3. Handle **auth, token storage, role gating, session expiry, logout** robustly.
4. Provide polished **loading (shimmers), empty, and error states**, **toasts**, and subtle **animations**.
5. Include **splash screen + branded logos** for "CNC Partner" and "CNC Worker".
6. Include **push + local notifications** (job offers, assignment updates, status changes).
7. Include **Terms & Conditions, Privacy Policy, and Account‑Delete** screens (store/compliance requirement).
8. Use a clear **state‑management** approach (recommend **Provider + ChangeNotifier** to match the sibling `cncapp`, or Riverpod — pick one and be consistent).

---

## 1. Tech Stack & Project Setup

- **Flutter** (stable), Dart 3.
- **State:** Provider + ChangeNotifier (default; matches `cncapp`). One controller per feature.
- **HTTP:** `dio` (interceptors for auth + 401) or `http`. Mirror the portal's axios interceptor behavior.
- **Secure storage:** `flutter_secure_storage` for the JWT; `shared_preferences` for non‑secret cache (partner name, last role).
- **JWT decode:** `jwt_decoder` (read `role`, `workerRoles`, `partnerId`, `workerId`, `exp`).
- **Maps:** `google_maps_flutter` + `flutter_polyline_points` (driver route); `url_launcher` for `tel:` and external Google Maps deep links.
- **Notifications:** `firebase_messaging` (push) + `flutter_local_notifications` (local/foreground display).
- **Toasts:** a thin wrapper (e.g. `another_flutter_toast`/`fluttertoast` or a custom `SnackBar`/overlay) replicating react‑hot‑toast top‑position success/error.
- **Shimmer:** `shimmer` package for skeleton loaders.
- **Image upload/capture:** `image_picker` (rear camera, `CameraDevice.rear`) for before/after photos.
- **Phone input:** country‑code picker supporting AE(+971), SA, QA, OM, BH, KW, IN, PK, GB, US with per‑country digit‑count validation.
- **Suggested structure:** `lib/core/` (api client, theme, routes, storage), `lib/features/<feature>/{data,domain,presentation}`, `lib/widgets/` (shared UI).

---

## 2. Roles, Auth & Routing

### 2.1 Roles (from JWT)
JWT payload fields: `id, email?, role, partnerId?, workerId?, workerRoles?[], impersonatedBy?, iat, exp`.

- **`role = "partner"`** → **Partner Admin** (company owner/manager). Full admin module.
- **`role = "driver"`** → **Driver** worker (legacy/explicit driver).
- **`role = "worker"`** → field worker; capabilities come from **`workerRoles[]`** which may contain `"crew"` and/or `"driver"`. Workers can be **multi‑role**.

### 2.2 Landing per role (mirror `landingForUser()`)
- `partner` → Admin dashboard (home).
- `driver` (or `worker` with `driver` in workerRoles) → **Driver "My Route"** (today's route).
- `worker` with `crew` → **Crew "My Jobs"** (today).
- `worker` with both → show both Driver + Crew entries; default to one (portal defaults driver→route).
- No/invalid session → Login. Valid token but forbidden area → "Unauthorized" screen.

### 2.3 Route guarding
Gate every authenticated screen by role (mirror `canEnter()`):
- Admin screens require `role=partner`.
- Crew screens require `worker` + `crew` in workerRoles.
- Driver screens require `role=driver` OR (`worker` + `driver`).
Reject → Unauthorized screen; expired/malformed token → Login.

### 2.4 Session lifecycle
- **Validate token** on app start, on resume (app foregrounded), and on a periodic timer (portal: every 60s + on focus). Decode JWT, check `exp*1000 < now`, check role is acceptable. Invalid → clear session, go to Login.
- **Store:** token in secure storage (key analogous to `cnc_partner_token`); decoded user + cached partner name in prefs.
- **Inject** `Authorization: Bearer <token>` on every request (interceptor).
- **Global 401 handler:** clear session + navigate to Login (replace stack).

### 2.5 Auth endpoints (verify against `api.ts`)
- **Login:** `POST /api/users/login` body `{ email, password, portal: "partner" }` → `{ token, user{ id, role, email } }`. Special: response may carry `{ code: "ACCOUNT_NOT_ACTIVATED" }` (row exists, password null) → show "account isn't activated; check email".
- **Forgot password:** `POST /api/users/password-reset/request` `{ email, portal: "partner" }`.
- **Verify reset link:** `POST /api/users/verify-link-forget-password-crm` `{ token, email }`.
- **Apply reset:** `POST /api/users/reset-password-crm` `{ token, email, newPassword }`.
- **Verify setup (invite) link:** `GET /api/users/verify-setup-link?token&email` → `{ status: valid|consumed|expired|invalid|error }`.
- **Set password (invite):** `POST /api/users/setup-password` `{ token, email, password, confirmPassword }`.
- **OTP:** `POST /otp/send` `{ purpose, referenceId, destination?, userId? }`, `POST /otp/verify` `{ purpose, referenceId, code }`.

### 2.6 Password validation (match backend `passwordValidator.ts`)
Real‑time checklist; submit disabled until all pass + fields match:
1. ≥ 8 chars 2. ≥ 1 letter 3. ≥ 1 digit 4. ≥ 1 special (non‑alphanumeric).

### 2.7 Auth screens to build
Login, Forgot‑password (→ "check your email, link expires 24h"), Reset‑password (verify link → form → success → Login), Set‑password / accept‑invite (handle valid/consumed/expired/invalid states), Unauthorized. Map all HTTP errors to friendly strings (see §9).

---

## 3. PARTNER ADMIN MODULE (role = partner)

Bottom‑nav / drawer groups (from portal Shell): **Overview** (Dashboard), **Operations** (Requests, Bookings, Schedule), **My Team** (Workers, Vans), **Performance** (Earnings, Reviews), **Catalog** (Service Requests), plus **Profile**. Adapt to a mobile bottom‑nav (≤5 primary tabs) + a "More" menu for the rest.

> ⚠ **Endpoint note:** `api.ts` `partnerApi.*` helpers define the real paths (e.g. `listBookings → GET /booking/getPartnerBookings`, `listWorkers → GET /workers`, `listVans → GET /vans`, `ratingSummary → GET /partner/me/rating-summary`, offers via `/offers/mine`, `/offers/{id}/accept|decline`). One agent inferred `/partner/bookings`, `/partner/workers`, `/partner/offers/my` from pages — **trust `api.ts`.** Verify each before coding.

### 3.1 Dashboard
- **Shows:** KPI cards (bookings today, next 7 days, workers count, vans count, week earnings) + **pending‑acceptance** bookings queue.
- **Data:** list bookings (`partnerApi.listBookings`, large limit), workers, vans. Parse defensively across `{data|rows|bookings|data.rows}` envelopes.
- **Actions:** Accept booking (`partner-accept`), Decline (opens reason modal → `partner-decline`), "View all pending" → Bookings filtered, KPI cards → filtered Bookings.
- **States:** skeleton KPIs, error banner (graceful — one failed call doesn't blank page), "All caught up" empty.

### 3.2 Bookings (master list)
- **Shows:** Ref, Customer, Service, Area, Scheduled date/time, Status badge, Partner cost.
- **Data:** `listBookings({limit:500})`. **Booking timestamp resolution order:** `scheduledStart` → `date`+`time` → `selectedDates` (JSON) → `bookingServices` (JSON).
- **Filters (client‑side, AND‑combined):** search (ref/customer/service/area), status dropdown (`unassigned, pending_dispatch, awaiting_acceptance, accepted, in_progress, completed, declined, cancelled, failed_to_assign`), date‑range presets (All, This/Last week, This/Last month, This year, Custom from/to), Clear filters; show "X of Y".
- **Row actions by status:** Team (BookingTeamModal — adjust crew/van), Accept, Decline (reason modal), Start (`partner-start`; if `requiresStartOtp` open OTP modal first), Complete (confirm → `partner-complete`), Review customer (`reviews/partner-submit` with stars+comment), Row → BookingDetailModal (read‑only: customer, schedule, team, lifecycle, pricing, notes).
- **Lifecycle endpoints:** `POST /booking/{id}/partner-accept | partner-decline {reason?} | partner-start {otp?} | partner-complete`; reviews `POST /reviews/partner-submit {bookingId, stars, comment?}`, list `GET /reviews/booking/{id}`.
- **OTP errors** come back in `error` field as `OTP_REQUIRED`/`OTP_INVALID` → show inline in modal (not toast).

### 3.3 Requests (auto‑dispatch offer inbox) — real‑time
- **Shows:** per‑offer countdown (MM:SS, ticks every 1s), service, ref, attempt rank (#N of M cascade), date/time, location, customer (name/phone/earnings), address, proposed crew count + van.
- **Data:** `listMyOffers → GET /offers/mine`; **poll every 15s**; only "open" offers; sort newest first.
- **Actions:** Refresh; expand row; Accept (confirm → `POST /offers/{id}/accept {substitutions?}`); Decline (confirm + optional reason → `POST /offers/{id}/decline {reason?}`). Disable Accept/Decline when countdown expired. Error codes (`no_workers, offer_not_open, offer_expired`) → readable inline text.
- **Countdown colors:** gray expired, amber normal, rose urgent (<5 min). Empty: "No pending requests".

### 3.4 Schedule
- Day‑view grid of crew assignments (ScheduleGrid): 30‑min slots 7am–9pm, worker rows, status‑colored blocks; date prev/next/today + date picker. Data: booking‑assignments + bookings (labels).

### 3.5 Workers (roster)
- **Shows:** name, code, roles, contact (phone+email), rating, SOT %, status (incl. "Pending" when user password null).
- **Data:** `listWorkers → GET /workers`; zones `GET /zones/flat`; services `GET /catalog/partner/my-services`; vans `GET /vans`.
- **CRUD:** create `POST /workers`, update `PUT /workers/{id}`, delete `DELETE /workers/{id}`. Zones `POST /workers/{id}/zones`; services `POST /workers/{id}/services`; availability `…/availability-rules`.
- **Filters:** search (name/code/phone/email), role (crew/driver), status (active/not_working/pending/on_leave/suspended).
- **Worker form:** first name (req), last name, code (auto on create, locked on edit), phone (country picker + digit‑count validation), email (req+format), role (radio crew|driver; driver clears services), primary zone (req), home pickup (address+GPS), status (edit‑only), auto‑assign checkbox, working hours (day toggles + time), additional zones, services (crew‑only tree picker).
- **Account modal:** `GET /workers/{id}/login-info` → status; `POST /workers/{id}/send-reset` (email link), `POST /workers/{id}/set-password {password}` (with random generator + copy), `PUT /workers/{id}/status {status, reason?}` (reactivate/leave/suspend; reason for leave/suspend).
- **Schedule modal:** recurring rules (per day‑of‑week) + exceptions (off/extra, 90‑day window) — create/delete rules & exceptions.

### 3.6 Vans (fleet)
- **Shows:** name, code, plate, seats, driver, parking (Google Maps link), status (active=emerald, maintenance=amber, retired=gray).
- **Data:** `listVans → GET /vans`; drivers `GET /workers?role=driver`; zones.
- **CRUD:** `POST /vans`, `PUT /vans/{id}`, `DELETE /vans/{id}`. Form: name(req), code(unique→409 inline), plate(req, unique→409 inline), seats(1–30), driver(select, show "assigned to X" for taken), primary zone(req), additional zones, status, auto‑assign, parking address + map pin picker.
- **Filters:** search (name/code/plate), status. Empty: "No vans yet…".

### 3.7 Earnings
- **Shows:** wallet balance (hero gradient), period earnings, period bookings, period received; bookings table (Ref, Customer, Service, Scheduled, Status, Your Earning) with pagination (17/page).
- **Data:** `GET /settlement/wallet/{partnerId}/statement` → `{wallet{balance, lifetimeEarnings, lifetimePaidOut}, transactions, total}`; bookings via `listBookings`.
- **Filters:** date‑range presets/custom. **Withdraw** button = placeholder (not wired). Refresh.
- **Calc:** earnings = Σ `partnerCost` on completed in range; received = Σ where `paymentStatus ∈ {full, paid}`.

### 3.8 Reviews
- Shared ReviewsView (`source=partner`) → `GET /partner/me/rating-summary` (per `api.ts`): aggregate score + star distribution bars + review list (customer initial, stars, comment, ref, date). Empty state.

### 3.9 Service Requests (catalog self‑serve)
- **Shows:** my linked services, catalog tree (Vertical→Category→Service), past requests (name, status, admin notes, dates).
- **Data:** `GET /catalog/partner/catalog-tree`, `GET /catalog/partner/my-services`, link `POST /catalog/partner/services {catalogServiceId}`, unlink `DELETE /catalog/partner/services/{id}`, submit `POST /catalog/partner/service-requests {requestedName, description?, targetPriceRange?, notes?}`, list `GET /catalog/partner/service-requests`.
- **Actions:** "I provide this" toggle per service (spinner), Remove linked, New request form (name req), search across catalog. Status colors: pending(gray), in_review(blue), approved_*(green), declined(red).

### 3.10 Partner Profile (view + edit)
- **View:** hero (avatar, name, email, status pill, code, kind, joined), quick stats (rating, SOT%, available, commission%), cards (identity, contact, location/zones, hours, commercial, compliance/TRN, services grouped Vertical→Category, bank details).
- **Data:** `getPartner → GET /partner/{id}`, zones, my‑services, availability rules.
- **Edit:** `updatePartner → PUT /partner/update/{id}` (JSON or multipart with photo). Fields: name(req), contact person, status, auto‑assign, website, phones (repeatable), primary zone(req), additional zones, operating hours (day toggles + presets Mon‑Fri/Mon‑Sat/All week/Clear + time range), bank rows (bankName, branch, accountNumber, iban). Hours saved by deleting old availability rules then `POST /partner/availability-rules` per working day (`{ownerType:"partner", ownerId, dayOfWeek, startTime:"HH:MM:SS", endTime, isActive:true}`). Photo upload with preview.

---

## 4. DRIVER MODULE (role=driver or worker+driver)

Nav: **Today → My route**, **Bookings → My bookings, Schedule**, **Account → Reviews**, **Profile**.

### 4.1 My Route (today) — maps
- **Shows:** van (name/seats/home zone), pending‑acceptance section, today's bookings as tabs, ordered stops (parking→pickups→job→parking), polyline route w/ distance+duration, TodaySummary banner.
- **Data:** `GET /routing/driver/{workerId}/day?date=YYYY-MM-DD` → `{plan{vanName, vanSeats, homeZone, legs[], warnings[]}}`; assignments `GET /booking-assignments?workerId&from&to`; pending `…?workerId&status=pending_acceptance`; per‑booking map `GET /routing/driver/{workerId}/route-map?date&bookingId` → `{stops[], subPolylines[], totalDistanceMeters, totalDurationSeconds, warnings[]}`; today summary `GET /workers/me/today-summary`.
- **Actions:** Accept/Decline pending (`/booking-assignments/{id}/accept|decline {reason?}`), "View all" → bookings, booking tabs select → fetch route‑map, tap stop → focus/pan map, **Navigate** per stop → external `https://www.google.com/maps/dir/?api=1&destination={lat},{lng}&travelmode=driving`.
- **Map:** google_maps_flutter — parking = green circle (home icon), pickup = sky pin, job = violet pin; numbered labels (running counter across day); decode polylines (solid when real, dashed fallback); auto‑fit bounds, pan to focused stop; overlay labels ("Pickup: name" / job address). Handle missing API key + load errors gracefully.

### 4.2 My Bookings (shared WorkerBookings)
- Tabs Upcoming/Completed/All (`GET /workers/me/bookings?status=`). Per row: id, service, customer, status badge, times, phone, address, role, completed‑at. Actions: accept/decline/start(OTP)/complete via `/booking-assignments/{id}/…`.

### 4.3 Schedule (day picker)
- `GET /routing/driver/{workerId}/day?date=` for any date; prev/next/date input; read‑only legs with times/addresses/customers/workers + warnings. Empty: "No stops on this day."

### 4.4 Profile (read‑only) & Reviews
- Profile `GET /workers/me/profile` → `{worker, user}` + `GET /workers/me/rating-summary`. Avatar, name/code/roles/status, rating aggregate, recent reviews, identity (email/zone/home locked), phone/languages locked. Reviews screen = ReviewsView (`source=worker`): big score, distribution bars, review cards. Empty states.

---

## 5. CREW MODULE (worker + crew)

Nav: **Today → My jobs**, **Bookings → My bookings, Week ahead**, **Account → Reviews**, **Profile**.

### 5.1 My Jobs (today) — primary field screen, mobile‑first
- **Shows:** "Up next" hero card (soonest job: status badge + countdown, service+id, when/customer/address, actions, directions + call partner) + assignment list (status‑sorted: pending→in_progress→accepted→completed), each with lifecycle buttons + before/after photo sections.
- **Data:** `GET /booking-assignments?workerId&from(today)&to(tomorrow)`; today summary; attachments `GET/POST /booking-assignments/{id}/attachments`.
- **Actions:** Accept, Decline(reason), **Start** (`/start`; if `{code:OTP_REQUIRED}` open 6‑digit OTP modal → retry with otp; `OTP_INVALID` shows inline), Complete. **Directions** → `https://www.google.com/maps/search/?api=1&query=<address+area>`; **Call partner** → `tel:<phone>`.
- **Photos (Phase 13):** Before (visible accepted/in_progress/completed) + After (in_progress/completed). Camera button → rear camera (`image_picker`, rear) → auto‑upload `POST /booking-assignments/{id}/attachments` (multipart `{file, type, caption?}`) → refresh 3‑col grid; tap image → open full.
- **Countdown:** refresh ~30s; "in 2h 15m", "starts now", "5m late".
- **OTP modal:** 6 single‑digit boxes, auto‑advance, backspace/arrow nav, paste fills all, Enter submits when full; shows booking id + customer; error text.
- Empty: "Nothing scheduled. Enjoy the day."

### 5.2 Week ahead (ScheduleGrid), My Bookings, Profile, Reviews
- Week ahead: day grid (7am–9pm, 30‑min slots, self only) with date nav + Today. Others = shared components (same as Driver §4.2/4.4).

---

## 6. Shared Components to Build (Flutter equivalents)

`Field` (label+required+error), `StatusBadge` (status→color map, see §10), `BookingDetailModal`, `BookingTeamModal` (crew checkboxes + driver/van dropdowns, in‑zone/out‑of‑zone grouping, availability warnings, multi‑crew), `ScheduleGrid`, `ReviewsView`, `ReviewCustomerModal` (1–5 star picker + 2000‑char comment), `WorkerBookings`, `WorkerProfile`, `StartOtpModal`, `DeclineReasonModal` (500‑char), `DriverRouteMap`, `ZonePicker` (single/multi, emirate→area, primary locked), `TodaySummary` (silent‑fail banner), `PhoneCountrySelect`, `ParkingLocationPicker` (address search + map pin), `WorkerServicesPicker` (catalog tree), `WorkerAccountModal`, `WorkerScheduleModal`, `VanModal`, `WorkerModal`, `PartnerProfileForm`.

---

## 7. State Management & Data Layer

- **Controllers** (ChangeNotifier) per feature: `AuthController`, `BookingsController`, `OffersController`, `WorkersController`, `VansController`, `EarningsController`, `ScheduleController`, `ProfileController`, `DriverRouteController`, `CrewJobsController`, `ReviewsController`, `ServiceRequestsController`, `NotificationsController`.
- **API client** (`ApiClient`): base URL from env; request interceptor injects bearer; response interceptor handles 401 (clear+login) and normalizes errors. **Defensive envelope parsing** helper `pickList(resp)` handling `{data|rows|bookings|data.rows}` and bare arrays.
- **No silent caps:** when a list is capped (e.g. limit 500), it matches the portal — keep parity.
- **Polling:** Offers (15s) + countdowns (1s); Crew/Driver today countdown (~30s). Cancel timers on dispose/background.
- **Refetch on resume:** profile & today screens refetch when app returns to foreground (portal refetches on window focus).

---

## 8. Loaders, Shimmers, Empty & Animations

- **Shimmers/skeletons:** the portal uses plain "Loading…" text — **upgrade to `shimmer` skeletons** for lists, cards, KPIs, tables (better mobile UX). Per‑row busy state disables only the acting row's buttons.
- **Empty states:** icon + friendly copy (e.g. "All caught up", "No pending requests", "Nothing scheduled. Enjoy the day.", "No reviews yet — your first job is on the way.").
- **Animations:** modal pop‑in (`scale 0.96→1 + translateY 6→0`, ~160ms ease‑out); `transition-colors`‑style hover/press feedback; sidebar/nav transitions; countdown re‑render. Keep motion subtle (functional, not flashy).

---

## 9. Error Handling & Toasts

- **Toasts** (react‑hot‑toast parity): top position; `success` (confirmations) and `error` (failures). Use for action outcomes ("Team updated", "Booking accepted", "Declined — offer passed to next partner").
- **Map HTTP errors to friendly strings** (don't surface raw API messages). Login examples: 401→"Incorrect email or password", 403→"Your account has been suspended…", 404→"No account found with this email", 5xx→"Server is temporarily unavailable", network→"Can't reach the server. Please check your internet". Forgot‑password: 404 EMAIL_NOT_FOUND→"No partner account is registered with this email", 500 PORTAL_NOT_CONFIGURED→"Reset link can't be sent right now — contact support".
- **Inline errors:** OTP (`OTP_REQUIRED/OTP_INVALID`) and 409 conflicts (van code/plate) shown **inline at the field/modal**, not as toast.
- **Top‑of‑screen error banner** for failed page loads (rose bg + AlertTriangle), with graceful degradation (one failed call shouldn't blank the whole screen).
- **Global 401** → clear session, go to Login.
- (Optional) **Sentry** parity: strip Authorization/Cookie headers before sending.

---

## 10. Design System (match the portal)

- **Brand green:** `brand-600 #059669` (primary), `brand-500 #10b981`, `brand-700 #047857`, `brand-50 #ecfdf5`, `brand-100 #d1fae5`. Theme color `#059669`.
- **Neutrals:** gray‑50 `#f9fafb` background, white cards, gray‑200 borders, gray‑900 sidebar.
- **Accents:** sky (pending/info), emerald (accepted/complete/success), violet (in‑progress/secondary), rose (decline/error), amber (warning).
- **Typography:** system sans; bold headings; `text-xs font-semibold uppercase tracking-wide` labels; mono for booking IDs.
- **Radii:** 4/8/12/16 + full. **Cards:** white + gray‑200 border + `rounded-lg`/`rounded-2xl` + subtle shadow.
- **Buttons:** primary `bg-brand-600` white (hover 700); secondary outlined gray; destructive `rose-600`; disabled 50% opacity.
- **Status → color maps** (replicate exactly):
  - Booking dispatch: `unassigned`→gray, `pending_dispatch`→amber, `awaiting_acceptance`→sky, `accepted`→emerald, `in_progress`→violet, `completed`→gray, `declined`→rose, `cancelled`→gray, `failed_to_assign`→rose(deep).
  - Worker booking: `pending_acceptance`→amber, `accepted`→sky, `in_progress`→violet, `completed`→emerald, `declined/no_show`→rose, `cancelled`→gray.
  - Role badges: crew→sky, driver→violet. Stars: filled amber‑400, empty gray‑300.
- **Icons** (lucide → use `lucide_icons`/Material equivalents): Dashboard=LayoutDashboard, Requests=Inbox, Bookings=ClipboardList, Schedule=CalendarDays, Workers=Users, Vans=Truck, Earnings=Wallet, Reviews=MessageSquare, Driver route=Map, Service Requests=Sparkles, My bookings=ListChecks; actions: Accept=Check/CheckCircle2, Start=Play, Delete=Trash2, Add=Plus, Warning=AlertTriangle, Phone=Phone, Location=MapPin, Time=Clock, Price=CreditCard, Notes=FileText, Date=Calendar, Rating=Star, Email=Mail, Locked=Lock, OTP=KeyRound, Navigate=Navigation, Countdown=Timer, Camera=Camera, Logout=LogOut.
- **Nav:** mobile bottom‑nav for the role's primary destinations + a profile/menu entry; active = brand‑600.

---

## 11. Splash Screen & Logo (generate)

- **Splash:** brand‑green (`#059669`) background, centered logo, app name. Implement with `flutter_native_splash` (Android 12 splash + iOS launch screen) and an in‑app "Authorizing…" gate while validating the token.
- **Logos to generate** (deliver as assets + app icons via `flutter_launcher_icons`):
  1. **CNC Partner** — the portal's mark is a `CnC` badge (rounded square, brand‑600 fill, white bold "CnC"). Generate a clean SVG/PNG logo + monochrome + adaptive‑icon variants, labeled "CNC Partner".
  2. **CNC Worker** — a sibling mark for the worker context (same brand language, e.g. "CnC" with a worker/crew accent), labeled "CNC Worker".
  Provide light/dark and foreground/background layers for adaptive icons. (No image assets exist in the portal — the mark is CSS‑rendered, so these are net‑new and should match the brand exactly.)

---

## 12. Notifications (push + local)

- **Push (FCM):** register the device token after login (per‑role topic or user id); send token to backend (confirm endpoint — likely a `notifications`/`device-token` route; check backend). Handle: **partner** → new dispatch **offer** (with countdown), booking accepted/declined, status changes; **worker** → new assignment (pending_acceptance), start/complete reminders, OTP prompts.
- **Local notifications:** foreground display of FCM messages + **local reminders** (e.g. job starting soon based on countdown), and tap‑to‑navigate deep links into the relevant screen (offer → Requests, assignment → My Jobs/Route).
- Respect OS permission flows (iOS prompt; Android 13+ POST_NOTIFICATIONS). Badge counts for pending offers/assignments where feasible.

---

## 13. Account, Legal & Compliance Screens

- **Logout:** confirmation dialog ("Log out? You'll need to sign in again") → clear secure storage + prefs → Login (replace stack). Place in profile/menu.
- **Terms & Conditions** + **Privacy Policy:** dedicated screens (link to hosted docs or in‑app markdown). Required for store review; link from profile/settings and from login/signup footer.
- **Delete Account:** a screen that lets the user request account deletion (store/Play requirement). For workers, deletion is typically partner‑admin‑managed server‑side — provide a "Request account deletion" flow that calls the appropriate backend endpoint (confirm with backend) or routes to support, with a clear confirmation + consequences notice. Surface this from profile/settings.
- **Settings:** notification toggles, language (if applicable), about/version.

---

## 14. Build Order (suggested)

1. Project scaffold: theme (§10), ApiClient + interceptors, secure storage, env config, routing + role guard, splash.
2. Auth: login, forgot/reset/set‑password, OTP, session lifecycle, logout. Unauthorized.
3. Shared widgets: StatusBadge, Field, modals, toasts, shimmer skeletons, ZonePicker, PhoneCountrySelect.
4. Worker (Crew) module — highest field value: My Jobs (lifecycle + OTP + photos), Bookings, Profile, Reviews, Week ahead.
5. Driver module: My Route (maps), Schedule, Bookings, Profile, Reviews.
6. Partner Admin: Dashboard, Bookings, Requests (offers polling), Workers, Vans, Schedule, Earnings, Reviews, Service Requests, Profile (view/edit).
7. Notifications (FCM + local), Legal/Account screens, Settings.
8. Polish: empty/error states, animations, accessibility, icons/splash/logos.

---

## 15. Open Items to Confirm With Backend/Team (before/while coding)

1. **Exact endpoints** — reconcile `api.ts` vs page usage for: bookings list/lifecycle (`/booking/getPartnerBookings` + `/booking/{id}/partner-*`), workers (`/workers`), vans (`/vans`), offers (`/offers/mine`, `/offers/{id}/accept|decline`), rating summary (`/partner/me/rating-summary`, `/workers/me/rating-summary`). **`api.ts` wins; verify each.**
2. **Base URL** + auth header format; whether a refresh‑token endpoint exists (portal had none — client‑side expiry only).
3. **Push notification** registration endpoint + payload contract + topics.
4. **Account deletion** endpoint / policy (worker vs partner).
5. **Maps API key** provisioning for mobile (Android + iOS) — env `GOOGLE_MAPS_API_KEY`.
6. **Attachment upload** field names/limits; image compression expectations.
7. **`partner` env value** for login (`portal: "partner"`) and any per‑env differences.

---

### Appendix A — Endpoint quick‑reference (verify against `src/lib/api.ts`)

**Auth/password/OTP:** `/api/users/login`, `/api/users/password-reset/request`, `/api/users/verify-link-forget-password-crm`, `/api/users/reset-password-crm`, `/api/users/verify-setup-link`, `/api/users/setup-password`, `/otp/send`, `/otp/verify`.

**Partner:** bookings `GET /booking/getPartnerBookings`; lifecycle `POST /booking/{id}/partner-accept|partner-decline|partner-start|partner-complete`; reviews `POST /reviews/partner-submit`, `GET /reviews/booking/{id}`, `GET /partner/me/rating-summary`; workers `GET/POST /workers`, `PUT/DELETE /workers/{id}`, `/workers/{id}/zones|services|login-info|set-password|send-reset|status`; vans `GET/POST /vans`, `PUT/DELETE /vans/{id}`; zones `GET /zones/flat`; availability `/availability/resolved|rules|exceptions` (+ `/partner/availability-rules` variant seen in pages); offers `GET /offers/mine`, `GET /offers/{id}`, `POST /offers/{id}/accept|decline`; assignments `GET/POST /booking-assignments`, `DELETE /booking-assignments/{id}`, `/booking-assignments/{id}/attachments`; catalog `/catalog/partner/catalog-tree|my-services|services|service-requests`; partner `GET /partner/{id}`, `PUT /partner/update/{id}`, `/partner/{id}/availability-rules`; earnings `GET /settlement/wallet/{partnerId}/statement`.

**Worker:** assignments `GET /booking-assignments?workerId&from&to[&status]`, `/booking-assignments/{id}/accept|decline|start|complete|attachments`; self `GET /workers/me/today-summary|bookings|rating-summary|profile`, `PUT /workers/me/profile`; routing `GET /routing/driver/{workerId}/day`, `GET /routing/driver/{workerId}/route-map`.

### Appendix B — Env vars
`API_URL` (base), `GOOGLE_MAPS_API_KEY`, `FRONTEND_URL`, `SENTRY_DSN?`, `SENTRY_RELEASE?`, `SENTRY_TRACES_SAMPLE_RATE?` (mirror portal's `NEXT_PUBLIC_*`).
</content>

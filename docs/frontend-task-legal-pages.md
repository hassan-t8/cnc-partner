# Frontend task — 2 public pages needed for the Google Play submission

**Requested by:** mobile team
**Needed for:** publishing the **CNC Partner** Android app (`com.carenclean.partner`)
**Priority:** blocking — Google Play will not let the app go live without these URLs

---

## Where these go

The **partner portal** (`Carencleanss_Partner`, `carenclean-partner-portal`,
served at `https://partner.cnc.marifahlabs.com`) is the right home for these,
since they belong to the Partner app rather than the customer site.

That repo is Next.js App Router with **no `middleware.ts`** — the auth guard lives
inside the `(portal)` route group. So anything added at the root of `src/app/`
is public with no further work:

```
src/app/privacy/page.tsx          ->  /privacy
src/app/delete-account/page.tsx   ->  /delete-account
```

Both must be **real routes**. Right now the site is a SPA that answers every
unknown path with HTTP 200 while rendering "404: This page could not be found" —
a soft 404. Google treats that as a broken policy link.

The site-wide `noindex` is fine and does not need changing; Google Play requires
the page to be *publicly reachable*, not *indexed*.

## Why the existing customer page can't be reused

`https://carencleanss.com/privacy-policy` is already live, but it does not satisfy
Google Play. Checked 11 Aug 2026, it:

- is effective **March 20, 2020** and describes **only the website** ("this
  website", "web browsers") — no mention of a mobile app;
- addresses **customers only** — nothing about partners, drivers or crew;
- lists **no device permissions**, while the Partner app declares precise
  location, camera, photos, push notifications and biometrics to Google;
- has **no account-deletion section**.

Google's reviewers compare the privacy policy against the app's Data Safety
declarations. A mismatch this large is one of the most common rejection reasons
and can put a User Data policy strike on the whole developer account, which would
affect all three CNC apps — so we need a separate, app-specific page.

**Suggested approach:** reuse the existing `/privacy-policy` page's layout and
styling, publish it at the new path, and drop in the copy below.

## What's needed

Two **publicly accessible** pages on `carencleanss.com`. Google's reviewers open
these directly, so they must work with **no login, no redirect to a login page,
and no `noindex`/robots block**.

| # | Page | URL to create |
|---|------|---------------|
| 1 | Privacy Policy | `https://partner.cnc.marifahlabs.com/privacy` |
| 2 | Account deletion request | `https://partner.cnc.marifahlabs.com/delete-account` |

If a different path suits the site structure better, that's fine — just send the
final URLs back, because they get typed into the Play Console listing and cannot
be a dead link at any point after launch.

**One thing to confirm before we commit to these URLs:** is
`partner.cnc.marifahlabs.com` the permanent home of the partner portal, or will it
move to a `carencleanss.com` subdomain later? Whatever URL goes into Play Console
must keep working for the life of the app — if it 404s afterwards, Google can pull
the app. If a move is planned, publish these on the final domain now, or keep a
permanent redirect in place.

### Hard requirements (Google rejects on these)

- Reachable over **HTTPS**, publicly, without authentication.
- Must **not** be a PDF, a Google Doc, or a login-gated page.
- Must stay live permanently — a 404 later can pull the app from the store.
- Plain static pages are fine. No app functionality is involved.

---

## Page 1 — Privacy Policy

Use the site's normal page layout/header/footer. The body copy below is the exact
text already shown inside the app, so the two must not drift apart.

> **Title:** Privacy Policy
> **Subtitle/first line:** Last updated: 11 August 2026

**Intro paragraph:**

This Policy explains what data the CNC Partner app collects, how we use it, and
your choices. It applies to partners, drivers and crew using the app.

**1. Information we collect**

Account details (name, email, phone, role, company). Team data you add (workers,
vans, availability, zones), including the home pickup address a partner sets for
a crew member so the driver can collect them on the daily van route. Operational
data (bookings, job status, timestamps, job addresses, before/after photos,
ratings, earnings). Device data (app version, basic diagnostics, push token).

We do not track your device's location. Addresses are the ones you or your
partner enter or pick on a map; the app never records where your phone is.

**2. How we use it**

To operate the partner platform: send and manage job offers, dispatch and route
jobs, verify start codes, record job completion and photos, calculate earnings
and settlements, maintain quality and ratings, and provide support.

**3. Permissions**

Location permission is used only to show the blue "you are here" dot on the map
while you pick an address, so you can orient yourself. Your position stays on
your device and is never sent to us or shared with anyone. Camera access is used
to capture before/after job photos. Notifications are used for job offers and
updates. Biometrics (fingerprint/Face ID) are processed only on your device to
unlock saved sign-in — we never receive your biometric data.

**4. Sharing**

We do not sell your data. We share it only as needed to run the service — for
example with the customer for a booking you fulfil, and with service providers
(hosting, maps, notifications) under appropriate safeguards, or where required by
law.

**5. Retention**

We keep data for as long as your account is active and as required for legal,
settlement and dispute purposes. Completed-booking records may be retained after
account closure as required.

**6. Security**

We use industry-standard measures to protect your data, including encrypted
storage of credentials on your device. No system is 100% secure; keep your login
protected.

**7. Your rights**

You can request access to or deletion of your data from the account screen or by
contacting support. Some data may be retained where the law requires.

**8. Contact**

For privacy questions or requests, contact privacy@carenclean.com.

---

## Page 2 — Account deletion request

Google requires a page a user can reach **from outside the app** (e.g. after
uninstalling) that explains how to delete their account. Same layout as above.

> **Title:** Delete your CNC Partner account

**Body:**

You can delete your CNC Partner account at any time.

**From the app (fastest):** open the CNC Partner app, go to **Profile → Delete
account**, and confirm with your password. Your account is deleted immediately.

**Without the app:** email **privacy@carenclean.com** from the email address
registered on your account, with the subject "Delete my account". We will verify
it is you and complete the deletion within 30 days.

**What is deleted:** your account profile (name, email, phone, role, company),
your team and vehicle records, your saved sign-in, and your push notification
token.

**What is kept, and why:** records of completed bookings, payments, settlements
and invoices are retained where we are legally required to keep them for tax,
accounting and dispute-resolution purposes. These records are no longer linked to
an active account.

**Contact:** privacy@carenclean.com

---

## When done

Send back the two final URLs. Nothing else is needed from the frontend side for
this submission.

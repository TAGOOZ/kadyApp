# Elkady Café App — Feature & Flow Plan

Multi-mode mobile platform for Elkady Café: **dine-in, pickup, delivery**, unified with **loyalty (points / stamps / tiers)** and **gamification**.

- Audience: young Egyptian (16–35), Arabic-first UI with English toggle.
- Payments: cash on pickup / cash on delivery. No POS integration at MVP.
- Design source of truth: Stitch project **"Elkady Café Experience Platform"** (`projects/12860480963451146010`), theme "Heritage Hearth".

---

## 0. Design System (from Stitch)

### Colors

| Token | Hex | Usage |
|---|---|---|
| `deep-forest` | `#004232` | Headers, primary actions |
| `primary` | `#003A2A` | Primary color |
| `primary-container` | `#00533E` | Filled surfaces, active states |
| `primary-fixed` | `#ABF1D4` | Tints, badges |
| `secondary` | `#A53C00` | Accents, prices, secondary CTAs |
| `secondary-container` | `#FF7434` | Highlights, promo chips |
| `cream-parchment` | `#F9EBD7` | Main app background |
| `paper-white` | `#FFF9F0` | Card backgrounds |
| `coffee-bean` | `#4B2C20` | Warm shadows tint, dark text accents |
| `background` | `#F8FAF6` | Scaffold background |
| `error` | `#BA1A1A` | Errors, destructive |

### Typography

| Level | Font | Size/Weight | Notes |
|---|---|---|---|
| display-lg | Be Vietnam Pro Bold | 40px / 700 | -0.02em tracking |
| headline-lg | Be Vietnam Pro SemiBold | 32px / 600 | mobile variant: 24px |
| title-md | Work Sans SemiBold | 20px / 600 | card titles |
| body-lg | Work Sans Regular | 16px / 400 | descriptions |
| body-sm | Work Sans Regular | 14px / 400 | item details |
| label-md | IBM Plex Sans Medium | 12px / 500 | prices, buttons, +0.05em |

Arabic fallback: *IBM Plex Sans Arabic* / *Amiri*. Arabic is default locale (`ar`), English optional (`en`). RTL-first layouts.

### Shape & Spacing

- Radius: sm 4px · default 8px · md 12px · lg 16px · xl 24px · pill 9999px
- Spacing scale: base 4 · xs 8 · sm 16 · md 24 · lg 32 · xl 48 · gutter 16 · margin 20
- Shadows: low-opacity, coffee-tinted (`#4B2C20` @ ~6–10%), highly diffused ("Coffee Shadows")
- Dividers: geometric triangle pattern accent for heritage feel

---

## 1. Roles & Modes

### Roles
| Role | Capabilities |
|---|---|
| Customer | Order (any mode), earn points/stamps, play games, redeem rewards |
| Staff / Barista | Receive/manage orders, check in customers, apply rewards, manage menu/campaigns |
| Driver (optional) | Assigned deliveries, navigation handoff, status updates |
| Admin / Owner | Menu, hours, zones, loyalty rules, basic analytics |

### Service modes (shared loyalty profile)
- **Dine-in** — check in (QR/table number), order from table or counter, earn points (+10% dine-in bonus).
- **Pickup** — order ahead, choose time slot, pay cash at counter.
- **Delivery** — address-based, cash on delivery; café or partner driver.

---

## 2. Screen Inventory & Stitch Coverage

### ✅ Already designed in Stitch

| # | Screen | Stitch screen ID |
|---|---|---|
| S0 | Onboarding Welcome | `e0bc068cb9fb4671aa6dde6dd64ecba7` |
| S0 | Phone Verification + OTP | `637c3ee6b73a49aba568b35e66baeadf` |
| S1 | Home Dashboard (AR) | `4e0c07f39fc84eff95e4688876696748` · EN `12b61de414d44abf8ba2de0b9d215b07` |
| S2 | Mode Selection (AR) | `75255c0ede9c41e9947f1c6f4d0ebe67` · EN `38f5cdb0fc79414dab8373b513cca939` |
| S3 | Menu (AR) | `66a8667b91e7492a8c59389806dfc921` · EN `5ee54e3e39354de5946181149285318a` |
| S3b | Item Detail modal | `8df188c2225642b1956e4056edeb498e` |
| S4 | Cart & Checkout (AR) | `334887c86f3146f39f38f594ff13f738` |
| S4b | Order Confirmation | `8085f5fe65c34c9b991e1515d2d214d7` |
| S5 | Order Status timeline (AR) | `6edff00f5fda4764b4b91c8eca08fbd5` |
| S6 | Loyalty & Games hub (AR) | `1ba8b2eda00c4dd582605e6a7923c166` · EN `6e00733b82e14a5489a8253f7fe12ffc` |
| S7 | Spinner of Luck (AR) | `40b09fc8661e4e7e88de9d804b9edffe` |
| S8 | Staff Dashboard (AR) | `7dd506e8df2a4bbc8609f1d4e0da6e8f` · Utility/orders `eec299fa86cd479e99619be821a67152` · Pro redesign `f00d398f2bcc42c68a4846e41ab49c30` |
| S9 | Driver Dashboard (AR) | `fc1defe107204839a63f1e3279ebaeb2` · Driver Order Detail `ac5a748447ac42728ed7d9842577a9fd` |

### ✅ Completed gap screens (Aug 2026 session)

| # | Screen | Stitch screen ID |
|---|---|---|
| G1 | Welcome / onboarding | `e0bc068cb9fb4671aa6dde6dd64ecba7` |
| G2 | Phone auth + OTP | `637c3ee6b73a49aba568b35e66baeadf` |
| G3 | Item detail modal | `8df188c2225642b1956e4056edeb498e` |
| G4 | Order confirmation summary | `8085f5fe65c34c9b991e1515d2d214d7` |
| G5 | Profile & settings (+addresses) | `b8148131e88f4daaaa692563d771f2a7` · alt `fff835a5043741208838cb5544ddec7e` |
| G6 | Guest → save profile prompt | `e9e17252260c4c1daf87e2372e1966b0` (+ mascot image asset `ed920dbf67884ed88d00d13ab0e9720c`) |
| G7 | 3-Card Match game | `ece9e5ede25c44e3bb6d08d6fb3bf929` |
| G8 | Scratch & Win | `169e67ac1a9048d2a2dd39ae2bc584a1` · alt `3e8ee1f8c2ea44cba266829c50baaf8f` |
| G9 | Quests & Badges hub | `9574eed6ca9744cd8f8de19c2978e4ef` |
| G10 | Staff orders list (utility view) | `eec299fa86cd479e99619be821a67152` |
| G11 | Admin campaign management | `f1b41151707b4031899b896b6765e022` |
| G12 | Driver order detail | `ac5a748447ac42728ed7d9842577a9fd` |
| — | Coffee-cup mascot illustration | `ed920dbf67884ed88d00d13ab0e9720c` |

### ⬜ Still missing

| # | Screen | Priority | Note |
|---|---|---|---|
| G10b | Staff customer lookup | P1 | Generation repeatedly rejected server-side ("invalid argument"); staff orders screen already has search entry point — retry later or build directly in Flutter |
| — | Staff order detail sheet | P2 | Can reuse order card expanded state |
| — | Admin menu CRUD editor | P2 | Phase 3 per plan |

---

## 3. Customer Flows

### 3.1 Onboarding & Auth
- Welcome: value prop ("Earn points, play games, get rewards"), `Continue with Google`, `Skip for now`. **Google OAuth is the anti-fake gate** (Supabase `signInWithOAuth(provider: google)`, free, verified — reduces fake accounts vs phone-OTP).
- After Google sign-in: collect **phone number** (required, `+20…` format, DB `UNIQUE` constraint) + name (+optional email prefilled from Google) + optional birthdate / "Student?" / city. No SMS OTP in v1 — phone is validated by format + uniqueness only; real `verifyOtp` can re-enable later without changing loyalty logic.
- **Identity remains phone** (`CONTEXT.md`: one Customer per phone). Google account is linked 1↔1 to that phone; all loyalty/orders still keyed by phone so Staff lookup by phone works. Google session simply prevents anonymous bulk account creation.
- **Guest mode**: browse + one order allowed; after first order prompt to `Sign in with Google` to keep points (same phone prompt follows).

### 3.2 Home (hub)
Greeting + tier chip (Bronze/Silver/Gold); points widget (`120 / 200 → Free drink`); stamp card widget (`7/10 visits → Free snack`); quick actions: Order · Scan & earn · Play game · Rewards; banner carousel (campaigns/quests).

### 3.3 Mode Selection
Three cards with helper text:
- Dine-in: "Check in, order from table or counter, earn points."
- Pickup: "Order now, pick up at Elkady Café."
- Delivery: "Order to your address. Cash on delivery."

### 3.4 Menu (shared across modes)
Category tabs (Hot Drinks, Cold Drinks, Snacks, Specials). Item rows: photo, name AR(+EN), description, price. Item detail modal: size, sugar level, add-ons, special instructions note, Add to cart / Favorite.

Mode-specific requirements before confirming:
- Dine-in → table number or area (inside/terrace)
- Pickup → time slot
- Delivery → saved address or add-address prompt

### 3.5 Cart & Checkout
Items with modifiers/quantities; order notes; subtotal + delivery fee (delivery only, flat 15 EGP default, admin-editable). **No service-charge line in v1** (hidden; constant kept for later). All numerals rendered as Western `0123` in both Arabic and English (AR-Indic from Stitch normalized at render). Order display number shown as local increment `#NNNN` (e.g. `#1023`).
Loyalty box: points to be earned preview (round half-up, after ×1.1 dine-in multiplier); reward redemption ("Use 200 pts for free drink?"); optional group-order bonus line if group rule applies (see §9).
Payment: Pay at café (cash) / Cash on delivery. Confirmation screen: mode, items, slot/address, ETA.

### 3.6 Order Status
Timelines per mode:
- Dine-in: Received → In preparation → Ready → Served
- Pickup: Received → In preparation → Ready for pickup
- Delivery: Received → In preparation → Out for delivery → Delivered (+driver name/phone, map link)

### 3.7 Profile & Settings
Name/phone/email/birthdate/student toggle/default area; saved addresses (Home/Work labels); notification prefs (order updates, promos, match nights, exam season); language ar/en.

---

## 4. Loyalty Rules (initial config)

### Points
- Earn: **1 pt / 10 EGP**; dine-in multiplier **+10%**; campaign double-point windows (quiet hours/exam season).
- **Rounding: round half-up on the final earned value** (after multipliers) — e.g. 95 EGP → 9.5 → 10 pts; dine-in 90 EGP → 9×1.1=9.9 → 10 pts.
- Spend: rewards catalog (free drink, discount, free topping); min redemption threshold **200 pts**.
- Catalog v1 (MVP): free topping **100 pts** · free snack **150 pts** · free drink (any ≤60 EGP) **200 pts** — all thresholds admin-editable via #015 (loyalty params editor).

### Stamp Cards
- 10-slot digital card; qualifying visit = spend ≥ **50 EGP**; full card → fixed reward (free snack); every 3rd stamp grants a Spinner Token. Campaign-specific cards (Ramadan, match nights) deferred post-MVP. All thresholds admin-editable (#015).

### Tiers
| Tier | Criteria | Benefits | Admin-editable |
|---|---|---|---|
| Bronze | default | — | — |
| Silver | 2000 lifetime pts | Occasional free delivery, more frequent game access | thresholds tunable via Admin |
| Gold | 5000 lifetime pts | Busy-hour priority, exclusive offers, lower delivery fee, extra birthday reward | thresholds tunable via Admin |

Delivery fee default **15 EGP flat citywide** for MVP; **admin-editable** via Admin → Campaign Management (#015). Zoned fee table (polygon / per-area fees) deferred to Phase 2 and built as an extension of the Admin zone editor, reusing the same orders-fee calculation hook.

---

## 5. Gamification

| Feature | Trigger | Outcomes/Rewards |
|---|---|---|
| **Spinner of Luck** | Every 3rd stamp; re-engagement campaigns | 5 pts / 10 pts / free topping / double-points-next-visit / nothing (rare big wins tuned low) |
| **3-Card Match** | Unlocks after stamp-card completion or monthly quest | Small: pts · Medium: discount · Large (rare): free drink; themed symbols (cup, bean, Elkady icon) |
| **Scratch & Win** | Inactive users; special days (Ramadan nights, Eid, Valentine's, match victories) | Same pool as spinner |
| **Streaks** | Weekly streak (X consecutive weeks); short daily campaigns | Extra pts, game unlock token, one-time discount/free topping; flame/calendar indicator on home |
| **Quests** | e.g. "Try 3 different drinks this month", "Order during a match night", "One delivery + one pickup this week" | Progress bar + deadline + defined reward (pts/stamp/game token) |
| **Badges** | Identity/community: Match Night Regular, Exam Warrior, Ramadan Night Owl, Gold Tier Loyalist | Shown in profile, highlightable on home |

---

## 6. Staff Dashboard

- **Orders list**: tabs All/Dine-in/Pickup/Delivery; card = ID, name+phone, mode+timing, items summary, status chip; actions accept/reject, advance status, adjust expected-ready time.
- **Dine-in/pickup ops**: QR or phone check-in; attach table/area; mark pickup Ready (on counter).
- **Delivery ops**: see assigned driver; edit address notes; Out for delivery / Delivered transitions.
- **Customer lookup**: search by phone/name; visit/order history; manual reward apply (service recovery).
- **Admin**: menu CRUD; opening hours & delivery availability per day; zones+fees; loyalty params (pts/EGP, thresholds); schedule quests/promos/streaks.

Status vocabulary: New → Accepted → In prep → Ready → Out for delivery → Delivered/Served.

---

## 7. Driver App

- Auth: phone + password (admin assigns orders).
- Assigned list: pickup location, customer address, items summary.
- Detail: map preview + external navigation handoff; statuses Accepted/Picked up/Delivered; delivery notes (building, floor, landmarks).
- History: completed deliveries.

---

## 8. Notifications

| Type | Examples |
|---|---|
| Transactional | Accepted / Ready / Out for delivery / Delivered; driver nearby |
| Promotional | We-miss-you (inactivity), Ramadan quests launch, match-night specials, exam bundles, quiet-hours double points |
| Loyalty/games | Streak reminders, quest progress/completion, game unlock (spinner/scratch available) |

---

## 9. Egyptian-Market Considerations

- Arabic default, casual friendly tone; late-night availability surfaced explicitly.
- Exam-season emphasis for students; football-match & holiday campaigns.
- Group mechanics **in MVP**: staff check-in grants a bonus when ≥3 Customers check in within a short window (same table/area); a group delivery order (multiple Customers on one address) also grants bonus points/stamp. Tuned via loyalty config (group bonus = extra points configurable in #015).
- Initial menu catalog is **seeded from an owner-provided sheet** (items, AR/EN names, prices, photos). Admin CRUD (#015) is the editor thereafter.
- Project & bundle identity: `kady_app` (`com.elkadycafe.kady_app`) — kept as scaffolded.
- Cart & group bonus, stamp, and tier rules all admin-editable defaults (see §4).

---

## 10. Constraints & Phasing

- MVP: no POS; cash only; single branch; orders/payments tracked in-app.
- Phase 1: dine-in/pickup + core loyalty + spinner. Phase 2: delivery + driver app + quests/badges/match/scratch. Phase 3: analytics, online payments, social sharing, multi-branch.

---

## 11. Decisions (resolved Aug 2026 — grill-with-docs session)

1. **Missing screens**: remaining unddesigned pages (customer lookup, order detail sheet variations, admin menu CRUD) **coded locally** in Flutter — Stitch set considered complete at 13 new screens.
2. **Backend**: **Supabase from day one** (`https://zrlhtwmzuljsqricpxbb.supabase.co`, `supabase_flutter` + Riverpod) — see ADR-0001. Repository interfaces stay but implementations are Supabase-backed from slice #001 onwards; cross-device sync works from day one.
3. **State management**: **Riverpod** (plus `riverpod_generator`) — ADR-0002.
4. **Auth**: **Google OAuth gate + phone collection** — Google `signInWithOAuth` is the anti-fake gate (free, verified); phone remains the canonical Customer key (`CONTEXT.md`) — collected after Google, validated by `+20…` format + DB `UNIQUE`, no SMS OTP in v1; `verifyOtp("123456")` path removed.
5. **Driver app**: **single binary + hidden role switcher** (customer/staff/driver/admin) for MVP; shared in-memory orders store; separate binary deferred to Supabase/realtime phase.
6. **Menu data**: **owner-provided sheet seeded** into `lib/data/menu_repository.dart`; Admin menu editor thereafter.
7. **Delivery zones/fees**: **flat 15 EGP citywide**, **admin-editable** via Admin → Campaign Mgmt (#015); zoned/polygon fees deferred to Phase 2.
8. **Minimum qualifying spend**: **50 EGP** for a stamp; admin-editable.
9. **Rewards catalog v1**: **free topping 100 pts · free snack 150 pts · free drink (≤60 EGP) 200 pts**; each threshold **admin-editable**; min redemption 200 pts.
10. **Package/bundle**: **keep `kady_app` / `com.elkadycafe.kady_app`** as scaffolded.
11. **Numerals**: **Western `0123` in both Arabic and English** (Stitch Arabic-Indic normalized at render).
12. **Order numbers**: **local `#NNNN` increment** (e.g. `#1023`), persisted in prefs.
13. **Dine-in service charge**: **hidden row in v1** (constant kept for later).
14. **Tiers**: **Bronze default · Silver 2000 · Gold 5000** lifetime pts; thresholds admin-editable.
15. **Group mechanics**: **included in MVP** — ≥3 check-ins in window → bonus; group delivery order → bonus.

16. **Storage** (Tech): **Supabase Storage bucket `menu-photos`** public; `menu_items.image_url` holds the URL — ADR-0005.
17. **Realtime** (Tech): **Supabase Realtime on `orders`** via Riverpod `StreamProvider` — ADR-0006.
18. **Error UX** (Tech): **online-only** — offline banner + snackbar `Failed — Retry` preserving cart/form; background auto-retry (3× exponential) — standard apps pattern.
19. **RLS** (Tech): **`customers.google_user_id = auth.uid()`** with phone as business key — ADR-0007.
20. **Testing** (Tech): **Full TDD + integration** per slice (unit for loyalty/cart math, widget goldens for flows, Patrol/integration for place-order → status).
21. **Shipping** (Tech): **manual builds only** for web + APK in v1; no auto-deploy pipeline.

22. **Notifications** (Tech): **in-app Realtime only** in MVP; no FCM/APNs. Push deferred to Edge Function + FCM phase.
23. **Analytics** (Tech): **none in MVP**; add PostHog/Firebase when funnel needed.
24. **Crash reporting** (Tech): **none in MVP**; manual + Supabase logs.
25. **Envs** (Tech): **single Supabase project** for dev/prod — ADR-0008.
26. **Images** (Tech): **`cached_network_image` + parchment placeholder**.
27. **Lists** (Tech): **paginated infinite scroll (20)** via Supabase `.range()`.
28. **Search** (Tech): **`ilike %term%` on `phone` + `name`**.
29. **Throttle** (Tech): **Edge Function rate limit** (5/5min) + app 30s debounce — ADR-0010.
30. **Time** (Tech): **store UTC (`timestamptz`), display `Africa/Cairo`** — ADR-0009.

31. **Check-in** (Tech): **QR + manual fallback** — Customer QR (`phone` hash) scanned by Staff `mobile_scanner`; fallback phone/table entry.
32. **A11y** (Tech): **basic semantics** — `semanticsLabel`, headings, contrast-checked tokens; no full WCAG audit in v1.
33. **Perf** (Tech): **strict — web <1.5s + APK <20MB** — deferred imports, `cached_network_image` with downscaling, `--analyze-size` check.

Unresolved: Deep links for shared orders, app icon/splash, and localization workflow — say `continue` to grill those, or `build` to start slice #001.

---

*Source: product plan provided Aug 2026 + Stitch project `12860480963451146010`. This doc is the implementation contract; update it when decisions land.*

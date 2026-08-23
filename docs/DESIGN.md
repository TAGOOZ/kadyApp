# Elkady Café — Design System (Heritage Hearth)

Flutter translation of FEATURES.md §0. Code source of truth: `lib/core/theme/app_theme.dart`.

## Color tokens

| Token | Hex | Role |
|---|---|---|
| `primary` | `#003A2A` | Headers, primary actions, filled chips |
| `primaryContainer` | `#00533E` | Filled dark surfaces, active states |
| `primaryFixedTint` | `#ABF1D4` | Tints, badges, prize surfaces |
| `secondary` | `#A53C00` | Prices, accents, secondary CTAs (6.18:1 on paper-white) |
| `secondaryContainer` | `#FF7434` | Highlights only — never text (2.7:1 as text) |
| **`textMuted`** | `#55605B` | Body/caption ink on light surfaces (added in polish pass) |
| `coffeeBean` | `#4B2C20` | Primary text ink, shadow tint |
| `parchment` | `#F9EBD7` | App background fills, inactive chips |
| `paperWhite` | `#FFF9F0` | Card backgrounds |
| `background` | `#F8FAF6` | Scaffold background |
| `error` | `#BA1A1A` | Errors, destructive |
| `outline` | `#6F7974` | **Strokes/dividers/decorative icons only — never copy** |

### Contrast ledger (WCAG, measured pre/post polish)

| Pair | Before | After |
|---|---|---|
| Muted captions on paperWhite (`outline`) | 4.30 ✗ | `textMuted` 6.25 ✓ |
| Muted captions on parchment | 3.84 ✗ | `textMuted` 5.57 ✓ |
| Muted captions on background | 4.29 ✗ | `textMuted` 6.23 ✓ |
| Price orange `secondary` on paperWhite | 6.18 ✓ | unchanged (no `priceInk` needed) |
| Gold tier chip fg on paperWhite | 4.28 ✗ | `#8A6200` 5.24 ✓ |
| Staff status "ready" fg on 12% tint | 4.35 ✗ | `#156B41` 5.24 ✓ |
| Staff status "out for delivery" fg on tint | 2.30 ✗ | `#9E3900` 5.47 ✓ |
| Staff status "done" fg on tint | 3.75 ✗ | `textMuted` 5.30 ✓ |
| White banner copy on gradient light stop | 1.76–2.69 ✗ | deep-ember stops ≥ 4.91 ✓ |

## Type scale (`AppTextStyles`)

Hierarchy comes only from named styles; no ad-hoc `fontSize:` outside the theme file.

| Style | Size/Weight | Height | Use |
|---|---|---|---|
| `displayLg` | 40 / 700 | 1.15 | Welcome hero |
| `headlineLg` | 32 / 600 | 1.20 | App name |
| `headlineMobile` | 24 / 600 | 1.25 | Screen titles |
| `titleMd` | 20 / 600 | 1.25 | Section headings |
| `titleSm` | 16 / 600 | 1.25 | Card/list titles, in-card headers |
| `bodyLg` | 16 / 400 | 1.35 | Descriptions |
| `bodySm` | 14 / 400 | 1.35 | Item details |
| `labelMd` | 12 / 500 | 1.30 | Chips, timestamps |
| `priceSm` / `priceLg` | 14·18 / 700 | 1.3·1.25 | Money emphasis |

Heights ≥1.15 everywhere (Arabic needs the extra leading). Weight-only `copyWith(fontWeight:)`
on a named style is allowed emphasis; size drift is not. Emoji glyph placeholders (☕) are
illustration sizing, exempt.

## Shape & elevation

- Radii scale 4 · 8 · 12 · 16 · 24 · pill. Cards cap at `AppRadii.xl24`; pill for chips/buttons.
- Shadows: `AppShadows.coffeeShadows()` (coffee-bean tint ~8%, diffused).
- **Ghost-card ban**: a surface carries EITHER a hairline border OR a soft shadow, never both.
- No nested cards; inner selectable rows use bordered `Material` without shadows
  (checkout `_AddressOption`). Sticky-footer top hairlines are separators, not accents.
- Western digits everywhere (§11.11); Arabic-first RTL.

## Motion

- House curves: `easeOutCubic` family only. Bounce/Elastic/back-overshoot banned.
- Every looping/auto animation respects `MediaQuery.disableAnimations`:
  - Banner carousel: auto-advance timer never starts under reduce-motion.
  - Order timeline pulse: controller stopped; static halo.
  - Confetti burst: skipped; delivered banner carries the celebration.
  - Menu shimmer: static skeleton at fixed opacity.
- Transitions 150–400 ms; state-change feedback only.

## Copy

- Buttons: verb + object (أضف للسلة، استلم المكافأة). Sheet-dismiss buttons say إغلاق, never حسناً/OK.
- Errors state what happened + what to do next (Failed — Retry family).
- No all-caps Latin strings; uppercase exists only as avatar-initial rendering.

## Known trade-offs

- Staff statuses `جديد` (#A53C00) and `خرج للتوصيل` (#9E3900) sit close in hue; both must clear
  AA on their tints, so differentiation leans on the label + flow position. Revisit if a
  mid-luminance accent is ever added to the palette.

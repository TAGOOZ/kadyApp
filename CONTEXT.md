# Elkady Café App

Multi-mode café platform (dine-in, pickup, delivery) for Elkady Café, unified by a single loyalty & gamification system. Arabic-first for a young Egyptian audience; cash payments; no POS integration in v1.

## Language

### People

**Customer**:
A person who orders through the app in any service mode and accumulates loyalty. One Customer per phone number — the phone number identifies the Customer everywhere (app, staff lookup, loyalty).
_Avoid_: user, member, account, client

**Guest**:
An unidentified Customer using the app without registering. Has local-only progress; prompted to register after their first completed Order so progress isn't lost.
_Avoid_: anonymous user, visitor

**Staff** (aka Barista):
A café employee who receives, accepts and progresses Orders, checks Customers in, and may grant manual rewards.
_Avoid_: admin (that's a different role), cashier

**Driver**:
The person fulfilling Delivery Orders; picks up at the café, delivers to the Customer, collects cash.
_Avoid_: courier, delivery man

**Admin** (aka Owner):
Configures menu, hours, campaigns and loyalty rules; views reports. Not involved in live order flow.
_Avoid_: manager, staff (overloaded)

### Ordering

**Service Mode**:
One of Dine-in, Pickup, or Delivery. Every Order has exactly one; all modes feed the same loyalty profile.
_Avoid_: channel, type

**Dine-in**:
Customer is physically at the café. Requires a table number or area; earns a dine-in bonus multiplier.
_Avoid__: eat-in, in-store

**Pickup**:
Customer orders ahead and collects at the counter within a chosen time slot.
_Avoid_: take-away, takeaway, carryout

**Delivery**:
Order brought to a saved address; cash collected on arrival by a Driver.
_Avoid_: shipping

**Check-in**:
Staff action attaching a physical visit to a Customer (QR or phone/table entry), optionally tagging table/area.
_Avoid__: login (reserved for authentication)

### Loyalty

**Visit**:
A real-world purchase occasion at the café, recorded via Check-in or a qualifying Order.
_Avoid_: transaction, session

**Qualifying Visit**:
A Visit whose spend meets the minimum-stamp threshold; adds one Stamp.

**Stamp**:
One slot filled on a Stamp Card (10 slots). Completing a card grants a fixed reward.

**Points**:
Spend-based currency (default 1 pt / 10 EGP). Spendable on the Rewards Catalog above a minimum redemption threshold.
_Avoid_: coins, credits, stars

**Lifetime Points**:
Cumulative Points ever earned; never spent down; determines Tier.

**Tier**:
Status level derived from Lifetime Points (Bronze/Silver/Gold); grants standing benefits.
_Avoid_: level, rank

**Voucher**:
A concrete granted reward awaiting use (free drink, free topping, free snack).
_Avoid_: coupon, promo code, gift

**Game Token**:
A consumable play credit for a specific game (Spinner Token, Match Token, Scratch Token).
_Avoid_: coin, ticket

# TESTING.md — in-game verification checklist

This mod ships **without runtime testing**. It was written against verified
Factorio 2.1 API facts and validated only by static analysis (JSON + Lua
syntax). Please walk through the checklist below in order and report anything
that deviates from the *Expected outcome* lines.

**Setup for most tests:** a fresh vanilla-ish save with **Unichest** (>=
1.0.10) and **unichest-logistics** enabled. `/editor` or cheat mode is fine for
speeding things up (inserters, belts, chests from the cheat menu).

---

## 1. Request UI unlocked before any research

1. Start a fresh save with Unichest + this mod. Research **nothing**.
2. Open the character inventory (E) and look at the personal logistics request
   panel.

**Expected outcome:** the request panel is visible and usable immediately
(no technology required). This works for *existing* players too because the
unlock runs from `on_init`, `on_configuration_changed`, and
`on_player_created`.

## 2. Basic fulfillment up to max

1. Place a unichest anywhere on the player's surface.
2. Set the unichest's filter to **transport-belt**.
3. Insert **200 transport belts** into the unichest.
4. Set a personal logistic request for **transport-belt: min 50 / max 100**.
5. Wait up to ~30 ticks (~0.5 s).

**Expected outcome:** exactly **100** belts land in your inventory in one pass
(0 → 100: below min 50 triggers a refill that tops you up to max 100). The
unichest now holds 100 belts. No further deliveries happen while you hold
>= 50.

## 3. Refill after draining below min

1. From the state of test 2 (100 belts in inventory), drop or trash belts until
   you hold **fewer than 50** (e.g. 20).
2. Wait up to ~30 ticks.

**Expected outcome:** you are topped up to **100** again (below-min triggers
refill-to-max).

## 4. Full inventory — no duplication or loss

1. Set a request for an item (e.g. transport-belt, min 50 / max 100) and fill
   the unichest with 200 of it.
2. Fill your main inventory completely (each slot occupied) **before** the next
   delivery, e.g. by disabling the request, filling slots, re-enabling.
3. Wait several 30-tick passes.

**Expected outcome:** nothing is delivered (nowhere to put it), and — critically
— **no items are lost or duplicated**: the container keeps exactly what it had.
(The transfer order is insert-into-player-first, remove-from-container-second,
so a full inventory can never destroy items.) Free a few slots and the next
pass delivers normally.

## 5. Cursor guard

1. With a pending request below its minimum, pick up a stack of the requested
   item onto the cursor (pick it from a container or the ground; do **not**
   place it).
2. Wait past the next 30-tick pass.

**Expected outcome:** **no delivery** while the matching item+quality sits on
the cursor. Place the cursor stack down (or into a slot) and the next pass
delivers normally.

## 6. Per-user setting toggle

1. With a pending below-min request, open *Settings → Mod settings → Per
   player* and switch **Enable Unichest Logistics** off.
2. Wait several passes. Then switch it back on.

**Expected outcome:** deliveries **stop** while off and **resume** within one
30-tick pass after switching on.

## 7. Personal logistics switch (`point.enabled`) respected

1. With a pending below-min request, toggle the **personal logistics** on/off
   switch (the vanilla enable/disable button for your logistics requests).
2. Wait several passes. Toggle it back on.

**Expected outcome:** deliveries **stop** while the switch is off and resume
when on.

## 8. No / empty containers — no crash

1. With a request set (below its minimum), ensure there is **no** linked
   container on your surface. Wait several passes.
2. Then place a unichest but leave it **empty**. Wait several passes.

**Expected outcome:** no delivery in either case, and — most importantly —
**no crash / no error in log** (`factorio-current.log` stays clean).

## 9. Ignored filters — no crash

1. Set a **fluid** request (e.g. crude-oil barrel is fine, but ideally pick a
   actual fluid filter via a mod like Fluid Request if available — otherwise
   verify with a `>`-comparator filter if your setup allows one).
2. Wait several passes.

**Expected outcome:** the filter is simply **ignored** (nothing delivered, no
crash). If you cannot create a fluid or non-`=` filter in vanilla UI, note that
and move on — the guard is exercised by code inspection.

## 10. Two players — both served (bare-return regression)

1. Host a multiplayer game (or open a second client), two **connected**
   players.
2. Give **both** players a below-min request backed by a stocked unichest
   (they must be on the surface with the container).

**Expected outcome:** **both** players are topped up in the same pass (or at
most one pass apart). A bug where only the first player is served means a bare
`return` escaped into the player loop — this test guards that regression.

## 11. Adding the mod to an EXISTING save (on_player_created regression)

1. Load a save that was played **without** this mod (ideally also without any
   personal-logistics unlock).
2. Enable unichest-logistics, reload the save, and check the character screen.

**Expected outcome:** the personal logistics **request panel is enabled** for
the already-existing player without any research or action. (This guards the
bug where only newly created players — `on_player_created` — got the unlock.)

## 12. Type-based scan: Warehousing's linked warehouse without Unichest

1. Disable Unichest; enable **Warehousing** (which provides linked
   warehouse / linked containers of type `linked-container`).
2. Repeat test 2 using a Warehousing linked container as the source.

**Expected outcome:** fulfillment works identically — the scan is type-based
(`linked-container`), not tied to Unichest prototypes.

---

## Reporting

Please include: Factorio version, mod version, mod list (esp. which
linked-container mod), and the test numbers that failed with the actual vs
expected behavior and any lines from `factorio-current.log`.

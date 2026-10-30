# Unichest Logistics

Fulfills your **personal logistic requests** directly from **linked-container
entities** (Unichest's shared chests — or any other mod's linked containers)
**before robot logistics exists**.

## What it does & design intent

Every 30 ticks the mod checks each connected player's personal logistic
requests. If you are below a request's minimum, it tops you up to the request's
maximum by taking items from linked containers on your surface.

This is an **early convenience tier** on purpose:

- It exists so personal logistics is useful before logistic robots.
- It is **deliberately replaced by robot logistics later** — no throughput
  guarantees, no construction robots, no trash handling yet.
- It is intentionally small and read-only: it never writes request slots, never
  places or removes entities, and transfers items with an insert-first /
  remove-second order so a full inventory can never destroy items.

**Balance philosophy:** one-way supply from pools *you filled by hand*. You put
items into a Unichest yourself; this mod only moves them into your inventory to
satisfy requests. It is not a mall, not a production chain, and not a
replacement for robots — it just removes the early-game tedium of manually
restocking belts, inserters, and ammo.

## Works with ANY linked-container mod

Containers are found **by entity type** (`linked-container`), not by a
hard-coded Unichest prototype. So it works with:

- **Unichest** (the original motivation),
- **Warehousing**'s linked warehouse / linked chests,
- any other mod that adds `linked-container` type entities.

A soft dependency on Unichest is declared, but it is optional (`? Unichest`) —
the mod works standalone with any linked-container mod.

## How requests work

- Requests are read from your character's requester point
  (`character.get_requester_point()`), the same slots as vanilla personal
  logistics.
- **Below-min triggers a refill up to max**: when your total (main + ammo
  inventory) drops below the request *minimum*, the mod delivers up to the
  request *maximum* (or up to the minimum if the request has no maximum).
- Only `=`-comparator item filters are fulfilled. Fluid filters and other
  comparators are ignored.
- Requests only draw from linked containers **on the player's surface**.
- The player's personal-logistics on/off switch is respected, and there is a
  per-user opt-out in *Settings → Mod settings → Per player*.
- If you are holding the requested item on your cursor (e.g. while placing it),
  that request is skipped for the tick to avoid double-delivery.
- The request UI (the requests tab) is unlocked for all forces from the start —
  no technology needed, because this mod only *reads* requests.

## Known limitations

- **Quality "any" resolves to "normal".** A request with no specific quality
  means "any quality" in the engine; this mod satisfies it with
  **normal-quality items only**. Quality-specific requests work exactly.
- **Same-surface only.** Containers must exist on the player's surface; items
  in linked containers on other surfaces are not seen (linked containers share
  their *contents* across surfaces in some setups — if the container entity
  itself is elsewhere, this mod will not find it).
- **No trash handling (v1).** Your trash slot is not emptied into containers
  yet.
- **One source per item per run.** If the first container holding an item has
  fewer items than needed, the remainder is delivered on the next 30-tick pass.
- This mod has **no runtime-tested release guarantee** — see TESTING.md and
  please report results.

## Installation

Copy the repository folder into Factorio's `mods/` directory (or zip it as
`unichest-logistics_0.1.0.zip` with the mod files at the zip root), enable it
together with any linked-container mod, and play.

## Credits

Fulfillment-loop patterns informed by "global-storage" by charlesbl
(<https://github.com/charlesbl/global-storage>) and "item-network-sa-continued"
by restjack (<https://github.com/restjack/item-network-sa-continued>).

## License

MIT — see LICENSE.

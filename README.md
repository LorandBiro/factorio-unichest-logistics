# Unichest Logistics

Fulfills your **personal logistic requests** and routes your **personal
logistics trash** directly from **Unichests** (linked containers with a single
assigned item type) **before robot logistics exists**.

> **Unichest-only as of v0.2.0.** The mod hard-depends on Unichest
> (`Unichest >= 1.0.10`). See [Why Unichest-only](#why-unichest-only) below.

## What it does & design intent

Every 30 ticks the mod checks each connected player's personal logistic
requests. If you are below a request's minimum, it tops you up to the request's
maximum by taking items from linked containers on your surface.

This is an **early convenience tier** on purpose:

- It exists so personal logistics is useful before logistic robots.
- It is **deliberately replaced by robot logistics later** — no throughput
  guarantees, no construction robots.
- It is intentionally small and read-only: it never writes request slots, never
  places or removes entities, and every transfer is lossless (supply is
  insert-into-player-first / remove-from-container-second; trash moves are
  whole-stack insert-first transfers), so a full inventory can never destroy
  items.

**Balance philosophy:** one-way supply from pools *you filled by hand*. You put
items into a Unichest yourself; this mod only moves them into your inventory to
satisfy requests. It is not a mall, not a production chain, and not a
replacement for robots — it just removes the early-game tedium of manually
restocking belts, inserters, and ammo.

## Why Unichest-only

The mod routes by **assigned item type** (`item` + `quality`), which only
Unichest makes knowable: every Unichest entity has exactly one assigned item
type, stored as inventory slot filters — that filter is the entire integration
surface (there is no remote interface).

A generic linked container can hold **mixed contents**, so there is no way to
know where a trashed item belongs. That is why the mod hard-depends on
Unichest and only ever looks at `zy-unichest` entities:

- A Unichest with **no assigned type** (empty slot filter) is skipped entirely
  — the mod never guesses a default item.
- Multiple Unichests can share one linked inventory (same `link_id`); the mod
  dedupes by `link_id` so availability is not over-counted.
- Items with **no matching Unichest** are simply not supplied — and not
  removed from trash.

## How requests work

- Requests are read from your character's requester point
  (`character.get_requester_point()`), the same slots as vanilla personal
  logistics.
- **Below-min triggers a refill up to max**: when your total (main + ammo
  inventory) drops below the request *minimum*, the mod delivers up to the
  request *maximum* (or up to the minimum if the request has no maximum).
- Only `=`-comparator item filters are fulfilled. Fluid filters and other
  comparators are ignored.
- Requests only draw from Unichests **on the player's surface**.
- The player's personal-logistics on/off switch is respected, and there is a
  per-user opt-out in *Settings → Mod settings → Per player*.
- If you are holding the requested item on your cursor (e.g. while placing it),
  that request is skipped for the tick to avoid double-delivery.
- The request UI (the requests tab) is unlocked for all forces from the start —
  no technology needed, because this mod only *reads* requests.

## How trash routing works

Every 30-tick pass, after the request loop, the mod looks at your personal
logistics **trash slots** (`character_trash`) and moves each stack into the
Unichest assigned to that exact `item|quality`:

- **If no matching Unichest exists, the item stays in the trash slot**
  (visible to you) until one appears. The mod **never destroys or re-invents
  trash**: nothing is deleted, and nothing is moved back to your main
  inventory (the engine would just re-trash it, causing endless churn).
- **Whole-stack, insert-first transfers only** (`transfer_from_stack`): item
  data (durability, ammo, custom data) is preserved; whatever does not fit
  stays in the trash slot for the next pass. No duplication, no loss.
- **Stacks with an equipped equipment grid are never touched** — an armor with
  modules in a trash slot stays exactly where it is.
- Trash routing respects the same gates as delivery: the per-user setting,
  a valid character, and the personal-logistics on/off switch.

**Caveat (outside the mod's control):** if real vanilla logistics robots are
available in your game, they will still haul trash-slot items according to
vanilla rules — this mod cannot and does not veto that.

**Deliberate gameplay intervention:** to make trash routing meaningful before
any technology, the mod gives every force **at least 10 personal logistics
trash slots** (`character_trash_slot_count`, matching the vanilla starting
default). The value persists in the save and is only ever raised to the floor,
never lowered.

## Known limitations

- **Quality "any" resolves to "normal".** A request with no specific quality
  means "any quality" in the engine; this mod satisfies it with
  **normal-quality items only**. Quality-specific requests work exactly.
- **Same-surface only.** Unichests must exist on the player's surface; items
  in Unichests on other surfaces are not seen (linked containers share their
  *contents* across surfaces in some setups — if the Unichest entity itself is
  elsewhere, this mod will not find it).
- **One source per item type per run.** If the Unichest assigned to an item has
  fewer items than needed, the remainder is delivered on the next 30-tick
  pass. If two Unichests are assigned the same `item|quality` without sharing
  a `link_id`, only the first one found is used as the routing target.
- This mod has **no runtime-tested release guarantee** — see TESTING.md and
  please report results.

## Installation

Copy the repository folder into Factorio's `mods/` directory (or zip it as
`unichest-logistics_0.2.0.zip` with the mod files at the zip root) and enable
it — Unichest (>= 1.0.10) is pulled in automatically as a hard dependency.

## Credits

Fulfillment-loop patterns informed by "global-storage" by charlesbl
(<https://github.com/charlesbl/global-storage>) and "item-network-sa-continued"
by restjack (<https://github.com/restjack/item-network-sa-continued>).

## License

MIT — see LICENSE.

-- Unichest Logistics — personal logistic request fulfillment and trash
-- routing from Unichests (single-assigned-type linked containers).
--
-- Intentionally small and READ-ONLY towards the world except for the two
-- safe transfer steps (supply: insert into player first, then remove exactly
-- what was inserted from the source Unichest; trash: whole-stack
-- transfer_from_stack into the matching Unichest, unmatched stacks stay in
-- the trash slot).
--
-- Fulfillment-loop patterns informed by "global-storage" by charlesbl and
-- "item-network-sa-continued" by restjack (see CREDITS).

local logistics = {}

-- Standard container inventory index. `entity.get_inventory(defines.inventory.chest)`
-- is the documented way to reach a container's contents; for linked-container
-- entities this returns their shared inventory. We handle nil defensively
-- (see find_source) instead of probing other inventory indices.
local CHEST_INVENTORY = defines.inventory.chest

-- Unichest is the ONLY container this mod talks to. Each Unichest has exactly
-- one assigned item type, stored as inventory slot filters (Unichest's
-- scripts/chestutil.lua reads it the same way we do below). That assigned
-- type (item + quality) is the entire routing contract — and the reason this
-- mod hard-depends on Unichest: a generic linked container can hold mixed
-- contents, so there is no way to know where a trashed item belongs.
local UNICHEST_NAME = "zy-unichest"

-- The personal logistics trash slots (the engine moves trashed items here).
local TRASH_INVENTORY = defines.inventory.character_trash

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

--- Normalize a filter's quality (request filter or Unichest slot filter) to
--- a plain string.
--- `filter.quality == nil` means "any quality" in the engine; this mod
--- resolves it to "normal" (both reference mods do the same).
--- KNOWN LIMITATION: a request for "any quality" is thus satisfied with
--- normal-quality items only.
---@param filter CompiledLogisticFilter
---@return string
local function filter_quality(filter)
  local quality = filter.quality
  if quality == nil then
    return "normal"
  end
  -- Defensive: if the engine ever hands us a quality prototype instead of a
  -- string, unwrap it.
  if type(quality) ~= "string" and quality.name then
    return quality.name
  end
  return quality
end

--- Should this compiled filter be fulfilled at all?
--- Skip entries where name is nil (empty slot), type is not nil/"item"
--- (fluid / fluid-ingredient style filters), or comparator is not nil/"="
--- (e.g. ">" minimum-delivery style comparators we do not interpret).
---@param filter CompiledLogisticFilter
---@return boolean
local function is_usable_filter(filter)
  if filter.name == nil then
    return false
  end
  if filter.type ~= nil and filter.type ~= "item" then
    return false
  end
  if filter.comparator ~= nil and filter.comparator ~= "=" then
    return false
  end
  return true
end

--- Quality-aware item count for one inventory.
--- `inventory.get_item_count(name)` IGNORES quality, so we iterate stacks and
--- compare `stack.quality.name` instead.
---@param inv LuaInventory|nil
---@param item_name string
---@param quality string
---@return integer
local function count_in_inventory(inv, item_name, quality)
  if inv == nil then
    return 0
  end
  local total = 0
  for i = 1, #inv do
    local stack = inv[i]
    if stack.valid_for_read and stack.name == item_name and stack.quality.name == quality then
      total = total + stack.count
    end
  end
  return total
end

--- Build a per-pass index of Unichests by their assigned item type.
--- Key: "item|quality" (the same keying Unichest uses for link IDs).
--- Value: { entity, inventory } — the FIRST Unichest claiming that type wins.
---
--- Rules (all deliberate):
--- - A nil slot filter means "no assigned type": the Unichest is skipped
---   entirely. We do NOT guess a default item (Unichest's own getItemFilter
---   fallback does that with a warning — wrong fit for routing).
--- - Multiple Unichests can share one linked inventory (same `link_id`);
---   dedupe by `link_id` (first wins) so availability is not over-counted.
---@param surface LuaSurface
---@return table<string, { entity: LuaEntity, inventory: LuaInventory }>
local function build_container_index(surface)
  local index = {}
  local seen_links = {}

  for _, entity in pairs(surface.find_entities_filtered { name = UNICHEST_NAME }) do
    local link_id = entity.link_id
    if link_id == nil or not seen_links[link_id] then
      -- Unichest's integration surface: the assigned type lives in slot
      -- filter 1 of the output inventory (type "with_filters_and_bar").
      local inv = entity.get_output_inventory() or entity.get_inventory(CHEST_INVENTORY)
      if inv ~= nil then
        local slot_filter = inv.get_filter(1)
        if slot_filter ~= nil and slot_filter.name ~= nil then
          -- Claim the link only once the entity actually contributes a type,
          -- so a filter-less sibling never hides a filtered one sharing the
          -- same link_id.
          if link_id ~= nil then
            seen_links[link_id] = true
          end
          local key = slot_filter.name .. "|" .. filter_quality(slot_filter)
          if index[key] == nil then
            index[key] = { entity = entity, inventory = inv }
          end
        end
      end
    end
  end

  return index
end

--- Look up the Unichest assigned to exactly `item_name` + `quality` and count
--- what its shared inventory can currently offer. Pure index lookup — no
--- entity loop, no content-scanning heuristic. Availability is recomputed per
--- call, so a source that runs dry mid-run is re-counted naturally.
---@param index table "item|quality" -> { entity, inventory }
---@param item_name string
---@param quality string
---@return { inventory: LuaInventory|nil, available: integer }
local function find_source(index, item_name, quality)
  local target = index[item_name .. "|" .. quality]
  if target == nil then
    return { inventory = nil, available = 0 }
  end
  return {
    inventory = target.inventory,
    available = count_in_inventory(target.inventory, item_name, quality),
  }
end

--- Transfer up to `wanted` items from the source inventory into the player.
--- SAFETY ORDER: insert into the player FIRST (ammo inventory first if it can
--- take the stack, then the main inventory), and only then remove EXACTLY the
--- inserted count from the source container. A full player inventory can
--- therefore never destroy items.
---@param source LuaInventory
---@param item_name string
---@param quality string
---@param wanted integer
---@param ammo_inv LuaInventory|nil
---@param main_inv LuaInventory|nil
---@return integer inserted
local function transfer_to_player(source, item_name, quality, wanted, ammo_inv, main_inv)
  local inserted = 0

  if ammo_inv ~= nil and ammo_inv.can_insert({ name = item_name, quality = quality, count = wanted }) then
    inserted = ammo_inv.insert({ name = item_name, quality = quality, count = wanted })
  end

  if inserted < wanted and main_inv ~= nil then
    local remainder = wanted - inserted
    if main_inv.can_insert({ name = item_name, quality = quality, count = remainder }) then
      inserted = inserted + main_inv.insert({ name = item_name, quality = quality, count = remainder })
    end
  end

  if inserted > 0 then
    source.remove({ name = item_name, quality = quality, count = inserted })
  end

  return inserted
end

----------------------------------------------------------------------------
-- Trash routing
----------------------------------------------------------------------------

--- Route the player's personal-logistics trash into matching Unichests.
--- One call per player per pass, after the request loop.
---
--- Rules (all safety-critical):
--- - NEVER touch stacks that carry an equipped equipment grid (armor with
---   modules etc.) — the guard mirrors item-network-sa-continued's
---   trash_to_network (NetworkChest.lua ~lines 404-417).
--- - Whole-stack moves only, via `transfer_from_stack`: insert-first and
---   lossless (whatever does not fit stays in the trash stack).
--- - No matching Unichest -> the stack STAYS in the trash slot, visible to
---   the player. Never remove it, never move it back to the main inventory
---   (the engine would re-trash it, causing endless churn). The mod never
---   destroys or re-invents trash.
---@param player LuaPlayer
---@param container_index table
local function route_trash(player, container_index)
  local trash_inv = player.get_inventory(TRASH_INVENTORY)
  if trash_inv == nil then
    return
  end

  for i = 1, #trash_inv do
    local stack = trash_inv[i]
    if stack.valid_for_read then
      local equipped = stack.item_number ~= nil and stack.grid ~= nil and #stack.grid.equipment > 0
      if not equipped then
        local target = container_index[stack.name .. "|" .. stack.quality.name]
        if target ~= nil then
          -- Insert-first whole-stack transfer: preserves item data (durability,
          -- ammo, custom data), no dupes, no loss. Partial fit leaves the
          -- remainder in the trash slot for the next pass.
          target.inventory.transfer_from_stack(stack)
        end
        -- No target: leave the stack in the trash slot (see rules above).
      end
    end
  end
end

----------------------------------------------------------------------------
-- Per-player fulfillment
----------------------------------------------------------------------------

--- Process one player's personal logistic requests. Early-outs at the first
--- cheap failure (setting -> character -> requester point -> point.enabled).
--- All returns here are function-local, so a broken player can never abort
--- the run for the remaining players (the bare-`return`-in-player-loop bug).
---@param player LuaPlayer
local function process_player(player)
  -- Cheapest check first: per-user opt-out.
  if not settings.get_player_settings(player.index)["unichest-logistics-enabled"].value then
    return
  end

  local character = player.character
  if character == nil or not character.valid then
    return
  end

  local point = character.get_requester_point()
  if point == nil then
    return
  end

  -- The player's personal-logistics on/off switch.
  if not point.enabled then
    return
  end

  local main_inv = player.get_main_inventory()
  local ammo_inv = player.get_inventory(defines.inventory.character_ammo)
  if main_inv == nil then
    return
  end

  -- Cursor guard: if the player is holding the requested item on the cursor
  -- (e.g. while placing it), delivering more this tick can double-deliver
  -- relative to what the player sees. Checked per request below.

  -- Unichest index is built once per player run (fine at a 30-tick cadence).
  -- Unichest-ONLY contract: routing keys off each Unichest's assigned item
  -- type ("item|quality" slot filter). Generic linked containers are not
  -- scanned — mixed contents give no routing target.
  local container_index = build_container_index(player.surface)

  for _, filter in pairs(point.filters) do
    if not is_usable_filter(filter) then
      goto continue
    end

    local quality = filter_quality(filter)

    -- Cursor guard: skip this request entirely while the player holds the
    -- very same item + quality on the cursor.
    local cursor = player.cursor_stack
    if cursor and cursor.valid_for_read and cursor.name == filter.name
        and cursor.quality.name == quality then
      goto continue
    end

    -- Quality-aware "have": main inventory + ammo inventory.
    local have = count_in_inventory(main_inv, filter.name, quality)
        + count_in_inventory(ammo_inv, filter.name, quality)

    -- Below the request MIN -> refill up to MAX (or up to MIN when the
    -- request has no max). Already at/above target -> nothing to do.
    if have >= filter.count then
      goto continue
    end
    local target = filter.max_count or filter.count
    if have >= target then
      goto continue
    end

    local source = find_source(container_index, filter.name, quality)
    if source.inventory == nil or source.available <= 0 then
      goto continue
    end

    local wanted = math.min(target - have, source.available)
    if wanted > 0 then
      local inserted = transfer_to_player(source.inventory, filter.name, quality, wanted, ammo_inv, main_inv)
      source.available = source.available - inserted
    end

    ::continue::
  end

  -- Trash routing: once per player per pass. Placed after the request loop on
  -- purpose, so the setting / character / point.enabled early-outs above
  -- still gate it (a player with personal logistics off gets no trash routing
  -- either).
  route_trash(player, container_index)
end

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

--- Process every connected player. Per-player failures are isolated by the
--- process_player function boundary; never use bare `return` here.
function logistics.process()
  for _, player in pairs(game.players) do
    if player.connected then
      process_player(player)
    end
  end
end

return logistics

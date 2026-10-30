-- Unichest Logistics — personal logistic request fulfillment from linked
-- containers.
--
-- Intentionally small and READ-ONLY towards the world except for the single
-- safe transfer step (insert into player first, then remove exactly what was
-- inserted from the source container).
--
-- Fulfillment-loop patterns informed by "global-storage" by charlesbl and
-- "item-network-sa-continued" by restjack (see CREDITS).

local logistics = {}

-- Standard container inventory index. `entity.get_inventory(defines.inventory.chest)`
-- is the documented way to reach a container's contents; for linked-container
-- entities this returns their shared inventory. We handle nil defensively
-- (see find_source) instead of probing other inventory indices.
local CHEST_INVENTORY = defines.inventory.chest

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

--- Normalize a request's quality to a plain string.
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

--- Locate `item_name` (of exactly `quality`) in the linked containers.
--- Result is memoized in `cache` under "item|quality" so each item is only
--- located once per player run: { inventory, available }.
--- First container holding the item wins; if it runs dry mid-run the rest is
--- picked up on the next 30-tick pass.
---@param containers table Array of LuaEntity (linked-container)
---@param item_name string
---@param quality string
---@param cache table
---@return { inventory: LuaInventory|nil, available: integer }
local function find_source(containers, item_name, quality, cache)
  local key = item_name .. "|" .. quality
  local memo = cache[key]
  if memo ~= nil then
    return memo
  end

  for _, entity in pairs(containers) do
    if entity.valid then
      local inv = entity.get_inventory(CHEST_INVENTORY)
      if inv ~= nil then
        local available = count_in_inventory(inv, item_name, quality)
        if available > 0 then
          memo = { inventory = inv, available = available }
          cache[key] = memo
          return memo
        end
      end
    end
  end

  memo = { inventory = nil, available = 0 }
  cache[key] = memo
  return memo
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

  -- Container list is built once per player run (fine at a 30-tick cadence).
  -- Type-based on purpose: works with Unichest AND any other linked-chest mod
  -- (e.g. Warehousing's linked warehouse).
  local containers = player.surface.find_entities_filtered { type = "linked-container" }

  -- Memoized location results: "item|quality" -> { inventory, available }.
  local source_cache = {}

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

    local source = find_source(containers, filter.name, quality, source_cache)
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

  -- TODO (v2, deliberately NOT in v1): trash handling.
  -- Intended future behavior: move the player's trash stacks
  -- (player.get_inventory(defines.inventory.character_trash)) into linked
  -- containers whose filter matches the trash stack — but ONLY after an
  -- equipment-grid guard: skip (and report) stacks that carry equipment,
  -- i.e. `stack.item_number ~= nil and stack.grid ~= nil and #stack.grid.equipment > 0`,
  -- exactly as item-network-sa-continued does in NetworkChest.lua
  -- trash_to_network (~lines 411-418). Trash must never swallow
  -- partially-equipped items.
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

local logistics = require("logistics")

--- Unlock the personal-logistics request UI (requests tab in the character
--- screen) for every force.
---
--- We only READ personal requests from control stage; writing request slots
--- is what silently fails without this flag. The flag is per-FORCE, and
--- on_player_created does not fire for players that already exist when the
--- mod is added mid-game, so this must run from on_init,
--- on_configuration_changed AND on_player_created.
local function unlock_personal_logistics_ui()
  for _, force in pairs(game.forces) do
    force.character_logistic_requests = true
  end
end

script.on_init(unlock_personal_logistics_ui)

script.on_configuration_changed(function(_event)
  unlock_personal_logistics_ui()
end)

script.on_player_created(function(_event)
  unlock_personal_logistics_ui()
end)

-- Fulfillment cadence: every 30 ticks (~0.5 s at 60 UPS). Cheap enough to
-- keep per-player work off the per-tick path entirely.
script.on_nth_tick(30, function(_event)
  logistics.process()
end)

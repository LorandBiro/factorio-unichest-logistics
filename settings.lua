-- Runtime-per-user toggle for Unichest Logistics delivery.
--
-- Note: setting prototypes do not carry a `description` field in the data
-- stage; the human-readable description shown in the settings UI lives in
-- locale/en.cfg under [mod-setting-description] (added in this mod for that
-- purpose).
data:extend({
  {
    type = "bool-setting",
    name = "unichest-logistics-enabled",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "a",
  },
})

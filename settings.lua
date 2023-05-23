local highlight_color = {
    type = "color-setting",
    name = "highlight_color",
    default_value = {1,1,1,1},
    setting_type = "runtime-per-user"
}

local highlights_per_tick = {
    type = "int-setting",
    name = "highlights_per_tick",
    default_value = 5,
    minimum_value = 1,
    setting_type = "runtime-per-user"
}

data:extend({
    highlight_color,
    highlights_per_tick
})
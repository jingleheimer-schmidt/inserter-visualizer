local toggle_inserter_visualizer = {
    type = "custom-input",
    name = "toggle-global-inserter-visualizer",
    key_sequence = "I",
    -- key_sequence = "SHIFT + I",
    -- alternative_key_sequence = "I",
    action = "lua",
}
data:extend({toggle_inserter_visualizer})

local toggle_inserter_visualizer_selection_shortcut = {
    type = "shortcut",
    name = "toggle-selection-highlighting-shortcut",
    action = "lua",
    associated_control_input = "toggle-selection-highlighting-shortcut",
    icon = {filename = "__inserter-visualizer__/icon_solid.png", size = 100},
    disabled_icon = {filename = "__inserter-visualizer__/icon_outlined.png", size = 100},
    toggleable = true,
}
data:extend({toggle_inserter_visualizer_selection_shortcut})

local toggle_inserter_visualizer_selection = {
    type = "custom-input",
    name = "toggle-selection-highlighting-shortcut",
    key_sequence = "CONTROL + I",
    alternative_key_sequence = "COMMAND + I",
    action = "lua",
}
data:extend({toggle_inserter_visualizer_selection})
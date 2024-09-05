
local table = require("__flib__.table")
local floor = math.floor
local ceil = math.ceil
local belt_types = {
    ["transport-belt"] = true,
    ["underground-belt"] = true,
    ["splitter"] = true
}
local dirs = {
    south = 0,
    south_west = 0.125,
    west = 0.25,
    north_west = 0.375,
    north = 0.5,
    north_east = 0.625,
    east = 0.75,
    south_east = 0.875,
}
local opposite_type = {
    inputs = "outputs",
    outputs = "inputs",
}

-- A player's unique index in LuaGameScript::players. It is given to them when they are created and remains assigned to them until they are removed.
---@alias PlayerIndex uint

-- The unique name of a surface
---@alias SurfaceName string

-- thank you _codegreen for concocting this magic function
---@param inserter LuaEntity
---@param drop_target LuaEntity
---@return boolean
local function flip_adjustment(inserter, drop_target)
    -- local entity = inserter.drop_target
    -- if not entity then return false end
    -- if not belt_types[entity.type] then return false end
    local belt_direction = drop_target.direction
    local inputs = drop_target.belt_neighbours.inputs
    local offset = 0
    if #inputs == 1 and belt_direction ~= inputs[1].direction then
        offset = (belt_direction - inputs[1].direction) % 8 == 2 and 2 or 4
    end
    return belt_direction == (inserter.direction + offset) % 8
end

---do a little math and then make the calls to LuaRendering to draw the drop position for the given inserter
---@param inserter LuaEntity
---@param player_index PlayerIndex
---@param color Color
local function draw_drop_position(inserter, player_index, color)
    if not inserter or not inserter.valid then return end
    local adjusted_position = inserter.drop_position
    local drop_target = inserter.drop_target
    local orientation = inserter.orientation
    local drop_target_offset = 1 / 5
    if game.active_mods["diagonal-inserter"] then
        drop_target_offset = 0
    end
    -- if there's no drop target, search the pickup location for a possible drop_target that the inserter doesn't know about yet. this would happen if an inserter goes to sleep before the drop target exists; the inserter won't know about the drop target until it wakes up. not a perfect solution, but should be good enough since this is a rather rare case to begin with.
    if not drop_target then
        drop_target = inserter.surface.find_entities_filtered({
            type = { "transport-belt", "undergrount-belt", "splitter" },
            position = adjusted_position,
            limit = 1
        })[1]
    end
    if orientation and drop_target and drop_target.type and belt_types[drop_target.type] then
        if orientation >= dirs["north_west"] and orientation < dirs["north_east"] then
            -- if orientation == 0.5 then -- placing north
            if flip_adjustment(inserter, drop_target) then
                adjusted_position.x = adjusted_position.x - drop_target_offset
            else
                adjusted_position.x = adjusted_position.x + drop_target_offset
            end
        elseif orientation >= dirs["north_east"] and orientation < dirs["south_east"] then
            -- elseif orientation == 0.75 then -- placing east
            if flip_adjustment(inserter, drop_target) then
                adjusted_position.y = adjusted_position.y - drop_target_offset
            else
                adjusted_position.y = adjusted_position.y + drop_target_offset
            end
        elseif orientation >= dirs["south_east"] or orientation < dirs["south_west"] then
            -- elseif orientation == 0 then -- placing south
            if flip_adjustment(inserter, drop_target) then
                adjusted_position.x = adjusted_position.x + drop_target_offset
            else
                adjusted_position.x = adjusted_position.x - drop_target_offset
            end
        elseif orientation >= dirs["south_west"] and orientation < dirs["north_west"] then
            -- elseif orientation == 0.25 then -- placing west
            if flip_adjustment(inserter, drop_target) then
                adjusted_position.y = adjusted_position.y + drop_target_offset
            else
                adjusted_position.y = adjusted_position.y - drop_target_offset
            end
        end
    end
    local surface = inserter.surface
    local circle_target_offset = {
        x = adjusted_position.x - inserter.position.x,
        y = adjusted_position.y - inserter.position.y,
    }
    local render_circle = rendering.draw_circle(
        {
            color = color,
            radius = 0.1,
            filled = true,
            target = inserter,
            target_offset = circle_target_offset,
            surface = surface,
            players = { player_index },
        }
    )
    local render_line = rendering.draw_line(
        {
            color = color,
            width = 3, -- 32px per tile
            gap_length = 0,
            dash_length = 0,
            from = inserter,
            to = adjusted_position,
            surface = surface,
            players = { player_index },
        }
    )
    if not global.renderings then
        global.renderings = {
            [player_index] = {
                player = player,
                render_ids = {}
            }
        }
    elseif not global.renderings[player_index] then
        global.renderings[player_index] = {
            player = player,
            render_ids = {}
        }
    end
    table.insert(global.renderings[player_index].render_ids, render_circle)
    table.insert(global.renderings[player_index].render_ids, render_line)
end

--- get every xy position within a given BoundingBox
---@param bounding_box BoundingBox
---@return table<integer, MapPosition>
local function get_positions_in_bounding_box(bounding_box)
    local positions = {}
    for x = floor(bounding_box.left_top.x), floor(bounding_box.right_bottom.x) do
        for y = floor(bounding_box.left_top.y), floor(bounding_box.right_bottom.y) do
            table.insert(positions, { x = x, y = y })
        end
    end
    return positions
end

--- draw any inserter drop_target highlights for given x and y coordinates
---@param x integer the x coordinate of a position
---@param y integer the y coordinate of a position
---@param surface_name SurfaceName
---@param player_index PlayerIndex
---@param color Color
local function draw_drop_positions_by_xy(x, y, surface_name, player_index, color)
    if not (global.drop_target_positions and global.drop_target_positions[surface_name]) then return end
    local positions_on_surface = global.drop_target_positions[surface_name]
    if not (positions_on_surface[x] and positions_on_surface[x][y]) then return end
    for _, inserter in pairs(positions_on_surface[x][y]) do
        if (inserter.valid and (floor(inserter.drop_position.x) == x) and (floor(inserter.drop_position.y) == y)) then
            -- if not inserter.valid then break end
            -- local drop_position = inserter.drop_position
            -- if not ((floor(drop_position.x) == x) and (floor(drop_position.y) == y)) then break end
            draw_drop_position(inserter, player_index, color)
        end
    end
end

--- TraceData is a table containing a LuaEntity of a transport-belt, underground-belt, or splitter, and a string indicating if the LuaEntity was traced from the "inputs" or "outputs" of the previous belt
---@class TraceData
---@field entity LuaEntity
---@field from_type string?

--- draw any inserter drop_target highlights for a given belt, and add any belt_neighbours to the trace queue
---@param data TraceData
---@param player_index PlayerIndex
---@param color Color
local function trace_belts(data, player_index, color)
    local entity = data.entity
    local from_type = data.from_type
    if not (entity and entity.valid) then return end
    local position = entity.position
    local x = floor(position.x)
    local y = floor(position.y)
    local surface_name = entity.surface.name
    local type = entity.type
    local unit_number = entity.unit_number --[[@as uint]]
    local belt_neighbours = entity.belt_neighbours
    local orientation = entity.orientation
    local global_data = global

    -- draw any inserter drop positions
    if type == "splitter" then
        local splitter_positions = get_positions_in_bounding_box(entity.bounding_box)
        for _, splitter_position in pairs(splitter_positions) do
            draw_drop_positions_by_xy(splitter_position.x, splitter_position.y, surface_name, player_index, color)
        end
    elseif type == "transport-belt" or type == "underground-belt" then
        draw_drop_positions_by_xy(x, y, surface_name, player_index, color)
    end

    -- document that we already traced this belt
    if not global_data.traced_belts then global_data.traced_belts = {} end
    if not global_data.traced_belts[player_index] then global_data.traced_belts[player_index] = {} end
    ---@type table<uint, boolean>
    local traced_belts = global_data.traced_belts[player_index]
    if not traced_belts[unit_number] then traced_belts[unit_number] = true end

    -- add any connected belts to the queue
    local unique_untraced = {}
    for neighbor_type, neighbours in pairs(belt_neighbours) do
        for _, neighbour in pairs(neighbours) do
            -- if not (neighbor_type == from_type) and not (traced_belts and traced_belts[neighbour.unit_number]) then
            -- if not (traced_belts and traced_belts[neighbour.unit_number]) then
            local same_io_type = neighbor_type == from_type
            local is_splitter = type == "splitter"
            local same_orientation = orientation == neighbour.orientation
            local already_traced = traced_belts and traced_belts[neighbour.unit_number]
            if (not same_io_type or (not is_splitter and same_orientation)) and not already_traced then
                unique_untraced[neighbour.unit_number] = { entity = neighbour, type = neighbor_type }
            end
        end
    end
    for _, neighbour_data in pairs(unique_untraced) do
        local trace_data = {
            entity = neighbour_data.entity,
            from_type = opposite_type[neighbour_data.type]
        }
        table.insert(global_data.trace_queue[player_index], trace_data)
    end

    -- add the other side of an underground to the queue
    if type == "underground-belt" and entity.neighbours then
        if traced_belts and traced_belts[entity.neighbours.unit_number] then return end
        table.insert(global_data.trace_queue[player_index], { entity = entity.neighbours })
    end
end

-- clear any renderings for the player
---@param player_index PlayerIndex
---@param global_data table?
local function clear_renderings_for_player(player_index, global_data)
    global_data = global_data or global
    ---@type table<PlayerIndex, boolean>
    if not global_data.destroy_renderings then global_data.destroy_renderings = {} end
    if global_data.renderings and global_data.renderings[player_index] then
        global_data.destroy_renderings[player_index] = true
    end
end

-- clear any queued belts from the tracer
---@param player_index PlayerIndex
---@param global_data table?
local function clear_queue_for_player(player_index, global_data)
    global_data = global_data or global
    if global_data.trace_queue and global_data.trace_queue[player_index] then
        global_data.trace_queue[player_index] = nil
    end
    if global_data.traced_belts and global_data.traced_belts[player_index] then
        global_data.traced_belts[player_index] = nil
    end
end

local function selected_entity_changed(event)
    local player_index = event.player_index
    local global_data = global
    if global_data.highlight_inserters and global_data.highlight_inserters[player_index] then return end
    local player = game.get_player(player_index)
    if not player then return end
    local entity = player.selected

    -- clear any renderings for the player
    ::destroy_renderings::
    if not (global_data.renderings and global_data.renderings[player_index]) then goto trace_queue end
    clear_renderings_for_player(player_index, global_data)

    -- clear any queued belts from the tracer
    ::trace_queue::
    clear_queue_for_player(player_index, global_data)
    if not (global_data.selection_highlighting and global_data.selection_highlighting[player_index]) then return end

    -- draw highlight if entity is an inserter, or add it to the trace queue if it's a belt
    ::highlight_entities::
    if global_data.single_inserter_queue and global_data.single_inserter_queue[player_index] then
        global_data.single_inserter_queue[player_index] = nil
    end
    if not (entity and entity.type) then return end
    local type = entity.type
    if not global_data.trace_queue then global_data.trace_queue = {} end
    if not global_data.trace_queue[player_index] then global_data.trace_queue[player_index] = {} end
    if type == "inserter" then
        -- draw_drop_position(entity, player_index, color)
        if not global_data.single_inserter_queue then
            global_data.single_inserter_queue = {
                [player_index] = entity
            }
        else
            global_data.single_inserter_queue[player_index] = entity
        end
    elseif belt_types[type] then
        table.insert(global_data.trace_queue[player_index], { entity = entity })
    end
end

---update the global list of drop target positions and global list of all inserters when a new one is built
---@param event EventData.on_robot_built_entity | EventData.on_built_entity | EventData.script_raised_built | EventData.on_player_rotated_entity | EventData.on_entity_settings_pasted
local function entity_built(event)
    local entity = event.entity or event.created_entity or event.destination
    if entity and entity.type == "inserter" then

        -- add the inserter to the global list indexed by xy coordinates
        ---@type table<SurfaceName, table< integer, table< integer, table< integer, LuaEntity> > > >
        if not global.drop_target_positions then global.drop_target_positions = {} end
        local drop_target_positions = global.drop_target_positions
        local surface_name = entity.surface.name
        local x = floor(entity.drop_position.x)
        local y = floor(entity.drop_position.y)
        if not drop_target_positions[surface_name] then drop_target_positions[surface_name] = {} end
        local positions_on_surface = drop_target_positions[surface_name]
        if not positions_on_surface[x] then positions_on_surface[x] = {} end
        local x_axis = positions_on_surface[x]
        if not x_axis[y] then x_axis[y] = {} end
        local drop_target_position = x_axis[y]
        table.insert(drop_target_position, entity)

        -- add the inserter to the global list sorted by unit_number
        if not global.all_inserters then global.all_inserters = {} end
        table.insert(global.all_inserters, 1, entity)
    end
end

--- update global list of drop positions when an inserter is rotated
---@param event EventData.on_player_rotated_entity
local function entity_rotated(event)
    entity_built(event)
end

---update global list of drop positions when an inserter settings are pasted
---@param event EventData.on_entity_settings_pasted
local function entity_settings_pasted(event)
    local active_mods = game.active_mods
    if active_mods["bobinserters"] or active_mods["Inserter_Config"] then
        entity_built(event)
    end
end

-- reset the global tables of inserters and drop locations
local function update_drop_locations()
    global.all_inserters = {}
    for _, surface in pairs(game.surfaces) do
        local found_inserters = surface.find_entities_filtered({ type = "inserter" })
        for _, inserter in pairs(found_inserters) do
            if inserter and inserter.valid then
                local event = {
                    entity = inserter
                }
                entity_built(event)
            end
        end
    end
    -- for table.sort, return true to sort a before b, or return false to sort b before a
    table.sort(global.all_inserters, function(a, b) return a.unit_number > b.unit_number end)
    -- table.sort(global.all_inserters, function(a,b) return a.unit_number < b.unit_number end)
end

--- turn the belt tracer on or off
---@param event EventData.CustomInputEvent
local function toggle_traced_belt_visualizer(event)
    local player_index = event.player_index
    local player = game.get_player(player_index)
    if not player then return end
    clear_renderings_for_player(player_index, global)
    clear_queue_for_player(player_index, global)
    global.from_key_inserter = nil
    global.from_key_render = nil

    ---@type table<PlayerIndex, boolean>
    global.highlight_inserters = global.highlight_inserters or {}
    local selected = player.selected
    if selected and selected.type and belt_types[selected.type] then
        global.trace_queue = global.trace_queue or {}
        global.trace_queue[player_index] = global.trace_queue[player_index] or {}
        table.insert(global.trace_queue[player_index], { entity = player.selected })
        global.highlight_inserters[player_index] = true -- so when you toggle while selecting a belt type entity, the highlight is persistent once you select something else
    else
        global.highlight_inserters[player_index] = false
        if not global.inserter_queue then return end
        global.inserter_queue[player_index] = nil
    end
end

--- turn the visualizer on or off for the selected inserter, belt, or all inserters if cursor is empty
---@param event EventData.CustomInputEvent
local function toggle_global_inserter_visualizer(event)
    local player_index = event.player_index
    local player = game.get_player(player_index)
    if not player then return end
    local selected_entity = player.selected
    global.highlight_inserters = global.highlight_inserters or {} ---@type table<PlayerIndex, boolean>
    global.inserter_queue = global.inserter_queue or {} ---@type table<PlayerIndex, boolean>
    global.single_inserter_queue = global.single_inserter_queue or {} ---@type table<PlayerIndex, LuaEntity>
    -- clear the single_inserter_queue of any previously highlighted inserters
    global.single_inserter_queue[player_index] = nil
    -- if player selected a belt, start up the belt tracer
    if player and selected_entity and belt_types[selected_entity.type] then
        toggle_traced_belt_visualizer({ player_index = player_index })
        -- otherwise add the selected inserter to the single_inserter_queue
    elseif player and selected_entity and selected_entity.type == "inserter" then
        global.single_inserter_queue[player_index] = selected_entity
        global.highlight_inserters[player_index] = true -- so when you toggle while selecting an inserter, the highlight is persistent once you select something else
        -- or if something else / nothing is selected, toggle highlighting all inserters
    else
        if not global.highlight_inserters[player_index] then
            global.highlight_inserters[player_index] = true
            global.inserter_queue[player_index] = true
        else
            global.highlight_inserters[player_index] = false
            global.inserter_queue[player_index] = nil
        end
        clear_renderings_for_player(player_index, global)
        clear_queue_for_player(player_index, global)
        global.from_key_inserter = nil
        global.from_key_render = nil
    end
end

--- turn selection highlighting on or off
---@param event EventData.on_lua_shortcut | EventData.CustomInputEvent
local function toggle_selection_highlighting(event)
    local name = event.prototype_name or event.input_name
    if name ~= "toggle-selection-highlighting-shortcut" then return end
    local player_index = event.player_index
    if not global.selection_highlighting then global.selection_highlighting = {} end
    global.selection_highlighting[player_index] = not global.selection_highlighting[player_index]
    game.get_player(player_index).set_shortcut_toggled("toggle-selection-highlighting-shortcut", global.selection_highlighting[player_index])
end

-- ensure that if a surface is renamed, all our functions can still access the data they need
---@param event EventData.on_surface_renamed
local function surface_renamed(event)
    local old_name, new_name = event.old_name, event.new_name
    if global.drop_target_positions and global.drop_target_positions[old_name] then
        global.drop_target_positions[new_name] = global.drop_target_positions[old_name]
    end
end

-- a "factory function" so that the player_index upval can be passed through during for_n_of.
-- the `callback` in for_n_of receives two inputs, the value and key of the table that is being processed,
-- so if we call this factory function `factory(uppval_to_pass)` it will return the inner function + the captured upvals,
-- which will be used as the `callback` in for_n_of.
-- Thank you so much justarandomgeek and jansharp for explaining what this is and how it works :)
---@param player_index PlayerIndex
---@param color Color
---@return function
local function draw_drop_positions_partial(player_index, color)
    ---@param inserter LuaEntity
    ---@return nil?
    ---@return boolean?
    return function(inserter)
        if inserter.valid then
            draw_drop_position(inserter, player_index, color)
        else
            return nil, true -- return the "deletion flag" to tell `for_n_of()` to remove it from global.all_inserters
        end
    end
end

---destroy the `render_id` and return the "deletion flag" to tell `for_n_of()` to remove it from `global.renderings[player_index]`
---@param render_id uint64
-- -@return nil
-- -@return boolean
local function destroy_renderings_partial(render_id)
    -- rendering.destroy(render_id)
    -- return nil, true
    rendering.destroy(render_id)
end

---update the highlighting progress indicator
---@param player_index PlayerIndex
---@param pre_text string
---@param global_data table
---@param iterations number
---@param big_table table
---@param reset_count boolean
---@param continued_count number?
local function update_highlight_message(player_index, pre_text, global_data, iterations, big_table, reset_count, continued_count)
    if not (global_data.message[player_index] and global_data.message[player_index].render_id) then
        local percent = ceil(iterations / table_size(big_table) * 100)
        local player = game.get_player(player_index)
        if not player then return end
        global_data.message[player_index] = {
            render_id = rendering.draw_text {
                text = pre_text .. ": " .. percent .. "%",
                target = player.character or player.position,
                surface = player.surface,
                color = { 1, 1, 1, 1 },
                alignment = "center"
            },
            count = continued_count or iterations
        }
    else
        local message_data = global_data.message[player_index]
        if reset_count then message_data.count = 0 end
        message_data.count = message_data.count + iterations
        local percent = ceil(message_data.count / table_size(big_table) * 100)
        if rendering.is_valid(message_data.render_id) then
            rendering.set_text(message_data.render_id, pre_text .. ": " .. percent .. "%")
        else
            global_data.message[player_index].render_id = nil
            update_highlight_message(player_index, pre_text, global_data, iterations, big_table, reset_count,
                message_data.count)
        end
    end
end

-- the core, the main mod loop, this is where it all happens :)
local function on_tick()
    local global_data = global
    local belt_queue = global_data.trace_queue ---@type table<PlayerIndex, table<integer, TraceData>>
    local inserter_queue = global_data.inserter_queue ---@type table<PlayerIndex, boolean>
    local destroy_renderings = global_data.destroy_renderings ---@type table<PlayerIndex, boolean>
    local single_inserter_queue = global_data.single_inserter_queue ---@type table<PlayerIndex, LuaEntity>
    if not global_data.from_key_inserter then global_data.from_key_inserter = {} end
    if not global_data.from_key_render then global_data.from_key_render = {} end
    if not global_data.message then global_data.message = {} end
    ::single_inserter::
    if not single_inserter_queue or not next(single_inserter_queue) then goto belt_queue end
    for player_index, inserter in pairs(single_inserter_queue) do
        if global_data.destroy_renderings and global_data.destroy_renderings[player_index] then break end
        local highlight_color = settings.get_player_settings(player_index)["highlight_color"].value --[[@as Color]]
        draw_drop_position(inserter, player_index, highlight_color)
    end
    ::belt_queue::
    if not belt_queue or not next(belt_queue) then goto inserter_queue end
    for player_index, belts in pairs(belt_queue) do
        if global_data.destroy_renderings and global_data.destroy_renderings[player_index] then break end
        local player_settings = settings.get_player_settings(player_index)
        local max_belts_traced_per_tick = player_settings["highlights_per_tick"].value
        local highlight_color = player_settings["highlight_color"].value --[[@as Color]]
        local counter = 0
        for id, belt_data in pairs(belts) do
            if counter > max_belts_traced_per_tick then break end
            trace_belts(belt_data, player_index, highlight_color)
            belts[id] = nil
            counter = counter + 1
        end
        if not next(belts) then
            belt_queue[player_index] = nil
        end
    end
    ::inserter_queue::
    if not inserter_queue then goto render_destruction end
    for player_index, bool in pairs(inserter_queue) do
        if not bool then break end
        -- don't start rendering until all the current ones are destroyed
        if global_data.destroy_renderings and global_data.destroy_renderings[player_index] then break end
        local player_settings = settings.get_player_settings(player_index)
        local max_inserters_iterated_per_tick = player_settings["highlights_per_tick"].value --[[@as number]]
        local highlight_color = player_settings["highlight_color"].value --[[@as Color]]
        local results, reached_end = nil, nil
        local reset_count = false
        if not global_data.from_key_inserter[player_index] then reset_count = true end
        global_data.from_key_inserter[player_index], results, reached_end = table.for_n_of(
            global_data.all_inserters,
            global_data.from_key_inserter[player_index],
            max_inserters_iterated_per_tick,
            draw_drop_positions_partial(player_index, highlight_color)
        )
        update_highlight_message(player_index, "Highlighting Inserters", global_data, max_inserters_iterated_per_tick, global_data.all_inserters, reset_count)
        if reached_end then
            inserter_queue[player_index] = false
            global_data.from_key_inserter[player_index] = nil
            rendering.destroy(global_data.message[player_index].render_id)
            global_data.message[player_index] = nil
        end
    end
    ::render_destruction::
    if not destroy_renderings then return end
    for player_index, bool in pairs(destroy_renderings) do
        if not bool then break end
        -- destroy every rendering for a given player_index
        local player_settings = settings.get_player_settings(player_index)
        local max_renderings_destroyed_per_tick = player_settings["highlights_per_tick"].value * 10 * 5
        local results, reached_end = nil, nil
        local reset_count = false
        if not global_data.from_key_render[player_index] then reset_count = true end
        global_data.from_key_render[player_index], results, reached_end = table.for_n_of(
            global_data.renderings[player_index].render_ids,
            global_data.from_key_render[player_index],
            max_renderings_destroyed_per_tick,
            destroy_renderings_partial
        )
        update_highlight_message(player_index, "Removing Highlights", global_data, max_renderings_destroyed_per_tick, global_data.renderings[player_index].render_ids, reset_count)
        if reached_end then
            global_data.renderings[player_index].render_ids = {}
            destroy_renderings[player_index] = false
            global_data.from_key_render[player_index] = nil
            rendering.destroy(global_data.message[player_index].render_id)
            global_data.message[player_index] = nil
        end
    end
end

script.on_init(update_drop_locations)
script.on_configuration_changed(update_drop_locations)
script.on_event(defines.events.on_tick, on_tick)
script.on_event(defines.events.on_built_entity, entity_built)
script.on_event(defines.events.on_robot_built_entity, entity_built)
script.on_event(defines.events.script_raised_built, entity_built)
script.on_event(defines.events.on_player_rotated_entity, entity_rotated)
script.on_event(defines.events.on_entity_settings_pasted, entity_settings_pasted)
script.on_event(defines.events.on_selected_entity_changed, selected_entity_changed)
script.on_event("toggle-global-inserter-visualizer", toggle_global_inserter_visualizer)
if script.active_mods["belt-visualizer"] then script.on_event("bv-highlight-belt", toggle_traced_belt_visualizer) end
script.on_event("toggle-selection-highlighting-shortcut", toggle_selection_highlighting)
script.on_event(defines.events.on_lua_shortcut, toggle_selection_highlighting)
script.on_event(defines.events.on_surface_renamed, surface_renamed)

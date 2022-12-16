
-- colors
local red = {1.0, 0.0, 0.0, 1.0}
local orange = {1.0, 0.5, 0.0, 1.0}
local yellow = {1.0, 1.0, 0.0, 1.0}
local green = {0.0, 1.0, 0.0, 1.0}
local blue = {0.0, 0.0, 1.0, 1.0}
local indigo = {0.29, 0.0, 0.51, 1.0}
local violet = {0.93, 0.51, 0.93, 1.0}
---@type Color
local color = violet

local table = require("__flib__.table")
local floor = math.floor
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
local diagonal_correction = {
	south_west = dirs["west"],
	north_west = dirs["north"],
	south_east = dirs["south"],
	north_east = dirs["east"],
}
local dirs_lookup = {
	[0] = "south",
	[0.125] = "south_west",
	[0.25] = "west",
	[0.375] = "north_west",
	[0.5] = "north",
	[0.625] = "north_east",
	[0.75] = "east",
	[0.875] = "south_east",
}
local active_mods = script.active_mods

-- thank you _codegreen for concocting this magic function
---comment
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

---comment
---@param inserter LuaEntity
---@param player_index PlayerIdentification
local function draw_drop_position(inserter, player_index)
	if not inserter or not inserter.valid then return end
	local adjusted_position = inserter.drop_position
	local drop_target = inserter.drop_target
	local orientation = inserter.orientation
	local drop_target_offset = 1/4
	-- if active_mods["diagonal-inserters"] then
	-- 	orientation = diagonal_correction[dirs_lookup[orientation]]
	-- end
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
	local render_circle = rendering.draw_circle(
		{
			color = color,
			radius = 0.1,
			filled = true,
			target = adjusted_position,
			surface = surface,
			players = {player_index},
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
			players = {player_index},
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

---comment
---@param bounding_box BoundingBox
---@return table
local function get_positions_in_bounding_box(bounding_box)
	local positions = {}
	for x = floor(bounding_box.left_top.x), floor(bounding_box.right_bottom.x) do
		for y = floor(bounding_box.left_top.y), floor(bounding_box.right_bottom.y) do
		table.insert(positions, {x = x, y = y})
		end
	end
	return positions
end

---comment
---@param x integer
---@param y integer
---@param surface_name SurfaceIdentification 
---@param player_index PlayerIdentification
local function draw_drop_positions_by_xy(x, y, surface_name, player_index)
	if not (global.drop_target_positions and global.drop_target_positions[surface_name]) then return end
	local positions_on_surface = global.drop_target_positions[surface_name]
	if not (positions_on_surface[x] and positions_on_surface[x][y]) then return end
	for _, inserter in pairs(positions_on_surface[x][y]) do
		draw_drop_position(inserter, player_index)
	end
end

---comment
---@param data table
---@param player_index PlayerIdentification
local function trace_belts(data, player_index)
	local entity = data.entity
	local from_type = data.from_type
	if not (entity and entity.valid) then return end
	local position = entity.position
	local x = floor(position.x)
	local y = floor(position.y)
	local surface_name = entity.surface.name
	local type = entity.type
	local unit_number = entity.unit_number
	local belt_neighbours = entity.belt_neighbours
	local orientation = entity.orientation

	-- draw any inserter drop positions
	if type == "splitter" then
		local splitter_positions = get_positions_in_bounding_box(entity.bounding_box)
		for _, splitter_position in pairs(splitter_positions) do
			draw_drop_positions_by_xy(splitter_position.x, splitter_position.y, surface_name, player_index)
		end
	elseif type == "transport-belt" or type == "underground-belt" then
		draw_drop_positions_by_xy(x, y, surface_name, player_index)
	end

	-- document that we already traced this belt
	if not global.traced_belts then global.traced_belts = {} end
	if not global.traced_belts[player_index] then global.traced_belts[player_index] = {} end
	local traced_belts = global.traced_belts[player_index]
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
				unique_untraced[neighbour.unit_number] = {entity = neighbour, type = neighbor_type}
			end
		end
	end
	for _, neighbour_data in pairs(unique_untraced) do
		local trace_data = {
			entity = neighbour_data.entity,
			from_type = opposite_type[neighbour_data.type]
		}
		table.insert(global.trace_queue[player_index], trace_data)
	end

	-- add the other side of an underground to the queue
	if type == "underground-belt" and entity.neighbours then
		if traced_belts and traced_belts[entity.neighbours.unit_number] then return end
		table.insert(global.trace_queue[player_index], {entity = entity.neighbours})
	end
end

script.on_event(defines.events.on_selected_entity_changed, function(event)
	local player_index = event.player_index
	if global.highlight_inserters and global.highlight_inserters[player_index] then return end
	local player = game.get_player(player_index)
	local entity = player.selected
	local data = nil

	-- clear any renderings for the player
	::destroy_renderings::
	if not (global.renderings and global.renderings[player_index]) then goto trace_queue end
	data = global.renderings[player_index]
	for key, id in pairs(data.render_ids) do
		rendering.destroy(id)
	end
	data.render_ids = {}

	-- clear any queued belts from the tracer
	::trace_queue::
	if global.trace_queue and global.trace_queue[player_index] then
		global.trace_queue[player_index] = nil
	end
	if global.traced_belts and global.traced_belts[player_index] then
		global.traced_belts[player_index] = nil
	end

	-- draw highlight if entity is an inserter, or add it to the trace queue if it's a belt
	::highlight_entities::
	if not (entity and entity.type) then return end
	local type = entity.type
	if not global.trace_queue then global.trace_queue = {} end
	if not global.trace_queue[player_index] then global.trace_queue[player_index] = {} end
	if type == "inserter" then
		draw_drop_position(entity, player_index)
	elseif belt_types[type] then
		table.insert(global.trace_queue[player_index], {entity = entity})
	end
end)

local function entity_built(event)
	local entity = event.entity or event.created_entity
	if entity.type == "inserter" then

		-- add the inserter to the global list indexed by xy coordinates
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

local function update_drop_locations()
	global.all_inserters = {}
	for _, surface in pairs(game.surfaces) do
		local found_inserters = surface.find_entities_filtered({type = "inserter"})
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
	table.sort(global.all_inserters, function(a,b) return a.unit_number > b.unit_number end)
	-- table.sort(global.all_inserters, function(a,b) return a.unit_number < b.unit_number end)
end

---comment
---@param event EventData.CustomInputEvent
local function toggle_global_inserter_visualizer(event)
	local player_index = event.player_index
	if not global.highlight_inserters then global.highlight_inserters = {} end
	if not global.highlight_inserters[player_index] then
		global.highlight_inserters[player_index] = true
		if not global.inserter_queue then global.inserter_queue = {} end
		global.inserter_queue[player_index] = true
	else
		global.highlight_inserters[player_index] = false
		global.inserter_queue[player_index] = nil
	end

	-- clear any renderings for the player
	if not global.destroy_renderings then global.destroy_renderings = {} end
	if global.renderings and global.renderings[player_index] then
		global.destroy_renderings[player_index] = true
	end

	-- clear any queued belts from the tracer
	if global.trace_queue and global.trace_queue[player_index] then
		global.trace_queue[player_index] = nil
	end
	if global.traced_belts and global.traced_belts[player_index] then
		global.traced_belts[player_index] = nil
	end
	global.from_key = nil
end

-- script.on_init(function() update_drop_locations() save_entities_for_cutscene() end)
-- script.on_configuration_changed(function() update_drop_locations() save_entities_for_cutscene() end)
script.on_init(function() update_drop_locations() end)
script.on_configuration_changed(function() update_drop_locations() end)
script.on_event(defines.events.on_built_entity, function(event) entity_built(event) end)
script.on_event(defines.events.on_robot_built_entity, function(event) entity_built(event) end)
script.on_event(defines.events.script_raised_built, function(event) entity_built(event) end)
script.on_event("toggle-global-inserter-visualizer", function(event) toggle_global_inserter_visualizer(event) end)

-- ensure that if a surface is renamed, all our functions can still access the data they need
script.on_event(defines.events.on_surface_renamed, function (event)
	local old_name, new_name = event.old_name, event.new_name
	if global.drop_target_positions and global.drop_target_positions[old_name] then
		global.drop_target_positions[new_name] = global.drop_target_positions[old_name]
	end
end)

-- a "factory function" so that the player_index upval can be passed through during for_n_of.
-- the `callback` in for_n_of receives two inputs, the value and key of the table that is being processed,
-- so if we call this factory function `factory(uppval_to_pass)` it will return the inner function + the captured upvals,
-- which will be used as the `callback` in for_n_of.
-- Thank you so much justarandomgeek and jansharp for explaining this to me :)
---comment
---@param player_index PlayerIdentification
---@return function
local function draw_drop_positions_partial(player_index)
  return function(inserter)
		if inserter.valid then
			draw_drop_position(inserter, player_index)
		else
			return nil, true -- return the "deletion flag" to tell for_n_of to remove it from global.all_inserters
		end
  end
end

---comment
---@param render_id uint64
---@return nil
---@return boolean
local function destroy_renderings_partial(render_id)
	rendering.destroy(render_id)
	return nil, true -- return the "deletion flag" to tell for_n_of to remove it from global.renderings[player_index]
end

local max_belts_traced_per_tick = 25
local max_inserters_iterated_per_tick = 25
local max_renderings_destroyed_per_tick = 250

script.on_event(defines.events.on_tick, function()
	local belt_queue = global.trace_queue
	local inserter_queue = global.inserter_queue
	local destroy_renderings = global.destroy_renderings
	::belt_queue::
	if not belt_queue then goto inserter_queue end
	for player_index, belts in pairs(belt_queue) do
		local counter = 0
		for id, data in pairs(belts) do
			if counter > max_belts_traced_per_tick then break end
			trace_belts(data, player_index)
			belts[id] = nil
			counter = counter + 1
		end
	end
	::inserter_queue::
	if not inserter_queue then goto render_destruction end
	for player_index, bool in pairs(inserter_queue) do
		if not bool then break end
		-- don't start rendering until all the current ones are destroyed
		if global.destroy_renderings and global.destroy_renderings[player_index] then break end
		local results, reached_end = nil, nil
		global.from_key, results, reached_end = table.for_n_of(
			global.all_inserters,
			global.from_key,
			max_inserters_iterated_per_tick,
			draw_drop_positions_partial(player_index)
		)
		if reached_end then
			global.inserter_queue[player_index] = false
		end
	end
	::render_destruction::
	if not destroy_renderings then return end
	for player_index, bool in pairs(destroy_renderings) do
		if not bool then break end
		-- destroy every rendering for a given player_index
		local results, reached_end = nil, nil
		if not global.player_from_key then global.player_from_key = {} end
		global.player_from_key[player_index], results, reached_end = table.for_n_of(
			global.renderings[player_index].render_ids,
			global.player_from_key[player_index],
			max_renderings_destroyed_per_tick,
			destroy_renderings_partial
		)
		if reached_end then
			global.renderings[player_index] = nil
			destroy_renderings[player_index] = false
		end
	end
end)
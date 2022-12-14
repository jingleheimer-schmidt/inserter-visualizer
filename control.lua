local color = {r = 255, g = 255, b = 0}
-- require "util"
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

local function flip_adjustment(inserter)
	local entity = inserter.drop_target
	if not entity then return end
	if not belt_types[entity.type] then return end
	local belt_direction = entity.direction
	local inputs = entity.belt_neighbours.inputs
	local offset = 0
	if #inputs == 1 and belt_direction ~= inputs[1].direction then
		offset = (belt_direction - inputs[1].direction) % 8 == 2 and 2 or 4
	end
	return belt_direction == (inserter.direction + offset) % 8
end

local function draw_drop_position(inserter, player_index)
	if not inserter or not inserter.valid then return end
	color.a = 1
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
			if flip_adjustment(inserter) then
				adjusted_position.x = adjusted_position.x - drop_target_offset
			else
				adjusted_position.x = adjusted_position.x + drop_target_offset
			end
		elseif orientation >= dirs["north_east"] and orientation < dirs["south_east"] then
		-- elseif orientation == 0.75 then -- placing east
			if flip_adjustment(inserter) then
				adjusted_position.y = adjusted_position.y - drop_target_offset
			else
				adjusted_position.y = adjusted_position.y + drop_target_offset
			end
		elseif orientation >= dirs["south_east"] or orientation < dirs["south_west"] then
		-- elseif orientation == 0 then -- placing south 
			if flip_adjustment(inserter) then
				adjusted_position.x = adjusted_position.x + drop_target_offset
			else
				adjusted_position.x = adjusted_position.x - drop_target_offset
			end
		elseif orientation >= dirs["south_west"] and orientation < dirs["north_west"] then
		-- elseif orientation == 0.25 then -- placing west
			if flip_adjustment(inserter) then
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
			-- time_to_live = 60 * 1, -- 1 seconds
			-- players = {player_index},
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
			-- time_to_live = 60 * 1, -- 1 seconds
			-- players = {player_index},
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

local function trace_belts_new(data, player_index)
	local entity = data.entity
	local from_type = data.from_type
	if entity and entity.valid then
		local position = entity.position
		local x = floor(position.x)
		local y = floor(position.y)
		local surface_name = entity.surface.name
		-- draw any inserter drop positions 
		if global.drop_target_positions and global.drop_target_positions[surface_name] then
			local positions_on_surface = global.drop_target_positions[surface_name]
			if positions_on_surface[x] and positions_on_surface[x][y] then
				for _, inserter in pairs(positions_on_surface[x][y]) do
					draw_drop_position(inserter, player_index)
				end
			end
		end
		-- document that we already traced this belt
		if not global.traced_belts then global.traced_belts = {} end
		if not global.traced_belts[player_index] then global.traced_belts[player_index] = {} end
		local traced_belts = global.traced_belts[player_index]
		if not traced_belts[x] then traced_belts[x] = {} end
		traced_belts[x][y] = true
		-- add any connected belts to the queue
		local belt_neighbours = entity.belt_neighbours
		local opposite_type = {
			inputs = "outputs",
			outputs = "inputs",
		}
		if belt_neighbours then
			for type, neighbours in pairs(belt_neighbours) do
				if type ~= from_type then
					for _, neighbour in pairs(neighbours) do
						local neighbour_position = neighbour.position
						local neighbour_x = floor(neighbour_position.x)
						local neighbour_y = floor(neighbour_position.y)
						if not (traced_belts and traced_belts[neighbour_x] and traced_belts[neighbour_x][neighbour_y]) then
							table.insert(global.trace_queue[player_index], {entity = neighbour, from_type = opposite_type[type]})
						end
					end
				end
			end
		end
		-- add the other side of an underground to the queue
		if entity.type and entity.type == "underground-belt" and entity.neighbours then
			local neighbour_position = entity.neighbours.position
			local neighbour_x = floor(neighbour_position.x)
			local neighbour_y = floor(neighbour_position.y)
			if not (traced_belts and traced_belts[neighbour_x] and traced_belts[neighbour_x][neighbour_y]) then
				table.insert(global.trace_queue[player_index], {entity = entity.neighbours})
			end
		end
	end
end

local function trace_belts_staggered(entity, type_to_ignore, player_index, color, final_ug, traced_belts, counter)
	if not entity.valid then return end
	if not counter then counter = 0 end
	if counter > 25 then
		if not global.belts_to_trace then
			global.belts_to_trace = {}
		end
		global.belts_to_trace[player_index] = {
			starting_entity = entity,
			type_to_ignore = type_to_ignore,
			color = color,
			final_ug = final_ug,
			traced_belts = traced_belts,
		}
		return
	end
	local opposite_type = {
		inputs = "outputs",
		outputs = "inputs",
	}
	traced_belts =  traced_belts or {}
	local x = math.floor(entity.position.x)
	local y = math.floor(entity.position.y)
	if traced_belts == true then
		traced_belts = {
			[x] = {
				[y] = true
			}
		}
	elseif traced_belts[x] then
		if traced_belts[x][y] then
			return
		end
	end
	if entity.type and entity.type == "underground-belt" and entity.neighbours then
		if global.drop_target_positions and global.drop_target_positions[entity.surface.name] then
			local positions_on_surface = global.drop_target_positions[entity.surface.name]
			if positions_on_surface[x] and positions_on_surface[x][y] then
				for _, inserter in pairs(positions_on_surface[x][y]) do
					draw_drop_position(inserter, player_index, color)
				end
			end
		end
		if not final_ug then
			final_ug = true
			if not traced_belts[x] then
				traced_belts[x] = {
					[y] = true
				}
			else
				traced_belts[x][y] = true
			end
			-- trace_belts_staggered(entity.neighbours, type_to_ignore, player_index, color, final_ug, traced_belts, counter + 1)
			table.insert(global.belts_to_trace[player_index], entity.neighbours)
		end
	end
	if entity.belt_neighbours then
		for type, neighbors in pairs(entity.belt_neighbours) do
			-- if type ~= type_to_ignore then
				for _, neighbor in pairs(neighbors) do
					if (neighbor.type == "transport-belt") or (neighbor.type == "splitter") or (neighbor.type == "underground-belt") then
						if global.drop_target_positions and global.drop_target_positions[entity.surface.name] then
							local positions_on_surface = global.drop_target_positions[entity.surface.name]
							if positions_on_surface[x] and positions_on_surface[x][y] then
								for _, inserter in pairs(positions_on_surface[x][y]) do
									draw_drop_position(inserter, player_index, color)
								end
							end
						end
						if not traced_belts[x] then
							traced_belts[x] = {
								[y] = true
							}
						else
							traced_belts[x][y] = true
						end
						-- trace_belts_staggered(neighbor, opposite_type[type], player_index, color, nil, traced_belts, counter + 1)
						table.insert(global.belts_to_trace[player_index], neighbor)
					end
				end
			-- end
		end
	end
end

local function trace_belts(entity, type_to_ignore, player_index, color, final_ug, traced_belts)
	if not entity.valid then return end
	local opposite_type = {
		inputs = "outputs",
		outputs = "inputs",
	}
	traced_belts =  traced_belts or {}
	local x = math.floor(entity.position.x)
	local y = math.floor(entity.position.y)
	if traced_belts == true then
		traced_belts = {
			[x] = {
				[y] = true
			}
		}
	elseif traced_belts[x] then
		if traced_belts[x][y] then
			return
		end
	end
	if entity.type and entity.type == "underground-belt" and entity.neighbours then
		if global.drop_target_positions and global.drop_target_positions[entity.surface.name] then
			local positions_on_surface = global.drop_target_positions[entity.surface.name]
			if positions_on_surface[x] and positions_on_surface[x][y] then
				for _, inserter in pairs(positions_on_surface[x][y]) do
					draw_drop_position(inserter, player_index, color)
				end
			end
		end
		if not final_ug then
			final_ug = true
			if not traced_belts[x] then
				traced_belts[x] = {
					[y] = true
				}
			else
				traced_belts[x][y] = true
			end
			trace_belts(entity.neighbours, type_to_ignore, player_index, color, final_ug, traced_belts)
		end
	end
	if entity.belt_neighbours then
		for type, neighbors in pairs(entity.belt_neighbours) do
			-- if type ~= type_to_ignore then
				for _, neighbor in pairs(neighbors) do
					if (neighbor.type == "transport-belt") or (neighbor.type == "splitter") or (neighbor.type == "underground-belt") then
						-- local x = math.floor(entity.position.x)
						-- local y = math.floor(entity.position.y)
						if global.drop_target_positions and global.drop_target_positions[entity.surface.name] then
							local positions_on_surface = global.drop_target_positions[entity.surface.name]
							if positions_on_surface[x] and positions_on_surface[x][y] then
								for _, inserter in pairs(positions_on_surface[x][y]) do
									draw_drop_position(inserter, player_index, color)
								end
							end
						end
						if not traced_belts[x] then
							traced_belts[x] = {
								[y] = true
							}
						else
							traced_belts[x][y] = true
						end
						-- rendering.draw_circle({
						--     color = color,
						--     radius = 0.1,
						--     filled = true,
						--     target = neighbor,
						--     surface = neighbor.surface,
						--     time_to_live = 60 * 0.25, -- 1 seconds
						-- })
						trace_belts(neighbor, opposite_type[type], player_index, color, nil, traced_belts)
					end
				end
			-- end
		end
	end
end

script.on_event(defines.events.on_selected_entity_changed, function(event)
	local player_index = event.player_index
	if global.highlight_inserters and global.highlight_inserters[player_index] then return end
	local player = game.get_player(player_index)
	local entity = player.selected
	-- clear any renderings for the player
	if global.renderings and global.renderings[player_index] then
		local data = global.renderings[player_index]
		for key, id in pairs(data.render_ids) do
			rendering.destroy(id)
		end
		data.render_ids = {}
	end
	-- clear any queued belts from the tracer
	if global.trace_queue and global.trace_queue[player_index] then
		global.trace_queue[player_index] = nil
	end
	if global.traced_belts and global.traced_belts[player_index] then
		global.traced_belts[player_index] = nil
	end
	-- draw highlight if entity is an inserter, or add it to the trace queue if it's a belt
	if entity and entity.type then
		if entity.type == "inserter" then
			draw_drop_position(entity, event.player_index)
		elseif (entity.type == "transport-belt") or (entity.type == "underground-belt") or  (entity.type == "splitter") then
			if not global.trace_queue then global.trace_queue = {} end
			if not global.trace_queue[player_index] then global.trace_queue[player_index] = {} end
			table.insert(global.trace_queue[player_index], {entity = entity})
		end
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
		-- add the inserter to the global list indexed by unit_number
		if not global.all_inserters then global.all_inserters = {} end
		-- table.insert(global.all_inserters, entity.unit_number, entity)
		-- table.insert(global.all_inserters, {unit_number = entity.unit_number, entity = entity})
		table.insert(global.all_inserters, entity)
	end
end

local function update_drop_locations()
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
	-- table.sort(global.all_inserters, function(a,b) return a.unit_number > b.unit_number end)
	table.sort(global.all_inserters, function(a,b) return a.unit_number < b.unit_number end)
end

local function toggle_global_inserter_visualizer(event)
	local player_index = event.player_index
	if not global.highlight_inserters then global.highlight_inserters = {} end
	if not global.highlight_inserters[player_index] then
		global.highlight_inserters[player_index] = true
		if not global.inserter_queue then global.inserter_queue = {} end
		global.inserter_queue[player_index] = true
		-- global.inserter_queue[player_index] = util.table.deepcopy(global.drop_target_positions)
		-- global.inserter_queue[player_index] = global.drop_target_positions
	else
		global.highlight_inserters[player_index] = false
		global.inserter_queue[player_index] = nil
	end
	-- clear any renderings for the player
	if global.renderings and global.renderings[player_index] then
		local data = global.renderings[player_index]
		for key, id in pairs(data.render_ids) do
			rendering.destroy(id)
		end
		data.render_ids = {}
	end
	-- clear any queued belts from the tracer
	if global.trace_queue and global.trace_queue[player_index] then
		global.trace_queue[player_index] = nil
	end
	if global.traced_belts and global.traced_belts[player_index] then
		global.traced_belts[player_index] = nil
	end
	if global.highlighted_inserters then
		global.highlighted_inserters = nil
	end
	global.from_key = nil
	
	-- table.sort(global.all_inserters, function(a,b) return a.unit_number > b.unit_number end)
end

script.on_init(function() update_drop_locations() end)
script.on_configuration_changed(function() update_drop_locations() end)
script.on_event(defines.events.on_built_entity, function(event) entity_built(event) end)
script.on_event(defines.events.on_robot_built_entity, function(event) entity_built(event) end)
script.on_event(defines.events.script_raised_built, function(event) entity_built(event) end)
script.on_event("toggle-global-inserter-visualizer", function(event) toggle_global_inserter_visualizer(event) end)

-- script.on_event(defines.events.on_tick, function(event)
--     local renderings = global.renderings
--     if renderings then
--         for player_index, data in pairs(renderings) do
--             if not data.player or not data.player.valid then
--                 renderings[player_index] = nil
--             else
--                 for key, id in pairs(data.render_ids) do
--                     if not rendering.is_valid(id) then
--                         renderings[player_index][key] = nil
--                     else
--                         local color = data.player.color
--                         color.a = 1
--                         rendering.set_color(id, color)
--                     end
--                 end
--             end
--         end
--     end
-- end)

script.on_event(defines.events.on_tick, function()
	local belt_queue = global.trace_queue
	if belt_queue then
		for player_index, belts in pairs(belt_queue) do
			local counter = 0
			for id, data in pairs(belts) do
				if counter < 5 then
					trace_belts_new(data, player_index)
					belts[id] = nil
					counter = counter + 1
				end
			end
		end
	end
	local inserter_queue = global.inserter_queue
	if inserter_queue then
		for player_index, bool in pairs(inserter_queue) do
			if bool then
				local results, reached_end = nil, nil
				global.from_key, results, reached_end = table.for_n_of(global.all_inserters, global.from_key, 33, function(inserter)
					if inserter.valid then
						draw_drop_position(inserter, player_index)
						-- game.print(inserter.unit_number)
					end
				end)
				if reached_end then
					global.inserter_queue[player_index] = false
				end
			end
		end
	end
	-- if inserter_queue then
	-- 	for player_index, data in pairs(inserter_queue) do
	-- 		local counter = 0
	-- 		for surface_name, x_positions in pairs(data) do
	-- 			if counter > 10 then return end
	-- 			local next = next
	-- 			for x, y_positions in pairs(x_positions) do
	-- 				if counter > 10 then return end
	-- 				for y, inserters in pairs(y_positions) do
	-- 					if counter > 10 then return end
	-- 					for id, inserter in pairs(inserters) do
	-- 						draw_drop_position(inserter, player_index)
	-- 						data[surface_name][x][y][id] = nil
	-- 						if next(inserters) == nil then
	-- 							data[surface_name][x][y] = nil
	-- 						end
	-- 						counter = counter + 1
	-- 					end
	-- 					if next(y_positions) == nil then
	-- 						data[surface_name][x] = nil
	-- 					end
	-- 				end
	-- 				if next(x_positions) == nil then
	-- 					data[surface_name] = nil
	-- 				end
	-- 			end
	-- 		end
	-- 	end
	-- end
end)
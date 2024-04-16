local InputController = require("scripts/input_controller")

local FocusMeter = {}

--Basic mod info
FocusMeter.info = {
	name = "FocusMeter",
	author = "SuperMickyJay",
	description = "Displays the amount of focus next to each player.",
	version = "0.1",
	repo_link = "",
	last_dt = 0,
}

FocusMeter.settings = {	
	show_player_bar = true,	
	show_player_icons = true,
	show_team_bars = true,
	show_team_icons = true,
	show_enemy_bars = true,
	show_enemy_icons = true,
	focus_bar_positions = 1,
	keyboard = {
		toggle_player_bar = {"left shift", "left alt", "i"},
		toggle_player_icons = {"left shift", "left alt", "j"},
		toggle_team_bars = {"left shift", "left alt", "o"},
		toggle_team_icons = {"left shift", "left alt", "k"},
		toggle_enemy_bars = {"left shift", "left alt", "p"},
		toggle_enemy_icons = {"left shift", "left alt", "l"},
		toggle_focus_bar_positions = {"left shift", "left alt", "u"},
		key_last_update = 0,
	}
}

--UI Helper Functions

local focus_bar_fill_size = {34, 24}
local focus_bar_size = {192, 24}
local focus_bar_scale = 3
local focus_bar_portrait_scale = 1.35 

-- Gets the screen position for the focus bar based on the player position and settings.
local function get_screen_pos_for_new_focus_bar(condition_args)
	local settings = FocusMeter.settings
	local peer_id = condition_args.peer_id or "missing_id"
	local position = (GET_UNIT_POS(ID_TO_UNIT(peer_id)) or Vector3(0, 0, 0))

	if (settings.focus_bar_positions == 1) then
		position = position + Vector3(0.4, 0, 3.05)
	elseif (settings.focus_bar_positions == 2) then
		position = position + Vector3(0.4, 0, 2.56)
	elseif (settings.focus_bar_positions == 3) then
		position = position + Vector3(0.4, 0, 2.06)
	end

	return VEC_TO_TABLE(WORLD_TO_SCREEN(position))
end

-- Gets the screen position for the focus icons based on the player position.
local function get_screen_pos_for_new_focus_icons(condition_args)
	local peer_id = condition_args.peer_id or "missing_id"
	local position = (GET_UNIT_POS(ID_TO_UNIT(peer_id)) or Vector3(0, 0, 0)) + Vector3(-0.45, 0, 2.4175) 

	return VEC_TO_TABLE(WORLD_TO_SCREEN(position))
end

-- Gets the screen position for the portrait focus bars.
local function get_screen_pos_for_portrait_focus_bar(condition_args)
	local player_portrait = GET_PLAYER_PORTRAIT_UI_ELEMENT(condition_args.peer_id) 
	local player_portrait_position = GET_INGAME_UI_ELEMENT_POS(player_portrait)

	-- Team 1 is the left team so we add to the X value to move it to the right of the portrait 
	-- and minus from the X value to move it to the left of the portrait for the other team.
	if condition_args.team == 1 then
		return {player_portrait_position[1] + 85, player_portrait_position[2] + 3.5, 0}
	else
		return {player_portrait_position[1] - 148, player_portrait_position[2] + 3.5, 0}
	end
end

-- Gets the amount of focus the player has.
local function get_focus(peer_id)
	local unit_data = GET_UNIT_DATA(peer_id)
	return unit_data.focus
end

-- Gets whether the supplied is alive or not.
local function get_alive(peer_id)
	local unit = GET_UNIT_DATA(peer_id)
	if unit.health > 0 then
		return true
	end		

	return false
end

--Returns whether player is on the user's team.
local function check_same_team(peer_id)
	--data about the target player
	local peer_data = GET_UNIT_DATA(peer_id) or {}
	--data about the local player
	local self_data = GET_UNIT_DATA(Network.peer_id())

	if peer_data.team == self_data.team then
		return true
	end

	return false
end

--Returns the team the player is on.
local function get_team(peer_id)
	local peer_data = GET_UNIT_DATA(peer_id) or {}
	
	return peer_data.team
end

-- Gets the size of the focus bar fill based on the amount of focus the player has.
-- This is what makes the bar slowly fill up by scaling the X value.
local function get_focus_bar_fill_size(condition_args)
	local focus = get_focus(condition_args.peer_id)
	local relative_focus = focus - (condition_args.focus_bar_number * 25)
	local size
	
	if (condition_args.focus_bar_number == 0 and focus < 25) then		
		size = {focus_bar_fill_size[1] * (focus / 25), focus_bar_fill_size[2]}	
	elseif (condition_args.focus_bar_number == 1 and focus < 50 and focus > 25) then
		size = {focus_bar_fill_size[1] * (relative_focus / 25), focus_bar_fill_size[2]}	
	elseif (condition_args.focus_bar_number == 2 and focus < 75 and focus > 50) then
		size = {focus_bar_fill_size[1] * (relative_focus / 25), focus_bar_fill_size[2]}	
	elseif (condition_args.focus_bar_number == 3 and focus < 100 and focus > 75) then
		size = {focus_bar_fill_size[1] * (relative_focus / 25), focus_bar_fill_size[2]}	
	else
		size = {focus_bar_fill_size[1], focus_bar_fill_size[2]}
	end

	if condition_args.is_portrait then
		return {size[1]/focus_bar_portrait_scale, size[2]/focus_bar_portrait_scale}
	end

	return {size[1]/focus_bar_scale, size[2]/focus_bar_scale}
end

-- Determines whether to show the focus bar or not based on settings and if the player is alive.
local function show_focus_bar(condition_args)
	if condition_args.is_portrait then
		if not InputController:input_pressed(UserSetting()["keybindings"]["show_stats_screen"]) then
			return "hud_portrait_focus_bar"
		end

		-- Don't show anything.
		return 
	end

	local alive = get_alive(condition_args.peer_id)

	if (condition_args.peer_id == Network.peer_id() and FocusMeter.settings.show_player_bar) or (condition_args.peer_id ~= Network.peer_id() and condition_args.is_team and FocusMeter.settings.show_team_bars) or (FocusMeter.settings.show_enemy_bars and not condition_args.is_team) then
		if alive then 
			return "hud_portrait_focus_bar"
		end
	end
end

-- Determines whether to show the focus bar fill or not based on settings and if the player is alive.
local function show_focus_fill(condition_args)
	local focus = get_focus(condition_args.peer_id)
	local alive = get_alive(condition_args.peer_id)

	if (condition_args.is_portrait) then
		if not InputController:input_pressed(UserSetting()["keybindings"]["show_stats_screen"]) then
			if (condition_args.focus_bar_number == 0) or (focus > 25 and condition_args.focus_bar_number == 1) or (focus > 50 and condition_args.focus_bar_number == 2) or (focus > 75 and condition_args.focus_bar_number == 3) then
				return "hud_portrait_focus_bar_fill"
			end
		end

		-- Don't show anything.
		return
	end

	if (condition_args.peer_id == Network.peer_id() and FocusMeter.settings.show_player_bar) or (condition_args.peer_id ~= Network.peer_id() and condition_args.is_team and FocusMeter.settings.show_team_bars) or (FocusMeter.settings.show_enemy_bars and not condition_args.is_team) then
		if alive then 
			if (condition_args.focus_bar_number == 0) or (focus > 25 and condition_args.focus_bar_number == 1) or (focus > 50 and condition_args.focus_bar_number == 2) or (focus > 75 and condition_args.focus_bar_number == 3) then
				return "hud_portrait_focus_bar_fill"
			end
		end
	end
end

-- Determines whether to show the focus icons or not based on settings and if the player is alive.
local function show_focus_icon(condition_args)
	local focus = get_focus(condition_args.peer_id)
	local alive = get_alive(condition_args.peer_id)	

	if (condition_args.peer_id == Network.peer_id() and FocusMeter.settings.show_player_icons) or (condition_args.peer_id ~= Network.peer_id() and condition_args.is_team and FocusMeter.settings.show_team_icons) or (FocusMeter.settings.show_enemy_icons and not condition_args.is_team) then
		if alive then 
			if (focus >= 25 and condition_args.focus_bar_number == 0) or (focus >= 50 and condition_args.focus_bar_number == 1) or (focus >= 75 and condition_args.focus_bar_number == 2) or (focus == 100 and condition_args.focus_bar_number == 3) then
				if (condition_args.type == "fill") then
					return "hud_portrait_focus_bar_fill"
				end 
		
				return "hud_portrait_focus_eruption"	
			end
		end
	end
end

--UI Helper Functions End

FocusMeter.init = function(self, context)
	FocusMeter.settings = LOAD_GLOBAL_MOD_SETTINGS(FocusMeter.info.name, FocusMeter.settings, false)

	SAVE_GLOBAL_MOD_SETTINGS(FocusMeter.info.name, FocusMeter.settings)
end

FocusMeter.ingame_init = function (self, context)
	-- Get the game mode.
	local gamemode_configuration = ApplicationStorage.get_data_keep("network_gamemode_configuration")

	--Add a delay so that the UI gets attached after the player has spawned.
	SIMPLE_TIMER(1, function()	
		-- Gets full list of active players.
		local player_list = GET_PEER_LIST()

		-- Adds focus bars/icons to players.
		for i = 1, #player_list, 1 do
			-- Get whether the player is on the same team as the user, for option toggles.
			local is_team = check_same_team(player_list[i])

			-- We only want to show the portrait focus bars in Warfare (koala) and Soul Harvest (confusion)
			-- as the other modes already have the focus bars.
			if gamemode_configuration.gamemode_type == "koala" or gamemode_configuration.gamemode_type == "confusion" then
				-- Get the team of the player to know which direction to move the focus bar.
				local team = get_team(player_list[i])
				local player_portrait = GET_PLAYER_PORTRAIT_UI_ELEMENT(player_list[i]) 

				if player_portrait then
					local player_portrait_position = GET_INGAME_UI_ELEMENT_POS(player_portrait)
				
					-- Markup for the focus bar.
					local focus_bar_markup = UIFunc.new_texture_markup(
						show_focus_bar, 
						get_screen_pos_for_portrait_focus_bar,
						{focus_bar_size[1]/focus_bar_portrait_scale, focus_bar_size[2]/focus_bar_portrait_scale}, 
						false,
						GET_DEFAULT_TEXTURE_COLOR(),
						{peer_id = player_list[i], team = team, is_portrait = true}
					)
		
					NEW_UI_ELEMENT("ingame", focus_bar_markup)
		
					-- Loop for the four sections of focus fill markups.
					for j = 0, 3, 1 do
						local focus_bar_fill_markup = UIFunc.new_texture_markup(
							show_focus_fill,  
							{(9 + (47 * j))/focus_bar_portrait_scale, 0, 10}, 
							get_focus_bar_fill_size, 
							false,
							GET_DEFAULT_TEXTURE_COLOR(),
							{peer_id = player_list[i], focus_bar_number = j, team = team, is_portrait = true}
						)
					
						UIFunc.add_child(focus_bar_markup, focus_bar_fill_markup)
					end
				end
			end

			-- Markup for the focus bar.
			local focus_bar_markup = UIFunc.new_texture_markup(
				show_focus_bar, 
				get_screen_pos_for_new_focus_bar,
				{focus_bar_size[1]/focus_bar_scale, focus_bar_size[2]/focus_bar_scale}, 
				false,
				GET_DEFAULT_TEXTURE_COLOR(),
				{peer_id = player_list[i], is_team = is_team, is_portrait = false}
			)

			NEW_UI_ELEMENT("ingame", focus_bar_markup)

			-- Loop for the four sections of focus fill markups.
			for j = 0, 3, 1 do
				local focus_bar_fill_markup = UIFunc.new_texture_markup(
					show_focus_fill,  
					{(9 + (47 * j))/focus_bar_scale, 0, 10}, 
					get_focus_bar_fill_size, 
					false,
					GET_DEFAULT_TEXTURE_COLOR(),
					{peer_id = player_list[i], focus_bar_number = j, is_team = is_team, is_portrait = false}
				)
			
				UIFunc.add_child(focus_bar_markup, focus_bar_fill_markup)
			end

			-- A placeholder parent for grouping the focus icons together
			local focus_icons_parent_markup = UIFunc.new_texture_markup(
				"hud_portrait_focus_bar_fill", 
				get_screen_pos_for_new_focus_icons,
				{12,12}, 
				false,
				{0,0,0,0},
				{peer_id = player_list[i]}
			)

			NEW_UI_ELEMENT("ingame", focus_icons_parent_markup)


			-- Loop for the four focus icon markups.
			local n = 0

			for j = 0, 6, 6 do
				for k = 0, 6, 6 do
					local focus_icon_fill_markup = UIFunc.new_texture_markup(
						show_focus_icon, 
						{0 + j, 0 - k, 10}, 
						{4,6}, 
						false,
						GET_DEFAULT_TEXTURE_COLOR(),
						{peer_id = player_list[i], focus_bar_number = n, type = "fill", is_team = is_team}
					)

					local focus_icon_highlight_markup = UIFunc.new_texture_markup(
						show_focus_icon, 
						{0 + j, 0 - k, 10}, 
						{4,6}, 
						false,
						GET_DEFAULT_TEXTURE_COLOR(),
						{peer_id = player_list[i], focus_bar_number = n, type = "highlight", is_team = is_team}
					)

					UIFunc.add_child(focus_icons_parent_markup, focus_icon_fill_markup)
					UIFunc.add_child(focus_icons_parent_markup, focus_icon_highlight_markup)

					n = n + 1
				end
			end			
		end		
	end)
end

FocusMeter.update = function (self, context)
	local dt = context.dt
	local settings = FocusMeter.settings
	local settings_changed = false

	FocusMeter.info.last_dt = dt

	-- Update keys. 
	-- As no "pressed up" implemented for multiple keys currently.
	if InputController:input_pressed_once(settings.keyboard.toggle_focus_bar_positions) then
		local focus_bar_position = settings.focus_bar_positions

		focus_bar_position = focus_bar_position + 1

		if focus_bar_position > 3 then
			focus_bar_position = 1
		end

		settings.focus_bar_positions = focus_bar_position
		settings_changed = true
	elseif InputController:input_pressed_once(settings.keyboard.toggle_player_bar) then
		settings.show_player_bar = not settings.show_player_bar
		settings_changed = true
	elseif InputController:input_pressed_once(settings.keyboard.toggle_player_icons) then
		settings.show_player_icons = not settings.show_player_icons
		settings_changed = true
	elseif InputController:input_pressed_once(settings.keyboard.toggle_team_bars) then
		settings.show_team_bars = not settings.show_team_bars
		settings_changed = true
	elseif InputController:input_pressed_once(settings.keyboard.toggle_team_icons) then
		settings.show_team_icons = not settings.show_team_icons
		settings_changed = true
	elseif InputController:input_pressed_once(settings.keyboard.toggle_enemy_bars) then
		settings.show_enemy_bars = not settings.show_enemy_bars
		settings_changed = true
	elseif InputController:input_pressed_once(settings.keyboard.toggle_enemy_icons) then
		settings.show_enemy_icons = not settings.show_enemy_icons
		settings_changed = true
	end

	-- Update settings.
	if settings_changed then
		settings.keyboard.key_last_update = 1
		SAVE_GLOBAL_MOD_SETTINGS(FocusMeter.info.name, settings)
	end
end

--subscribe to menu to get own peer id
SUBSCRIBE_TO_STATE("menu", "init", FocusMeter.info.name, FocusMeter.init, FocusMeter)

--subscribe to ingame events
SUBSCRIBE_TO_STATE("ingame", "players_initialized", FocusMeter.info.name, FocusMeter.ingame_init, FocusMeter)
SUBSCRIBE_TO_STATE("ingame", "update", FocusMeter.info.name, FocusMeter.update, FocusMeter)

return FocusMeter
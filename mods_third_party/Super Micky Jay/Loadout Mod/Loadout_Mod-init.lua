local InputController = require("scripts/input_controller")

local LoadoutMod = {}

local VERSION = "1.0"
local VERSION_WHOLE = "Loadout Mod Version " .. VERSION

ACTIVE_GAME_STATE = "menu"

local string_dash_break = "-----------------------------------------------------------\n"

--Basic mod info
LoadoutMod.info = {
	name = "LoadoutMod",
	author = "SuperMickyJay",
	description = "Adds the ability to save and load gear loadouts.",
	version = VERSION,
	repo_link = "",
	last_dt = 0,
}

LoadoutMod.hidden_settings = {
	loadouts = {
		loadout_1 = {},
		loadout_2 = {},
		loadout_3 = {},
	},
}

--UI Helper Functions

local function firstToUpper(string)
    return (string:gsub("^%l", string.upper))
end

local function string_insert(whole_string, insert, pos)
    return whole_string:sub(1,pos)..insert..whole_string:sub(pos+1)
end


local function popup_function_self_destroy(popup_item, button_function)
	button_function()

	UIFunc.kill_element_and_children(popup_item)
end

local function create_popup(title, message, button_function)
	local z_pos = 600
	local x_size = 500
	local y_size = 400

	local new_popup = UIFunc.new_texture_markup(
		"window_tile",
		{GET_CENTER_SCREEN_X_SCALED(), GET_CENTER_SCREEN_Y_SCALED(), z_pos},
		{x_size, y_size},
		true, 
		{200, 0, 0, 0},
		{}
	)

	UIFunc.add_child(new_popup, UIFunc.new_text_markup(title, {0, 150, z_pos + 1}, 30, {255, 255, 255, 255}, true))
	UIFunc.add_child(new_popup, UIFunc.new_text_body(message, {-200, 110, z_pos + 1}, 16, 60, 22))
	UIFunc.add_child(new_popup, UIFunc.new_button_unattached({0, -95, z_pos + 1}, "OK  ", 0, 0, function() popup_function_self_destroy(new_popup, button_function) end))
	
	local border_color = function() return {255,60,60,60} end

	--add decorations
	UIFunc.add_child(new_popup, UIFunc.new_texture_markup("window_tile", {(x_size * 0.49), 0, z_pos + 1}, UIFunc.new_texture_size(y_size,10), true, border_color))
	UIFunc.add_child(new_popup, UIFunc.new_texture_markup("window_tile", {-(x_size * 0.49), 0, z_pos + 1}, UIFunc.new_texture_size(y_size,10), true, border_color))
	UIFunc.add_child(new_popup, UIFunc.new_texture_markup("window_tile", {0, (y_size * 0.49), z_pos + 1}, UIFunc.new_texture_size(10,x_size), true, border_color))
	UIFunc.add_child(new_popup, UIFunc.new_texture_markup("window_tile", {0, -(y_size * 0.49), z_pos + 1}, UIFunc.new_texture_size(10,x_size), true, border_color))

   	NEW_UI_ELEMENT(ACTIVE_GAME_STATE, new_popup)
	
	return new_popup
end

local function save_loadout_1()
	local loadout_info = DEEP_CLONE(GET_GAME_DATA("loadout_info"))
	local settings = LoadoutMod.hidden_settings

	if #settings.loadouts.loadout_1 == 0 then
		table.insert(settings.loadouts.loadout_1, loadout_info)
	else		
		settings.loadouts.loadout_1[1] = loadout_info
	end

	SAVE_GLOBAL_MOD_SETTINGS(LoadoutMod.info.name, settings, true)
	create_popup("Loadout 1 Saved!", string_dash_break, function() end)
end

local function load_loadout_1()
	LoadoutMod.hidden_settings = LOAD_GLOBAL_MOD_SETTINGS(LoadoutMod.info.name, LoadoutMod.hidden_settings, true)

	if #LoadoutMod.hidden_settings.loadouts.loadout_1 == 0 then
		create_popup("Loadout Warning!", string_dash_break .. "No loadout saved in slot 1!", function() end)
		return
	end

	local loadout = LoadoutMod.hidden_settings.loadouts.loadout_1[1]
	local setup = LoadoutSetup_init_from_defaults()
	local gear_string = string_dash_break

	for k in pairs(loadout) do
		LoadoutSetup.set_equipment(setup, k, loadout[k]["equipment_name"])

		if k == "staff" or k == "ring" or k == "trinket" or k == "robe" or k == "weapon" then
			if k == "robe" then
				gear_string = gear_string .. firstToUpper(k) .. ": " .. LocalizationManager:lookup(loadout[k]["equipment_name"]) .. " () \n"
			else
				gear_string = gear_string .. firstToUpper(k) .. ": " .. LocalizationManager:lookup(loadout[k]["equipment_name"]) .. "\n"
			end
		end
	end

	for k in pairs(loadout) do
		if k == "robe_skin" then
			local position = string.find(gear_string, "%(")
			gear_string = string_insert(gear_string, LocalizationManager:lookup(loadout[k]["equipment_name"]), position)
		end
	end

	gear_string = gear_string .. "\n !!! Please note: Visually your gear will not change until the match starts !!!!"
	create_popup("Loadout 1 Loaded!", gear_string, function() end)
end

local function save_loadout_2()
	local loadout_info = DEEP_CLONE(GET_GAME_DATA("loadout_info"))
	local settings = LoadoutMod.hidden_settings

	if #settings.loadouts.loadout_2 == 0 then
		table.insert(settings.loadouts.loadout_2, loadout_info)
	else		
		settings.loadouts.loadout_2[1] = loadout_info
	end

	SAVE_GLOBAL_MOD_SETTINGS(LoadoutMod.info.name, settings, true)
	create_popup("Loadout 2 Saved!", string_dash_break, function() end)
end

local function load_loadout_2()
	LoadoutMod.hidden_settings = LOAD_GLOBAL_MOD_SETTINGS(LoadoutMod.info.name, LoadoutMod.hidden_settings, true)

	if #LoadoutMod.hidden_settings.loadouts.loadout_2 == 0 then
		create_popup("Loadout Warning!", string_dash_break .. "No loadout saved in slot 2!", function() end)
		return
	end

	local loadout = LoadoutMod.hidden_settings.loadouts.loadout_2[1]
	local setup = LoadoutSetup_init_from_defaults()
	local gear_string = string_dash_break

	for k in pairs(loadout) do
		LoadoutSetup.set_equipment(setup, k, loadout[k]["equipment_name"])

		if k == "staff" or k == "ring" or k == "trinket" or k == "robe" or k == "weapon" then
			if k == "robe" then
				gear_string = gear_string .. firstToUpper(k) .. ": " .. LocalizationManager:lookup(loadout[k]["equipment_name"]) .. " () \n"
			else
				gear_string = gear_string .. firstToUpper(k) .. ": " .. LocalizationManager:lookup(loadout[k]["equipment_name"]) .. "\n"
			end
		end
	end

	for k in pairs(loadout) do
		if k == "robe_skin" then
			local position = string.find(gear_string, "%(")
			gear_string = string_insert(gear_string, LocalizationManager:lookup(loadout[k]["equipment_name"]), position)
		end
	end

	gear_string = gear_string .. "\n !!! Please note: Visually your gear will not change until the match starts !!!!"
	create_popup("Loadout 2 Loaded!", gear_string, function() end)
end

local function save_loadout_3()
	local loadout_info = DEEP_CLONE(GET_GAME_DATA("loadout_info"))
	local settings = LoadoutMod.hidden_settings

	if #settings.loadouts.loadout_3 == 0 then
		table.insert(settings.loadouts.loadout_3, loadout_info)
	else		
		settings.loadouts.loadout_3[1] = loadout_info
	end

	SAVE_GLOBAL_MOD_SETTINGS(LoadoutMod.info.name, settings, true)
	create_popup("Loadout 3 Saved!", string_dash_break, function() end)
end

local function load_loadout_3()
	LoadoutMod.hidden_settings = LOAD_GLOBAL_MOD_SETTINGS(LoadoutMod.info.name, LoadoutMod.hidden_settings, true)

	if #LoadoutMod.hidden_settings.loadouts.loadout_3 == 0 then
		create_popup("Loadout Warning!", string_dash_break .."No loadout saved in slot 3!", function() end)
		return
	end

	local loadout = LoadoutMod.hidden_settings.loadouts.loadout_3[1]
	local setup = LoadoutSetup_init_from_defaults()
	local gear_string = string_dash_break

	for k in pairs(loadout) do
		LoadoutSetup.set_equipment(setup, k, loadout[k]["equipment_name"])

		if k == "staff" or k == "ring" or k == "trinket" or k == "robe" or k == "weapon" then
			if k == "robe" then
				gear_string = gear_string .. firstToUpper(k) .. ": " .. LocalizationManager:lookup(loadout[k]["equipment_name"]) .. " () \n"
			else
				gear_string = gear_string .. firstToUpper(k) .. ": " .. LocalizationManager:lookup(loadout[k]["equipment_name"]) .. "\n"
			end
		end
	end

	for k in pairs(loadout) do
		if k == "robe_skin" then
			local position = string.find(gear_string, "%(")
			gear_string = string_insert(gear_string, LocalizationManager:lookup(loadout[k]["equipment_name"]), position)
		end
	end

	gear_string = gear_string .. "\n !!! Please note: Visually your gear will not change until the match starts !!!!"
	create_popup("Loadout 3 Loaded!", gear_string, function() end)
end

local function random_loadout()
	local setup = LoadoutSetup_init_from_defaults()

	LoadoutSetup.set_random_equipment(setup, "robe", "")
	LoadoutSetup.set_random_equipment(setup, "staff", "")
	LoadoutSetup.set_random_equipment(setup, "weapon", "")
	LoadoutSetup.set_random_equipment(setup, "trinket", "")
	LoadoutSetup.set_random_equipment(setup, "ring", "")

	create_popup("Random Loadout Loaded!", string_dash_break .. "!!! Please note: Visually your gear will not change until the match starts !!! \n\n If your character glows white then it means it accidentally gave the wrong skin for the robe. This is fine, the default skin of that robe will be loaded when the match starts.", function() end)
end

--UI Helper Functions End

LoadoutMod.init = function(self, context)
	LoadoutMod.hidden_settings = LOAD_GLOBAL_MOD_SETTINGS(LoadoutMod.info.name, LoadoutMod.hidden_settings, true)
	SAVE_GLOBAL_MOD_SETTINGS(LoadoutMod.info.name, LoadoutMod.hidden_settings, true)

	loadout_mod_tab = {tab = nil}

	loadout_mod_tab.tab = UIFunc.new_mod_tab("Loadout Mod", "Loadout Mod", function ()
		local tab_description = "Adds the ability to save and load gear loadouts.\nCreated By SuperMickyJay"
		UIFunc.add_element_to_tab(loadout_mod_tab.tab, UIFunc.new_text_markup(VERSION_WHOLE, {100, GET_SCREEN_SIZE_Y() - 200,502}, 40, {255,255,255,255}, false, {}))
		UIFunc.add_element_to_tab(loadout_mod_tab.tab, UIFunc.new_text_body(tab_description, {100, GET_SCREEN_SIZE_Y() - 250,502}, 20, 100, 25))
	end)

	SIMPLE_TIMER(0.2, function()
		UIFunc.new_button({500, 32, 500}, "Save Loadout 1", 1, 0, save_loadout_1)
		UIFunc.new_button({650, 32, 500}, "Load Loadout 1", 1, 0, load_loadout_1)

		UIFunc.new_button({800, 32, 500}, "Save Loadout 2", 1, 0, save_loadout_2)
		UIFunc.new_button({950, 32, 500}, "Load Loadout 2", 1, 0, load_loadout_2)

		UIFunc.new_button({1100, 32, 500}, "Save Loadout 3", 1, 0, save_loadout_3)
		UIFunc.new_button({1250, 32, 500}, "Load Loadout 3", 1, 0, load_loadout_3)

		UIFunc.new_button({1400, 32, 500}, "Random Gear", -7, 0, random_loadout)
	end)
end

SUBSCRIBE_TO_STATE("menu", "init", LoadoutMod.info.name, LoadoutMod.init, LoadoutMod)

return LoadoutMod
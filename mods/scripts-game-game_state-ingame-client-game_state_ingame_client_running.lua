require("scripts/game/util/level_callback")
require("scripts/game/entity_system/entity_system_bag_client")
require("scripts/game/managers/hud_manager")
require("scripts/game/game_state/ingame/client/state_ingame_running_client")
require("scripts/game/game_state/ingame/client/state_ingame_failed_client")
require("scripts/game/game_state/ingame/client/state_ingame_lobby_client")
require("scripts/game/chat/chat_client_handler")
require("scripts/game/chat/chat_system")
require("scripts/game/util/pd_camera_controller_freeflight")
require("scripts/game/network/network_spawnpoints")
require("scripts/game/entity_system/systems/network/network_system_aux")
require("scripts/game/rendering/shading_environment_manager")

local GameModeTimer = require_bs("scripts/game/gamemode/gamemode_timer")
local Resolution = require_bs("foundation/scripts/util/engine/resolution")
local PlayerAssembly = require_bs("scripts/game/network/network_player_assembly")
local MatchMakerInterface = require_bs("scripts/game/network/network_matchmaker_interface")
local CurseVoiceChat = require_bs("scripts/game/curse_voice/curse_voice_chat")
local ChatAlias = "game"
local ChatTeam1Alias = "team1"
local ChatTeam2Alias = "team2"

local function get_unit_extension_functor_client(unit, extension_table)
	local is_husk_unit = NetworkUnit.is_husk_unit_boolean(unit)

	if lua_type(is_husk_unit) ~= "boolean" then
		local break_here = 1

		assert(false)
	end

	local extensions = "client_extensions"

	if is_husk_unit then
		slot4 = pdNetworkServerUnit.is_server_object(unit) and 1

		if pdNetworkServerUnit.owning_peer_is_self(unit) then
			slot4 = 1
		elseif Unit.has_data(unit, "client_husk_extensions") then
			extensions = "client_husk_extensions"
		end
	end

	local Unit_get_data = Unit.get_data
	local i = 0
	local extension_name = Unit_get_data(unit, extensions, i)

	while extension_name do
		i = i + 1
		extension_table[i] = extension_name
		extension_name = Unit_get_data(unit, extensions, i)
	end

	local has_old_style_extensions = Unit_get_data(unit, "extensions", 0) or Unit_get_data(unit, "husk_extensions", 0)

	if has_old_style_extensions then
		cat_printf_warning("always", "[CLIENT] old extension naming for unit : %s", tostring(unit))
	end

	return i
end

local TIME_BETWEEN_PING_TELEMETRY = 10
GameStateIngameClientRunning = class(GameStateIngameClientRunning, nil, "GameStateIngameClientRunning")

GameStateIngameClientRunning.init = function (self)
	self.ALIAS = "ingame_running_client"
	self.scratch_arrays = {
		pdArray.new(),
		pdArray.new()
	}
	local num_frames_to_store = 1
	self.num_frames_to_store = num_frames_to_store
	self.delayed_destroyed_gameobject_ids = {}

	for i = 1, self.num_frames_to_store, 1 do
		self.delayed_destroyed_gameobject_ids[i] = pdArray.new()
	end

	self.current_update_index = 1

	self:set_update_index()

	self.entity_systems_update_context = {}

	PresenceAux.set(PresenceAux.Status.KEY, PresenceAux.Status.IN_GAME)
	
	print("GAMESTATE INJECTED")

	self.time_to_send_telemetry = 1
	self.fps_num_frames = 0
	self.fps_elapsed_time = 0
	self.fps_average = 0
end

GameStateIngameClientRunning.set_update_index = function (self)
	self.current_update_index = self.current_update_index % self.num_frames_to_store + 1
	self.delete_index = (self.current_update_index + 1) % self.num_frames_to_store + 1
end

GameStateIngameClientRunning.setup_network = function (self, network_message_router)
	self.game_session = Network.game_session()
	self.network_message_router = network_message_router
	local rpc_messages = {
		"game_session_disconnect",
		"rpc_from_server_match_start",
		"rpc_good_bye",
		"rpc_from_server_end_of_round_client_rewards",
		"rpc_from_server_teleport_player",
		"rpc_from_server_teleport_ai"
	}

	self.network_message_router:register("client_running", self, unpack(rpc_messages))

	local peers_to_add, peers_to_add_n = self.game_lobby:members()
	self.gamesession_peers = NetworkGameSessionPeers.new(peers_to_add, peers_to_add_n)
	self.gamesession_peer_informations = NetworkGameSessionPeerInformations.new()
end

GameStateIngameClientRunning.rpc_from_server_teleport_player = function (self, peer_id, teleportee_peer_id, pos)
	local unit = NetworkGameSessionPeerInformations.get_unit_by_peer(self.gamesession_peer_informations, teleportee_peer_id)

	if Unit.alive(unit) then
		local player_ext = EntityAux.extension(unit, "player")

		if player_ext then
			if NetworkUnit.is_local_unit(unit) or pdNetworkServerUnit.owning_peer_is_self(unit) then
				Mover.set_position(Unit.mover(unit), pos)
			else
				Unit.teleport_local_position(unit, 0, pos)
			end

			self.event_delegate:trigger("event_unit_teleport", unit, pos, Unit.local_rotation(unit, 0))

			local unit_pos = Unit.world_position(unit, 0)
			local effect_manager = self.effect_manager
			local world = self.game_world
			local timpani_world = World.timpani_world(world)

			World.create_particles(world, "content/particles/magicks/teleport_forced_appear", pos, Quaternion.identity())
			World.create_particles(world, "content/particles/magicks/teleport_disappear", unit_pos, Quaternion.identity())
			TimpaniWorld.trigger_event(timpani_world, "play_magick_teleportb_event", pos)
			TimpaniWorld.trigger_event(timpani_world, "misc_teleport", pos)
			TimpaniWorld.trigger_event(timpani_world, "play_magick_teleporta_event", unit_pos)
			TimpaniWorld.trigger_event(timpani_world, "play_magick_teleport_end_event", pos)
		end
	end
end

GameStateIngameClientRunning.rpc_from_server_teleport_ai = function (self, peer_id, go_id, pos)
	local unit = self.unit_storage:unit(go_id)

	if Unit.alive(unit) then
		local unit_pos = Unit.world_position(unit, 0)
		local effect_manager = self.effect_manager
		local world = self.game_world
		local timpani_world = World.timpani_world(world)

		World.create_particles(world, "content/particles/magicks/teleport_appear", pos, Quaternion.identity())
		World.create_particles(world, "content/particles/magicks/teleport_disappear", unit_pos, Quaternion.identity())
		TimpaniWorld.trigger_event(timpani_world, "play_magick_teleportb_event", pos)
		TimpaniWorld.trigger_event(timpani_world, "play_magick_teleporta_event", unit_pos)
		Unit.set_local_position(unit, 0, pos)
		self.event_delegate:trigger("event_unit_teleport", unit, pos, Unit.local_rotation(unit, 0))
	end
end

GameStateIngameClientRunning.rpc_from_server_match_start = function (self, sender)
	self.peers_to_disconnect = table_aux.table_to_map(GameSession.peers(self.game_session), {})
	self.parent.peers_to_disconnect = self.peers_to_disconnect
end

GameStateIngameClientRunning.game_session_disconnect = function (self, host_id)
	if self.been_disconnected_from_gamesession then
		return
	end

	print("")

	local in_session = GameSession.in_session(self.game_session)

	printf("[game_session_disconnect] self has been disconnected from host '%s'. kicked or host left. is in session %s", tostring(host_id), tostring(not not in_session))
	print("")

	self.been_disconnected_from_gamesession = true
	self.unit_spawner.KEEP_GAMEOBJECT_UNITS_ON_DESTROY = true
end

GameStateIngameClientRunning.dev_game_session_disconnect = function (self, sender)
	return
end

GameStateIngameClientRunning.on_peer_disconnect_client_pd = function (self, left_peers, left_peers_n)
	for i = 1, left_peers_n, 1 do
		self.gamesession_host_left = self.gamesession_host_left or self.server_peer_id == left_peers[i]
	end
end

GameStateIngameClientRunning.setup_network_synchronizers = function (self)
	local game_detail_synchronizer_state_data = ApplicationStorage.get_data_clear("network", "client", "game_detail_synchronizer_state_data")
	local game_detail_synchronizer = NetworkGameDetailSynchronizer(self.network_message_router, false, self.event_delegate)

	if game_detail_synchronizer_state_data then
		game_detail_synchronizer:restore_state_data(game_detail_synchronizer_state_data)
	else
		game_detail_synchronizer:set_is_peer()
		game_detail_synchronizer:set_server_peer_id(self.server_peer_id)
	end

	self.game_detail_synchronizer = game_detail_synchronizer
	self.start_game_synchronizer = NetworkGameStartSynchronizerClient(self.network_message_router, game_detail_synchronizer, self.gamesession_peers)
end

GameStateIngameClientRunning.setup_peer_transitions = function (self)
	self.lobby_peers_transitions = NetworkGameSessionPeersTransitions.new(self.game_lobby:members())
	self.gamesession_peers_transitions = NetworkGameSessionPeersTransitions.new(GameSession.peers(self.game_session))
end

local function make_client_state_block(self)
	return {
		parent = self,
		server_peer_id = self.server_peer_id,
		level_name = self.level_name,
		network_message_router = self.network_message_router,
		game_lobby = self.game_lobby,
		chat_handler = self.chat_handler,
		game_detail_synchronizer = self.game_detail_synchronizer,
		start_game_synchronizer = self.start_game_synchronizer,
		is_dedicated_server = self.server_is_dedicated_server,
		gamesession_peers = self.gamesession_peers,
		gamesession_peer_informations = self.gamesession_peer_informations
	}
end

GameStateIngameClientRunning.setup_ingame_statemachine = function (self)
	local state_param_block = make_client_state_block(self)
	state_param_block.hud_manager = self.hud_manager
	state_param_block.event_delegate = self.event_delegate
	state_param_block.team_manager = self.team_manager
	state_param_block.network_transport = self.network_transport
	state_param_block.hide_lobby = self.gamemode.gamemode_configuration.client.hide_lobby
	state_param_block.gamemode = self.gamemode
	state_param_block.gamemode_title = self.gamemode.gamemode_configuration.client.title
	state_param_block.is_developer = self.is_developer
	state_param_block.world = self.game_world
	state_param_block.is_spectator = self.is_spectator
	state_param_block.persistence_client = self.persistence_client
	state_param_block.transaction_handler = self.transaction_handler
	local start_state = StateInGameLobby
	self.ingame_statemachine = StateMachine(start_state, state_param_block)
end

GameStateIngameClientRunning.on_enter = function (self, param_block)
	self.LAN_MODE = NetworkHandler.backend_type == "LAN"
	self.parent = param_block.parent
	self.is_spectator = param_block.is_spectator
	self.server_is_dedicated_server = param_block.is_dedicated_server
	self.server_peer_id = assert(param_block.server_peer_id)
	self.own_peer_id = Network.peer_id()
	self.gamesession_guid = param_block.gamesession_guid
	self.level_name = assert(param_block.level_name)
	self.level_name_id = assert(NetworkLookup.levels[self.level_name])
	self.gameobject_notifier = assert(param_block.gameobject_notifier_from_server)
	self.game_session = Network.game_session()
	self.game_lobby = assert(param_block.game_lobby)
	local network_message_router = assert(param_block.network_event_delegate)
	self.network_message_router = network_message_router
	self.persistence_client = param_block.persistence_client
	self.login_server_handler = param_block.login_server_handler
	self.is_developer = self.persistence_client:get_data(Network.peer_id(), "developer")
	self.gamemode_timer = GameModeTimer(network_message_router)
	self.seen_peer_ids_map = {
		[self.server_peer_id] = true
	}
	self.wall_timer = pdWallTimer.new()
	self.event_delegate = EventDelegate()

	if self.login_server_handler then
		self.login_server_handler:set_event_delegate(self.event_delegate)
	end

	PlayerAssembly.init(self.network_message_router, self.event_delegate)
	MatchMakerInterface.init(self.network_message_router, self.event_delegate)

	self.nop_delegate = EventDelegate()

	self:register_events()
	self:setup_peer_transitions()
	self:setup_network(network_message_router)
	self:setup_network_synchronizers()
	self:setup_game_world()
	self:setup_game_viewport_camera()

	local gameobject_notifier = assert(param_block.gameobject_notifier)

	self:setup_network_game_handlers(gameobject_notifier)
	self:create_network_transport()
	self:setup_team_manager()

	self.gamemode = param_block.gamemode
	local disabled_persistence = PD_APPLICATION_PARAMETER["disable-persistence"]
	self.chat_system = param_block.chat_system

	if not param_block.chat_system and not disabled_persistence then
		cat_print_error("always", "Expected chat system to be initialized already. Chat won't work!")
	end

	if not self.chat_system then
		self.chat_system = ChatSystem()

		self.chat_system:login_fake_lan_user(Network.peer_id())
	end

	self.chat_system:set_network_router(network_message_router)

	self.chat_handler = ChatClientHandler(self.chat_system)

	self.chat_system:register_chat_handler(self.chat_handler, ChatAlias)
	self.chat_system:register_chat_handler(self.chat_handler, ChatTeam1Alias)
	self.chat_system:register_chat_handler(self.chat_handler, ChatTeam2Alias)

	if CurseVoiceChat.is_enabled() then
		CurseVoiceChat.init(self.event_delegate, PlayerAssembly, self.chat_system, self.team_manager, self.game_detail_synchronizer)
		CurseVoiceChat.set_current_state("Lobby")
		CurseVoiceChat.set_gamesession_id(self.gamesession_guid)
	end

	if not rawget(_G, "ui") then
		print("init global ui")

		local UIContext = require_bs("scripts/game/ui2/ui_context")

		rawset(_G, "ui", UIContext("gui", nil, false))
	end

	self.ui_renderer = ui.ui_renderer

	pdDebug.setup(self.game_world)

	local backend_type = NetworkHandler.backend_type

	if backend_type == "STEAM" and PDXIGS.initialized() and self.login_server_handler then
		self.transaction_handler = param_block.transaction_handler
	else
		self.transaction_handler = FakeTransactionHandler()
	end

	self.transaction_handler:set_gamesession_guid(self.gamesession_guid)
	self:setup_gui_manager()
	self:setup_hud_manager()
	self:setup_gamemode(param_block)
	self:setup_entity_systems()
	self:setup_ingame_statemachine(param_block)

	local lobby_members_on_enter, lobby_members_on_enter_n = self.game_lobby:members()

	self:handle_joined_lobby_peers(lobby_members_on_enter, lobby_members_on_enter_n)

	self.update_stage = "game_update"
	self.been_disconnected_from_gamesession = false
	self.been_in_gamesession = false
	self.peers_received_good_bye = {}
	self.parent.peers_received_good_bye = self.peers_received_good_bye
	self.previous_cursor_clip = Window.clip_cursor()

	Window.set_clip_cursor(DevelopmentSetting("ui_cursor_clip") ~= false and not DevelopmentSetting_bool("no_clip_cursor"))
	PlayerAssembly.set_client_state(NetworkLookup.assembly_member_status.IN_MATCH)
end

GameStateIngameClientRunning.update_terminate_external_connections = function (self, dt)
	if not self.LAN_MODE then
		local my_peer_id = self.own_peer_id
		local login_server_peer_id = (self.login_server_handler and self.login_server_handler.server_id) or "something that will never be equal to any peer-id"

		NetworkSystemAux.update_terminate_external_connections(dt, my_peer_id, login_server_peer_id)
	end
end

GameStateIngameClientRunning.register_events = function (self)
	local events = {
		"from_flow_unspawn_unit",
		"on_score_screen_continue",
		"game_over"
	}

	if self.LAN_MODE then
		events[#events + 1] = "on_peer_disconnect_client_pd"
	end

	self.event_delegate:register(self.ALIAS, self, unpack(events))
end

GameStateIngameClientRunning.from_flow_unspawn_unit = function (self, unit)
	local extra_text = nil
	local is_local_unit = NetworkUnit.is_local_unit(unit)

	if is_local_unit then
		self.entity_manager:mark_for_deletion(unit)

		extra_text = "LOCAL unit, marked it for deletion."
	else
		extra_text = "REMOTE unit, dismissing."
	end

	cat_printf_info_blue("ingame_client", "from_flow_unspawn_unit(%s) : %s", tostring(unit), extra_text)
end

GameStateIngameClientRunning.game_over = function (self, did_win)
	self.match_is_over = true
	self.wants_to_exit_game_timer = GameSettings.gameserver_shutdown_delay
	local lobby_members, lobby_members_n = self.game_lobby:members()
	local peers_in_game = {}

	print([[



SAVING MEMBERS FROM MATCH TO KEEP UP CONNECTION TO:]])

	for i = 1, lobby_members_n, 1 do
		peers_in_game[lobby_members[i]] = true

		print(tostring(lobby_members[i]))
	end

	print([[
END OF MEMBER LIST!!


]])
	rawset(_G, "LAST_GAME_LOBBY_MEMBERS", peers_in_game)
end

GameStateIngameClientRunning.setup_gamemode = function (self, param_block)
	local gamemode_configuration = ApplicationStorage.get_data_keep("network_gamemode_configuration")
	local gamemode_context = {
		server_peer_id = self.server_peer_id,
		own_peer_id = self.own_peer_id,
		network_message_router = self.network_message_router,
		level = self.level,
		world = self.game_world,
		level_name = self.level_name,
		level_name_id = self.level_name_id,
		game_lobby = self.game_lobby,
		game_server = self.game_server,
		entity_manager = self.entity_manager,
		unit_spawner = self.unit_spawner,
		unit_storage = self.unit_storage,
		network_transport = self.network_transport,
		event_delegate = self.event_delegate,
		gameobject_event_broadcaster = self.gameobject_event_broadcaster,
		is_dedicated_server = self.server_is_dedicated_server,
		team_manager = self.team_manager,
		gamesession_peers = self.gamesession_peers,
		gamemode_configuration = gamemode_configuration,
		game_detail_synchronizer = self.game_detail_synchronizer,
		gamesession_peer_informations = self.gamesession_peer_informations,
		hud_manager = self.hud_manager,
		persistence_client = self.persistence_client,
		chat_system = self.chat_system,
		login_server_handler = self.login_server_handler,
		game_state = param_block.parent,
		game_state_client = self,
		transaction_handler = self.transaction_handler,
		ui_renderer = self.ui_renderer,
		camera = self.camera,
		camera_unit = self.camera_unit,
		gui_manager = self.gui_manager,
		is_spectator = self.is_spectator,
		gamemode_timer = self.gamemode_timer,
		shading_environment_manager = self.shading_environment_manager,
		is_custom_match = PlayerAssembly.get_assembly_type() == NetworkLookup.assembly_types.CUSTOM_MATCH
	}

	if gamemode_configuration.gamemode_type == "koala" then
		self.gamemode = NetworkGameModeKoalaClientGame(gamemode_context)
	elseif gamemode_configuration.gamemode_type == "confusion" then
		self.gamemode = NetworkGameModeConfusionClientGame(gamemode_context)
	elseif gamemode_configuration.gamemode_type == "goldrush" then
		self.gamemode = NetworkGameModeGoldrushClientGame(gamemode_context)
	elseif gamemode_configuration.gamemode_type == "training_grounds" then
		require("scripts/game/player/task_manager")

		self.task_manager = TaskManager(self.network_transport, self.event_delegate, self.level, gamemode_context)
		gamemode_context.task_manager = self.task_manager
		self.gamemode = NetworkGameModeTrainingGroundsClientGame(gamemode_context)
	elseif gamemode_configuration.gamemode_type == "melee" then
		self.gamemode = NetworkGameModeMeleeClientGame(gamemode_context)
	elseif gamemode_configuration.gamemode_type == "kingofthehill" then
		self.gamemode = NetworkGameModeKingofthehillClientGame(gamemode_context)
	elseif gamemode_configuration.gamemode_type == "duel" then
		self.gamemode = NetworkGameModeDuelClientGame(gamemode_context)
	elseif gamemode_configuration.gamemode_type == "arena" then
		self.gamemode = NetworkGameModeArenaClientGame(gamemode_context)
	elseif gamemode_configuration.gamemode_type == "training" then
		require("scripts/game/player/task_manager")

		self.task_manager = TaskManager(self.network_transport, self.event_delegate, self.level, gamemode_context)
		gamemode_context.task_manager = self.task_manager

		self.task_manager:start_task(1)

		self.gamemode = NetworkGameModeTrainingClientGame(gamemode_context)
	else
		cat_print_error("always", "Unknown gamemode %s", tostring(gamemode_configuration.gamemode_type))
		assert(false)
	end
end

GameStateIngameClientRunning.setup_team_manager = function (self)
	local hosting = false
	local gamemode_configuration = ApplicationStorage.get_data_keep("network_gamemode_configuration")
	local team_manager = TeamManager(hosting, self.network_message_router, nil, nil, gamemode_configuration.client.num_teams)
	self.team_manager = team_manager
end

GameStateIngameClientRunning.setup_hud_manager = function (self)
	local gamemode_configuration = ApplicationStorage.get_data_keep("network_gamemode_configuration")
	local level_settings = LevelSettings[self.level_name]
	local hud_manager_create_context = {
		world = self.game_world,
		ui_renderer = self.ui_renderer,
		team_manager = self.team_manager,
		event_delegate = self.event_delegate,
		own_peer_id = self.own_peer_id,
		server_id = self.server_peer_id,
		entity_manager = self.entity_manager,
		gamemode = self.gamemode,
		gamemode_configuration = gamemode_configuration,
		network_message_router = self.network_message_router,
		level_settings = level_settings,
		game_detail_synchronizer = self.game_detail_synchronizer,
		gamesession_peer_informations = self.gamesession_peer_informations,
		persistence_client = self.persistence_client,
		chat_handler = self.chat_handler,
		is_spectator = self.is_spectator,
		transaction_handler = self.transaction_handler
	}
	self.hud_manager = HudManager(hud_manager_create_context)
end

GameStateIngameClientRunning.setup_gui_manager = function (self)
	local gui_settings = {
		bar_uv_scale = true,
		bar_offset = 20,
		bar_texture = "hud_health_bar_character_fill",
		bar_back_texture = "hud_health_bar_character",
		bar_texture_size = {
			52,
			6
		},
		bar_back_texture_size = {
			64,
			16
		},
		bar_size = {
			64,
			16
		},
		vertical_bar_size = {
			16,
			64
		},
		vertical_bar_texture_size = {
			6,
			58
		},
		vertical_bar_back_texture_size = {
			16,
			64
		},
		font = UISettings.name_font,
		font_path = UISettings.name_font_path,
		font_material = UISettings.name_font_material,
		font_size = UISettings.name_font_size
	}
	local gui_template = {
		"material",
		"content/gui/materials/hud",
		"material",
		gui_settings.font_path,
		"material",
		"content/gui/fonts/linux_biolinum_bold_outline_10",
		"immediate"
	}
	local gui_manager_create_context = {
		world = self.game_world,
		ui_renderer = self.ui_renderer,
		camera = self.camera,
		camera_unit = self.camera_unit,
		gui_template = gui_template,
		settings = gui_settings
	}
	self.gui_manager = GuiManager(gui_manager_create_context)
end

GameStateIngameClientRunning.create_network_transport = function (self)
	local server_is_dedicated_server = self.server_is_dedicated_server
	local transport_is_server = false
	local pd_network_transport = pdNetworkTransportArena(self.event_delegate, self.gamesession_peers, self.unit_storage, self.network_message_router, self.server_peer_id, server_is_dedicated_server, transport_is_server)
	self.network_transport = pd_network_transport
end

GameStateIngameClientRunning.setup_game_world = function (self)
	local gravity = Vector3(0, 0, -19.64)
	local game_world = pdWorldAux.new_world("CLIENT_GAME_WORLD")
	local game_world_timpani_world = World.timpani_world(game_world)
	local game_world_level_callback = LevelCallback()

	game_world_level_callback:register_level_callback(self)
	World.set_flow_callback_object(game_world, game_world_level_callback)

	local physics_world = World.physics_world(game_world)

	PhysicsWorld.set_gravity(physics_world, gravity)

	self.game_world = game_world
	self.game_world_level_callback = game_world_level_callback
	local level_settings = LevelSettings[self.level_name]
	local level_resource_path = level_settings.level_name
	local level = World.load_level(game_world, level_resource_path)
	self.level = level
	self.shading_environment_manager = ShadingEnvironmentManager(game_world, level)
	local spawn_background = false

	if spawn_background then
		Level.spawn_background(level)
	end
end

GameStateIngameClientRunning.setup_game_viewport_camera = function (self)
	local viewport_template = "default"
	self.viewport = Application.create_viewport(self.game_world, viewport_template)

	Resolution.register_viewport(self.viewport)

	local camera_position = Vector3(0, 50, 0)
	local look_at_pos = Vector3(0, 0, 0)
	local look_dir = Vector3.normalize(look_at_pos - camera_position)
	local camera_orientation = Quaternion.look(look_dir)
	local camera_pose = Matrix4x4.from_quaternion_position(camera_orientation, camera_position)
	local camera_unit_resource = "foundation/units/camera/camera"
	self.camera_unit = World.spawn_unit(self.game_world, camera_unit_resource, camera_pose)
	self.camera = Unit.camera(self.camera_unit, "camera")

	Camera.set_near_range(self.camera, 0.01)
	Camera.set_far_range(self.camera, 1000)

	self.camera_controller = pdCameraControllerFreeFlight.new(self.camera, self.camera_unit)

	pdCameraControllerFreeFlight.update(self.camera_controller, 0.1)
end

GameStateIngameClientRunning.setup_network_game_handlers = function (self, gameobject_notifier)
	local network_message_router = self.network_message_router
	local unit_storage = NetworkUnitStorage()
	local entity_manager = EntityManager()
	local gameobject_event_broadcaster = NetworkGameEventBroadcaster()
	local go_types = require("scripts/game/network/network_game_object_types")
	local go_initializers = require("scripts/game/network/network_game_object_initializers")
	local unit_spawner = pdNetworkUnitSpawner(self.game_world, self.level, self.event_delegate, entity_manager, unit_storage, network_message_router, gameobject_event_broadcaster, go_types, go_initializers, "client")

	unit_spawner:set_gameobject_notifier(gameobject_notifier)

	local gameobject_initializer_context = {
		lars = true,
		is_client = true,
		game_session = self.game_session,
		own_peer_id = self.own_peer_id
	}

	unit_spawner:set_gameobject_initializer_context(gameobject_initializer_context)

	local unit_extension_functor = get_unit_extension_functor_client

	entity_manager:set_get_unit_extension_functor(unit_extension_functor)
	entity_manager:set_unit_deletion_handler(unit_spawner)

	self.gameobject_event_broadcaster = gameobject_event_broadcaster
	self.entity_manager = entity_manager
	self.unit_storage = unit_storage
	self.unit_spawner = unit_spawner
end

GameStateIngameClientRunning.setup_entity_systems = function (self)
	local world = self.game_world
	local entity_manager = self.entity_manager
	local unit_spawner = self.unit_spawner
	local player_variable_manager = PlayerVariableManager()
	local systems_creation_context = {
		SERVER = false,
		CLIENT = true,
		state = self,
		world = world,
		ui_renderer = self.ui_renderer,
		entity_manager = entity_manager,
		unit_spawner = unit_spawner,
		unit_storage = self.unit_storage,
		event_delegate = self.event_delegate,
		network_message_router = self.network_message_router,
		network_transport = self.network_transport,
		level = self.level,
		level_name = self.level_name,
		own_peer_id = self.own_peer_id,
		server_peer_id = self.server_peer_id,
		is_server = self.own_peer_id == self.server_peer_id,
		gamesession_peers = self.gamesession_peers,
		gamesession_peer_informations = self.gamesession_peer_informations,
		game_detail_synchronizer = self.game_detail_synchronizer,
		gameobject_event_broadcaster = self.gameobject_event_broadcaster,
		team_manager = self.team_manager,
		hud_manager = self.hud_manager,
		gui_manager = self.gui_manager,
		game_camera = self.camera,
		game_camera_unit = self.camera_unit,
		shading_environment_manager = self.shading_environment_manager,
		player_variable_manager = player_variable_manager,
		gamemode = self.gamemode,
		is_spectator = self.is_spectator
	}
	local entity_systems_bag = EntitySystemBagClient(world, entity_manager, unit_spawner)

	entity_systems_bag:do_initialize_systems(systems_creation_context)
	entity_systems_bag:finalize_setup()

	self.entity_systems_bag = entity_systems_bag
end

GameStateIngameClientRunning.spawn_unit = function (self, unit)
	printf("[ingame_client] spawn_unit %s", tostring(unit))
end

GameStateIngameClientRunning.unspawn_unit = function (self, unit)
	printf("[ingame_client] unspawn_unit %s", tostring(unit))
end

local function print_notifications(gameobject_list, gameobject_list_n, prefix, tag)
	if gameobject_list_n == 0 then
		return
	end

	local s = "[" .. prefix .. "] gameobject_notification_type [" .. tag .. "]"

	for i = 1, gameobject_list_n, 2 do
		print(s, gameobject_list[i], gameobject_list[i + 1])
	end
end

GameStateIngameClientRunning.handle_gameobject_notifications = function (self)
	local unit_spawner = self.unit_spawner
	local unit_storage = self.unit_storage
	local entity_manager = self.entity_manager
	local gameobject_notifier = self.gameobject_notifier
	local created_gameobject_ids, created_gameobject_ids_n = gameobject_notifier:created_gameobjects()

	for c = 1, created_gameobject_ids_n, 2 do
		unit_spawner:game_object_created(created_gameobject_ids[c], created_gameobject_ids[c + 1])
	end

	local destroyed_gameobject_ids, destroyed_gameobject_ids_n = gameobject_notifier:destroyed_gameobjects()

	for d = 1, destroyed_gameobject_ids_n, 2 do
		local go_id = destroyed_gameobject_ids[d]
		local sender = destroyed_gameobject_ids[d + 1]
		local unit = unit_storage:unit(go_id)
		local removed_extension = entity_manager:remove_extension(unit, "network_synced")
		removed_extension = entity_manager:remove_extension(unit, "network_client_husk")

		cat_printf_blue("gameobject_notifications", "[CLIENT] adding go_id(%d) for deletion at update_index(%d) @current_update_index %d, delete_index %d", go_id, UPDATE_INDEX, self.current_update_index, self.delete_index)
	end

	local delayed_destroyed_gameobject_ids = self.delayed_destroyed_gameobject_ids[self.delete_index]

	pdArrayAux.copy_from_table(delayed_destroyed_gameobject_ids, destroyed_gameobject_ids, destroyed_gameobject_ids_n)
	gameobject_notifier:clear_gameobjects()
end

GameStateIngameClientRunning.handle_delayed_gameobject_notifications = function (self)
	local unit_spawner = self.unit_spawner
	local delayed_destroyed_gameobject_ids = self.delayed_destroyed_gameobject_ids[self.current_update_index]
	local destroyed_gameobject_ids, destroyed_gameobject_ids_n = pdArray.data(delayed_destroyed_gameobject_ids)

	for d = 1, destroyed_gameobject_ids_n, 2 do
		local go_id = destroyed_gameobject_ids[d]
		local sender = destroyed_gameobject_ids[d + 1]

		unit_spawner:game_object_destroyed(go_id, sender)
		cat_printf_blue("gameobject_notifications", "[CLIENT] deleting go_id(%d) at update_index(%d) @current_update_index %d, delete_index %d", go_id, UPDATE_INDEX, self.current_update_index, self.delete_index)
	end

	pdArray.set_empty(delayed_destroyed_gameobject_ids)
end

GameStateIngameClientRunning.freen_debug_update = function (self, dt)
	if not DevelopmentSetting_bool("freen_is_mupping_around") then
		return
	end

	if rawget(_G, "FREEN_TIMER") then
		self.fml_counter = (self.fml_counter or 0) + dt
		self.fml_counter_wall = (self.fml_counter_wall or 0) + self.wall_timer.delta_time
		local wall_greater = self.fml_counter < self.fml_counter_wall
		local diff = nil

		if wall_greater then
			diff = self.fml_counter_wall - self.fml_counter
		else
			diff = self.fml_counter - self.fml_counter_wall
		end

		pdDebug.text("FML TIME [%.3f] - WALL [%.3f] - DIFF [%.3f] - GREATEST [%s]", self.fml_counter, self.fml_counter_wall, diff, (wall_greater and "WALL") or "DT")
	end

	if false and Mouse_down("right") then
		pdCameraControllerFreeFlight.update(self.camera_controller, dt)
	end

	if Keyboard_pressed("b") and not self.freen_left_gamesession then
		self.freen_left_gamesession = true

		GameSession.leave(self.game_session)
		print("FREEN_LEFT_GAMESESSION")
	end
end

GameStateIngameClientRunning.update_world_entity_systems = function (self, dt)
	local entity_systems_update_context = self.entity_systems_update_context
	local game_world = self.game_world
	local gamemode = self.gamemode
	local entity_systems_bag = self.entity_systems_bag
	local wall_timer = self.wall_timer
	entity_systems_update_context.current_wall_time = wall_timer.current_time
	entity_systems_update_context.wall_delta_time = wall_timer.delta_time

	gamemode:pre_update(dt)
	entity_systems_bag:pre_update(dt, entity_systems_update_context)
	gamemode:update(dt)
	entity_systems_bag:update(dt, entity_systems_update_context)
	World.update_animations(game_world, dt)
	World.update_scene(game_world, dt)
	gamemode:post_update(dt)
	entity_systems_bag:post_update(dt, entity_systems_update_context)
end

GameStateIngameClientRunning.pre_update = function (self, dt)
	self.ingame_statemachine:pre_update(dt)
end

GameStateIngameClientRunning.post_update = function (self, dt)
	self.ingame_statemachine:post_update(dt)
end

GameStateIngameClientRunning.handle_server_disconnect = function (self)
	if not self.LAN_MODE then
		Network.shutdown_game_session()
	end

	self.start_game_synchronizer:clear_game_session()

	self.game_session = nil

	if not self.game_lobby.left then
		self.game_lobby:leave_lobby()
	else
		print(">>> update_server_lobby_connection ALREADY LEFT game lobby!")
	end

	local peers, peers_n = NetworkGameSessionPeers.peers(self.gamesession_peers)
	local saved_peers_array = self.scratch_arrays[1]

	pdArrayAux.copy_from_table(saved_peers_array, peers, peers_n)

	local saved_peers, saved_peers_n = pdArray.data(saved_peers_array)

	for i = 1, saved_peers_n, 1 do
		local peer_id = saved_peers[i]

		NetworkGameSessionPeers.remove_peer_if_present(self.gamesession_peers, peer_id)
		printf("[CLIENT] handle server disconnected. removing peer_id '%s'", peer_id)
		self.team_manager:remove_peer(peer_id)
	end

	self.game_detail_synchronizer:remove_peers(saved_peers, saved_peers_n)
	self.event_delegate:trigger("on_peer_disconnect_client_pd", saved_peers, saved_peers_n)

	if getmetatable(self.ingame_statemachine.state) == StateInGameLobby then
		self.event_delegate:trigger("on_gameserver_disconnect", "lobby")
	else
		self.event_delegate:trigger("on_gameserver_disconnect", (self.update_stage == "match_over" and "match_over") or "running")
	end

	if self.update_stage ~= "disconnected" then
		print("[CLIENT] UPDATE_SERVER_DISCONNECT -> setting update stage to disconnected")

		self.update_stage = "disconnected"

		self.hud_manager:set_round_has_ended(true)

		if not self.match_is_over and not self.explicit_exit_request then
			self.transaction_handler:post_telemetry(Network.peer_id(), "error", "errorname", "gameserver_error_connection_lost")
		end
	end
end

GameStateIngameClientRunning.update_server_lobby_connection = function (self)
	if self.server_has_disconnected then
		return
	end

	local wants_to_exit_game = self.wants_to_exit_game
	local game_session = self.game_session
	local was_in_gamesession = self.is_in_gamesession
	self.is_in_gamesession = GameSession.in_session(game_session)

	if self.LAN_MODE and self.gamesession_host_left then
		self.is_in_gamesession = false
	end

	local host_has_disconnected = false

	if not was_in_gamesession and self.is_in_gamesession then
		self.has_been_in_gamesession = true
		local game_session_host = GameSession.game_session_host(game_session)

		printf(">>>>>> SELF ADDED TO GAMESESSION, HOST -> %s", game_session_host)
	end

	if was_in_gamesession and not self.is_in_gamesession then
		print(">>>>>> SELF REMOVED FROM GAMESESSION")
		self.start_game_synchronizer:clear_game_session()

		host_has_disconnected = true
	end

	local host_error = GameSession.host_error(game_session)

	if host_error then
		print("HOST ERROR!!!")
		GameSession.disconnect_from_host(game_session)
	end

	local been_disconnected_from_gamesession = self.been_disconnected_from_gamesession

	self.game_lobby:update()

	local game_lobby_failed = self.game_lobby.failed

	if self.LAN_MODE then
		local lobby_host = self.game_lobby.lobby_host
		local self_is_lobby_host = lobby_host == self.own_peer_id

		if self.server_peer_id ~= lobby_host and self_is_lobby_host then
			game_lobby_failed = true
		end
	end

	if not self.has_handled_gamesession_leave and (wants_to_exit_game or been_disconnected_from_gamesession or game_lobby_failed) then
		if self.has_been_in_gamesession then
			if been_disconnected_from_gamesession then
			elseif game_lobby_failed then
				print("CLIENT PLAIN LEAVE GAMESESSION")
				GameSession.disconnect_from_host(game_session)
			else
				print("CLIENT SENDING LEAVE TO HOST")
				GameSession.leave(game_session)
			end
		end

		self.has_handled_gamesession_leave = true
	end

	if self.has_handled_gamesession_leave and not self.handled_server_disconnect then
		local do_disconnect_logic = self.LAN_MODE

		if self.has_been_in_gamesession then
			if self.is_in_gamesession == false or game_lobby_failed then
				do_disconnect_logic = true

				printf("[CLIENT] disconnecting from host and peers. in gamesession %s, lobby failed %s", tostring(self.is_in_gamesession), tostring(game_lobby_failed))
			end
		else
			do_disconnect_logic = true
		end

		if do_disconnect_logic then
			self.handled_server_disconnect = true

			print("!!!!!!!!!!!!!!!ALL SAID AND DONE!!!!!!!")

			if self.LAN_MODE == false then
				self:handle_server_disconnect()
			end

			self.server_has_disconnected = true
		end
	end
end

local empty_input_data = {}
local _show_ping_data = true
local last_ping_value = "0"

local function format_ping(input)
	if string.len(input) >= 5 then
		return input:sub(1,5)
	end
	return input
end

GameStateIngameClientRunning.update = function (self, dt)
	if self.wants_to_exit_game_timer then
		self.wants_to_exit_game_timer = self.wants_to_exit_game_timer - dt

		if self.wants_to_exit_game_timer < 0 then
			self.wants_to_exit_game_timer = nil
			self.wants_to_exit_game = true
		end
	end
	
	if Keyboard_pressed("0") then
		_show_ping_data = not _show_ping_data
	end
	--pdDebug.text("Injected")
	if _show_ping_data then
		pdDebug.text("Ping: " .. last_ping_value .. " Packet Loss: " .. tostring(self.packet_loss))-- .. " FPS: " .. tostring(self.fps_average))
	end

	local game_session = Network.game_session()
	local in_session = false

	if game_session then
		in_session = GameSession.in_session(game_session)
	end

	pdWallTimer.tick(self.wall_timer)

	if self.transaction_handler then
		self.transaction_handler:update()
	end

	self.gamemode_timer:update(dt)

	local input_data = nil

	if self.ingame_statemachine.state.input_data and self.ingame_statemachine.state.input_data.input_data then
		input_data = self.ingame_statemachine.state.input_data.input_data
	else
		input_data = empty_input_data
	end

	self:set_update_index()

	self.fps_num_frames = self.fps_num_frames + 1
	self.fps_elapsed_time = self.fps_elapsed_time + dt

	if self.fps_elapsed_time > 1 then
		self.fps_average = self.fps_num_frames / self.fps_elapsed_time
		self.fps_num_frames = 0
		self.fps_elapsed_time = 0
	end

	local fps_counter_color = (1 / dt < 60 and Color(255, 0, 0)) or Color(0, 255, 0)
	
	self.time_to_send_telemetry = self.time_to_send_telemetry - dt
	if self.time_to_send_telemetry <= 0 and self.server_peer_id then
		self.ping_ms = Network.ping(self.server_peer_id) * 1000
		self.packet_loss = (Network.packet_loss and Network.packet_loss(self.server_peer_id)) or 0
		local telemetry_plist = {
			"server_pid",
			self.server_peer_id,
			"ping_ms",
			self.ping_ms,
			"packet_loss",
			self.packet_loss,
			"client_fps",
			self.fps_average
		}
		last_ping_value = format_ping(tostring(self.ping_ms))
		--pdDebug.text("Ping: " .. tostring(telemetry_plist.ping_ms) .. " Packete Loss: " .. tostring(telemetry_plist.packet_loss) .. " FPS: " .. tostring(telemetry_plist.fps_average))
		--print("FOUND Ping: ")-- .. tostring(telemetry_plist.ping_ms) .. " Packete Loss: " .. tostring(telemetry_plist.packet_loss) .. " FPS: " .. tostring(telemetry_plist.fps_average))

		cat_printf_info_blue("always", "[perf] Client performance: %s=%s\t%s=%.0f\t%s=%.2f\t%s=%.1f", unpack(telemetry_plist))
		self.transaction_handler:post_gamesession_telemetry(Network.peer_id(), "performace", unpack(telemetry_plist))

		self.time_to_send_telemetry = TIME_BETWEEN_PING_TELEMETRY
	--else
		--pdDebug.text("timer not expired yet: " .. tostring(self.time_to_send_telemetry))
	end

	pdDebug.cond_color_text(DevelopmentSetting_bool("show_fps_counter"), fps_counter_color, sprintf("FPS: %.1f", self.fps_average))

	if self.server_has_disconnected then
		flow_set_callback_delegate(self.nop_delegate)
	else
		flow_set_callback_delegate(self.event_delegate)
	end

	self:handle_delayed_gameobject_notifications()
	self:handle_gameobject_notifications()
	NetworkWrapper.update_receive(dt, self.network_message_router)
	self:handle_delayed_gameobject_notifications()
	self:update_server_lobby_connection()

	local server_has_disconnected = self.server_has_disconnected
	local connected_to_server = not server_has_disconnected

	if connected_to_server then
		self:update_peer_transitions()
	end

	self:freen_debug_update(dt)
	self.chat_system:update(dt)

	local is_kicked = self.game_detail_synchronizer.kicked_reason

	if is_kicked then
		self.parent.is_kicked = is_kicked
		self.game_detail_synchronizer.kicked_reason = nil
	end

	if self.go_to_menu then
		self:transition_to_menu()
	end

	if self.task_manager then
		self.task_manager:update(dt)
	end

	self.previous_game_state = self.ingame_statemachine.state

	self.ingame_statemachine:update(dt)

	if CurseVoiceChat.is_enabled() and self.ingame_statemachine.state ~= self.previous_game_state then
		if self.ingame_statemachine.state.lobby_screen then
			CurseVoiceChat.set_current_state("Lobby")
		else
			CurseVoiceChat.set_current_state("InGame")
		end
	end

	if self.update_stage == "game_update" then
		if self.server_has_disconnected then
			self.update_stage = "disconnected"

			self.hud_manager:set_round_has_ended(true)
			self.transaction_handler:post_telemetry(Network.peer_id(), "error", "errorname", "gameserver_error_connection_lost")
			print("[CLIENT] been disconnected from server in game_update stage")
		elseif self.match_is_over then
			self.update_stage = "match_over"
		else
			self:update_world_entity_systems(dt)
			assert(connected_to_server)
			self.hud_manager:update(dt, connected_to_server)
		end
	end
	
	if self.update_stage == "disconnected" then
		World.update_animations(self.game_world, dt)
		World.update_scene(self.game_world, dt)

		for _, system_data in ipairs(self.entity_systems_bag.systems) do
			local system_name = system_data.NAME

			if system_name == "minimap_system_client" then
				system_data:update(dt)

				break
			end
		end

		if not self.ingame_statemachine.state.lobby_screen then
			if self.exit_stats_screen then
				self:transition_to_menu()
			elseif is_kicked then
				self:transition_to_menu()
			end
		end

		self.hud_manager:update(dt, connected_to_server)
	elseif self.update_stage == "match_over" then
		if not self.update_entity_system_once_at_match_over then
			self.update_entity_system_once_at_match_over = true

			self:update_world_entity_systems(dt)
		else
			World.update_animations(self.game_world, dt)
			World.update_scene(self.game_world, dt)

			for _, system_data in ipairs(self.entity_systems_bag.systems) do
				local system_name = system_data.NAME

				if system_name == "minimap_system_client" then
					system_data:update(dt)

					break
				end
			end
		end

		if self.exit_stats_screen then
			self:transition_to_menu()
		end

		self.hud_manager:update(dt, connected_to_server)
	end

	self.shading_environment_manager:update(dt)
	Network.update_transmit()
	pdDebug.update(dt)
	flow_set_callback_delegate(nil)
end

GameStateIngameClientRunning.handle_left_game_session_peers = function (self, left, left_n)
	if left_n == 0 then
		return
	end

	self.game_detail_synchronizer:remove_peers(left, left_n)
	self.event_delegate:trigger("on_peer_disconnect_client_pd", left, left_n)

	local team_manager = self.team_manager

	for i = 1, left_n, 1 do
		local left_peer_id = left[i]

		team_manager:remove_peer(left_peer_id)

		local was_removed = NetworkGameSessionPeers.remove_peer_if_present(self.gamesession_peers, left_peer_id)

		printf("[CLIENT] '%s' left game_session. removed from gamesession peers : %s", left_peer_id, tostring(was_removed):upper())

		self.seen_peer_ids_map[left_peer_id] = nil
	end
end

GameStateIngameClientRunning.handle_left_lobby_peers = function (self, left, left_n)
	if left_n == 0 then
		return
	end

	self.game_detail_synchronizer:remove_peers(left, left_n)
	self.event_delegate:trigger("on_peer_disconnect_client_pd", left, left_n)

	local team_manager = self.team_manager

	for i = 1, left_n, 1 do
		local left_peer_id = left[i]

		team_manager:remove_peer(left_peer_id)

		local was_removed = NetworkGameSessionPeers.remove_peer_if_present(self.gamesession_peers, left_peer_id)

		printf("[CLIENT] '%s' left lobby. removed from gamesession peers : %s", left_peer_id, tostring(was_removed):upper())

		self.seen_peer_ids_map[left_peer_id] = nil
	end
end

GameStateIngameClientRunning.handle_joined_game_session_peers = function (self, joined, joined_n)
	if joined_n == 0 then
		return
	end

	for j = 1, joined_n, 1 do
		local peer_id = joined[j]
		local was_added = NetworkGameSessionPeers.add_peer_if_not_present(self.gamesession_peers, peer_id)

		printf("[CLIENT] '%s' joined game_session. added to gamesession peers : %s", peer_id, tostring(was_added):upper())
		self.event_delegate:trigger("on_peer_joined_gamesession", peer_id)

		self.seen_peer_ids_map[peer_id] = true
	end
end

GameStateIngameClientRunning.handle_joined_lobby_peers = function (self, joined, joined_n)
	if joined_n == 0 then
		return
	end

	for j = 1, joined_n, 1 do
		local peer_id = joined[j]
		local was_added = NetworkGameSessionPeers.add_peer_if_not_present(self.gamesession_peers, peer_id)

		printf("[CLIENT] '%s' joined lobby. added to gamesession peers : %s", peer_id, tostring(was_added):upper())

		self.seen_peer_ids_map[peer_id] = true
	end
end

GameStateIngameClientRunning.destroy = function (self, application_shutdown)
	self.ingame_statemachine:destroy(application_shutdown)
end

GameStateIngameClientRunning.render = function (self)
	local game_world_shading_environment = self.shading_environment_manager.shading_environment

	Application.render_world(self.game_world, self.camera, self.viewport, game_world_shading_environment)

	local ignore_render = self.ingame_statemachine:render()

	if DevelopmentSetting_bool("no_world_rendering") then
		local gui = self.screen_gui or World.create_screen_gui(self.game_world, "immediate")
		self.screen_gui = gui

		Gui.rect(gui, Vector3(0, 0, 998), Vector2(Application.resolution()), Color(255, 0, 0))
	end
end

GameStateIngameClientRunning.on_exit = function (self, application_shutdown)
	if self.LAN_MODE == true then
		self:handle_server_disconnect()
	end

	if not application_shutdown then
		assert(self.game_lobby.left == true)
	end

	if self.task_manager then
		self.task_manager:destroy(self.event_delegate)
		self.task_manager:destroy(self.nop_delegate)
	end

	self.ingame_statemachine:destroy(application_shutdown)
	self.shading_environment_manager:destroy()
	self.entity_systems_bag:destroy()
	self.gamemode_timer:destroy()
	self.game_detail_synchronizer:destroy()
	self.start_game_synchronizer:destroy()
	self.hud_manager:destroy()
	self.chat_system:unregister_chat_handler(self.chat_handler, ChatTeam2Alias)
	self.chat_system:unregister_chat_handler(self.chat_handler, ChatTeam1Alias)
	self.chat_system:unregister_chat_handler(self.chat_handler, ChatAlias)

	self.chat_handler = nil

	self.chat_system:leave_rooms(CHAT_DESTINATION_ALL)
	self.chat_system:leave_rooms(CHAT_DESTINATION_TEAM)
	Resolution.unregister_viewport(self.viewport)

	if rawget(_G, "ui") then
		ui:destroy()
		rawset(_G, "ui", nil)
	end

	pdDebug.teardown()
	Window.set_clip_cursor(self.previous_cursor_clip)
	Application.release_world(self.game_world)
	self.gamemode:shutdown()
	PlayerAssembly.set_client_state(NetworkLookup.assembly_member_status.NOT_READY_FOR_MATCH)
end

GameStateIngameClientRunning.rpc_good_bye = function (self, sender)
	self.peers_received_good_bye[sender] = true
end

local handled_peers_map = {}

local function clear_handled_peers_map()
	for k, _ in pairs(handled_peers_map) do
		handled_peers_map[k] = nil
	end
end

local function add_peers_to_handled(peers, peers_n)
	for i = 1, peers_n, 1 do
		handled_peers_map[peers[i]] = true
	end
end

local filtered_peers_array = {}

local function filter_by_handled_peers_map(peers, peers_n)
	local n = 0

	for i = 1, peers_n, 1 do
		local peer_id = peers[i]

		if not handled_peers_map[peer_id] then
			n = n + 1
			filtered_peers_array[n] = peer_id
		end
	end

	return filtered_peers_array, n
end

local temp_leaving_set = pdSet.new()

GameStateIngameClientRunning.update_leaving_peers = function (self)
	local seen_peer_ids_map = self.seen_peer_ids_map
	local leaving_peers_set = temp_leaving_set

	pdSet.clear(leaving_peers_set)

	local scratch_arrays = self.scratch_arrays
	local left_game_session_peers, left_game_session_peers_n = NetworkGameSessionPeersTransitions.left(self.gamesession_peers_transitions)

	self:handle_left_game_session_peers(left_game_session_peers, left_game_session_peers_n)

	for i = 1, left_game_session_peers_n, 1 do
		local peer_id = left_game_session_peers[i]

		if seen_peer_ids_map[peer_id] then
			pdSet.insert(leaving_peers_set, peer_id)
		end
	end

	local left_lobby_peers, left_lobby_peers_n = NetworkGameSessionPeersTransitions.left(self.lobby_peers_transitions)
	local left_lobby_peers_array = scratch_arrays[1]

	pdArray.set_empty(left_lobby_peers_array)

	for i = 1, left_lobby_peers_n, 1 do
		local left_peer_id = left_lobby_peers[i]

		if seen_peer_ids_map[left_peer_id] and not pdSet.has(leaving_peers_set, left_peer_id) then
			pdArray.push_back(left_lobby_peers_array, left_peer_id)
		end
	end

	local non_handled_peer_ids, non_handled_peer_ids_n = pdArray.data(left_lobby_peers_array)

	self:handle_left_lobby_peers(non_handled_peer_ids, non_handled_peer_ids_n)
end

GameStateIngameClientRunning.update_joining_peers = function (self)
	clear_handled_peers_map()

	local joined_game_session_peers, joined_game_session_peers_n = NetworkGameSessionPeersTransitions.joined(self.gamesession_peers_transitions)

	self:handle_joined_game_session_peers(joined_game_session_peers, joined_game_session_peers_n)
	add_peers_to_handled(joined_game_session_peers, joined_game_session_peers_n)

	local joined_lobby_peers, joined_lobby_peers_n = NetworkGameSessionPeersTransitions.joined(self.lobby_peers_transitions)

	self:handle_joined_lobby_peers(joined_lobby_peers, joined_lobby_peers_n)
end

GameStateIngameClientRunning.update_peer_transitions = function (self)
	NetworkGameSessionPeersTransitions.update(self.gamesession_peers_transitions, GameSession.peers(self.game_session))

	local game_lobby = self.game_lobby

	if game_lobby.joined and not game_lobby.left then
		NetworkGameSessionPeersTransitions.update(self.lobby_peers_transitions, self.game_lobby.lobby:members())
	end

	self:update_leaving_peers()
	self:update_joining_peers()
end

GameStateIngameClientRunning.transition_to_menu = function (self)
	self.wants_to_exit_game = true

	if not self.server_has_disconnected then
		return
	end

	print("GameStateIngameClientRunning : ALL SAID AND DONE!")

	if not self.transaction_handler:empty() then
		print("EXITING WHILE STILL HAS PENDING/UNHANDLED TRANSACTIONS... LOL FAIL!")
	end

	self.parent.go_to_menu = true
	self.parent.is_winner = self.gamemode.is_winning_team
	self.parent.team_scores = self.gamemode.team_scores
	self.parent.end_of_round_client_rewards = self.end_of_round_client_rewards
end

GameStateIngameClientRunning.rpc_from_server_end_of_round_client_rewards = function (self, sender, reward_name, reward_type, reward_amount, reward_source)
	if not self.end_of_round_client_rewards then
		self.end_of_round_client_rewards = {}
	end

	self.end_of_round_client_rewards[#self.end_of_round_client_rewards + 1] = {
		name = reward_name,
		type = reward_type,
		amount = reward_amount,
		source = reward_source
	}
end

GameStateIngameClientRunning.on_score_screen_continue = function (self)
	self.exit_stats_screen = true
end

return

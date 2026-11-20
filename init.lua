package.path = package.path .. ";.\\mods\\Discord_rich_presence_noita\\lib\\?.lua"
package.cpath = package.cpath .. ";.\\mods\\Discord_rich_presence_noita\\bin\\?.dll"

dofile_once("mods/Discord_rich_presence_noita/lib/coroutines.lua")

local discordRPC = require("discordRPC")

local appId = "814077146904526858"

function discordRPC.ready(userId, username, discriminator, avatar)
	print(string.format("Discord: ready (%s, %s, %s, %s)", userId, username, discriminator, avatar))
end

function discordRPC.disconnected(errorCode, message)
	print(string.format("Discord: disconnected (%d: %s)", errorCode, message))
end

function discordRPC.errored(errorCode, message)
	print(string.format("Discord: error (%d: %s)", errorCode, message))
end

function discordRPC.joinGame(joinSecret)
	print(string.format("Discord: join (%s)", joinSecret))
end

function discordRPC.spectateGame(spectateSecret)
	print(string.format("Discord: spectate (%s)", spectateSecret))
end

function discordRPC.joinRequest(userId, username, discriminator, avatar)
	print(string.format("Discord: join request (%s, %s, %s, %s)", userId, username, discriminator, avatar))
	discordRPC.respond(userId, "yes")
end

local presence = {
	state = "Playing noita",
	details = "This is a rich presence test.",
	startTimestamp = os.time(),
	largeImageKey = "coverimage",
}

local rpc_initialized = false

local function firstToUpper(str)
	return str:gsub("^%l", string.upper)
end

local function get_biome_name(entity)
	local x, y = EntityGetTransform(entity)

	local current_biome = GameTextGetTranslatedOrNot( BiomeMapGetName(x, y) )

	if current_biome == "_EMPTY_" then
		current_biome = "Overworld"
	end

	local px, py = GetParallelWorldPosition(x, y)
	if px < 0 then
		current_biome = GameTextGet("$biome_east", current_biome)
	elseif px > 0 then
		current_biome = GameTextGet("$biome_west", current_biome)
	end

	return current_biome
end

function OnWorldPreUpdate()
	wake_up_waiting_threads(1)
end

GLOBAL_DATA = {
	biome_index = {
		
	},
	start_time = os.time(),
}

PRESENCE_CHECKLIST = {
	name = function() ---@return string
		return "Noita"
	end,
	type = function() ---@return integer
		return 0
	end,
	url = function() end, ---@return string?
	created_at = function(player) ---@return integer
		return 0
	end,
	timestamps = {
		start = function() ---@return integer?
			return GLOBAL_DATA.start_time
		end,
		["end"] = function() ---@return integer?
			return os.time()
		end,
	},
	application_id = function(player) ---@return integer|string
		return "814077146904526858"
	end,
	status_display_type = function(player) end, ---@return integer?
	details = function(player) ---@return string?
		local biome_name = get_biome_name(player)
		return "Biome: "..firstToUpper(biome_name)
	end,
	details_url = function(player) end, ---@return string?
	state = function(player)
		if not player then
			local polymorphed_entities = EntityGetWithTag("polymorphed")
			for _,entity_id in ipairs(polymorphed_entities or {}) do
				local game_stats_comp = EntityGetFirstComponent(entity_id, "GameStatsComponent")
				if game_stats_comp ~= nil then
					if ComponentGetValue2(game_stats_comp, "is_player") then
						return GameTextGetTranslatedOrNot("$log_polymorph") --polymorphed player found!
					end
				end
			end
			return "Dead!" --failed to find polymorphed player
		else
			local hp_mult = tonumber(MagicNumbersGetValue("GUI_HP_MULTIPLIER")) or 25

			for _, dmc in ipairs(EntityGetComponent(player, "DamageModelComponent") or {}) do
				local max_hp = math.floor(ComponentGetValue2(dmc, "max_hp") * hp_mult)
				local cur_hp = math.floor(ComponentGetValue2(dmc, "hp") * hp_mult)
				return GameTextGet("$hud_health", tostring(cur_hp), tostring(max_hp))
			end
		end

		---@diagnostic disable-next-line: unreachable-code
		return "Health: ??? / ???" --code is reachable if no enabled DMC is located on the player due to a mod or bug.
	end,
	state_url = function(player) end, ---@return string?
	emoji = function(player) end,
	party = function(player) end,
	assets = {
		large_image = function (player)
			local biome_name = get_biome_name(player)
			return biome_name:gsub("%s+", "_"):lower()
		end,
		large_text = function (player)
			local year,month,day = GameGetDateAndTimeUTC()
			local t = os.date("*t")
			local newgame_n = tonumber( SessionNumbersGetValue("NEW_GAME_PLUS_COUNT") )
			local seed = string.format("%d%02d%d", t.year, t.month, t.day)
			if StatsGetValue("world_seed") == seed and newgame_n == 0 then
				return "Daily run"
			elseif newgame_n == 0 then
				return "Regular run"
			else
				return "NG+ Cycle: "..tostring(newgame_n)
			end
			return "$menupause_gamemode"
		end,
		large_url = function (player) end,
		small_image = function (player)
			return "goldnugget"
		end,
		small_text = function (player)
			local wallet = EntityGetFirstComponent(player, "WalletComponent")
			if wallet ~= nil then
				local money = ComponentGetValue2(wallet, "money")
				return GameTextGet("$hud_gold", tostring(money))
			end
		end,
		small_url = function (player) end,
		invite_cover_image = function (player) end,
	},
	secrets = function(player) end,
	instance = function(player) end,
	flags = function(player) end,
	buttons = function(player) end,
}

local function update_discord()
	local player = EntityGetWithTag("player_unit")[1]

	local presence_changed
	local function update_presence(target, destination)
		if #target == 0 then
			for key, value in pairs(target) do
				local value_type = type(value)
				if value_type == "table" then
					destination[key] = destination[key] or {}
					update_presence(value, destination[key])
				else
					if value_type == "function" then value = value(player) end
					if type(value) == "string" then value = GameTextGetTranslatedOrNot(value) end
					if value ~= destination[key] then --
						presence_changed = true
						print("    " .. key .. ": " .. value)
						destination[key] = value
					end
				end
			end
		end
	end

	print("start")
	update_presence(PRESENCE_CHECKLIST, presence)
	print("end")

	if rpc_initialized then
		if presence_changed then
			discordRPC.updatePresence(presence)
		end
		discordRPC.runCallbacks()
	end
end

function OnPlayerSpawned( player_entity )
	discordRPC.initialize(appId, true)
	rpc_initialized = true
	async_loop(function()
		local success, error_msg = pcall(update_discord)
		if not success then
			print_error("Lua script failed in coroutine: " .. error_msg)
		end
		wait(60) --885 --60
	end)
end


--!strict
--[[
	FreeForAllService: drop-in FREE FOR ALL, always running in its own arena.

	  * Step on the FREE FOR ALL pad at the end of the hallway and you're
	    straight in: no queue, no minimum. Leave any time (LEAVE button or L).
	  * Everyone for themselves: anyone can hit anyone. After being
	    eliminated you come back after a short wait, away from other players.
	  * Rounds: first to EliminationsToWin (ModeConfig.FreeForAll) or the most
	    eliminations when the timer runs out wins. The winner gets a win
	    (and the victory bonus), then scores reset and the next round starts
	    in a different themed arena (Map/ThemedArenaBuilder), sized for how
	    many people are playing.
	  * It has its own arena far away from the team-match arena, so team
	    matches and free for all run at the same time.

	Players here have status "InMatch" and the "FreeForAll" attribute.
	MatchService asks this service who may shoot whom (isPlaying/canFire/
	canDamage). Shared state for the screen is on ReplicatedStorage.FreeForAllState.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local ModeConfig = require(Shared.Config.ModeConfig)
local MapConfig = require(Shared.Config.MapConfig)
local MatchState = require(Shared.Match.MatchState)
local Net = require(Shared.Net.Net)
local QuestConfig = require(Shared.Config.QuestConfig)
local Progression = require(Shared.Data.Progression)
local RateLimiter = require(script.Parent.Parent.Components.RateLimiter)
local ThemedArenaBuilder = require(script.Parent.Parent.Map.ThemedArenaBuilder)
local SpawnService = require(script.Parent.SpawnService)
local LobbyService = require(script.Parent.LobbyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local QuestService = require(script.Parent.QuestService)
local AmmoService = require(script.Parent.AmmoService)

type Player_ = {
	player: Player,
	eliminations: number,
	deaths: number,
	alive: boolean,
	connections: { RBXScriptConnection },
}

local PATTR = MatchState.PlayerAttr
local FFA_ATTRIBUTE = "FreeForAll"
local ARENA_ORIGIN = Vector3.new(1600, 0, 0) -- far from the team-match arena
local CHECK_INTERVAL = 0.25
local BREAK_TIME = 6 -- seconds between rounds
local THEMES = { "Bounce", "Candy", "Ice", "Reef", "Space", "Kitchen", "Fireplace", "AntFarm" }

local MODE = ModeConfig.get("FreeForAll") :: ModeConfig.Mode
local TARGET = MODE.EliminationsToWin or 20
local ROUND_TIME = MODE.RoundTime
local RESPAWN_DELAY = MODE.RespawnDelay or 2.5

local FreeForAllService = {}

local playing: { [Player]: Player_ } = {}
local busy: { [Player]: boolean } = {} -- moving in or out right now
local spawnPoints: { BasePart } = {}
local themeIndex = 0
local roundEndsAt = 0
local roundActive = false
local stateFolder: Folder
local leaveLimiter = RateLimiter.new(2, 2)
local started = false

local function count(): number
	local total = 0
	for _ in playing do
		total += 1
	end
	return total
end

local function leader(): Player_?
	local best: Player_? = nil
	for _, entry in playing do
		if best == nil or entry.eliminations > best.eliminations or (entry.eliminations == best.eliminations and entry.deaths < best.deaths) then
			best = entry
		end
	end
	return best
end

local function publish()
	local top = leader()
	stateFolder:SetAttribute("Players", count())
	stateFolder:SetAttribute("LeaderName", if top and top.eliminations > 0 then top.player.DisplayName else "")
	stateFolder:SetAttribute("LeaderScore", if top then top.eliminations else 0)
	stateFolder:SetAttribute("Target", TARGET)
	stateFolder:SetAttribute("RoundEndsAt", if roundActive then Workspace:GetServerTimeNow() + math.max(0, roundEndsAt - os.clock()) else 0)
	-- The lobby pad shows how many are playing.
	local pad = LobbyService.getFfaPad()
	if pad then
		local text = if count() > 0 then `{count()} PLAYING` else "JUMP IN"
		pad.counter.Text = text
		if pad.screenCount then
			pad.screenCount.Text = text
		end
	end
end

-- Builds the next themed arena, sized for how many are playing.
local function buildArena()
	themeIndex = themeIndex % #THEMES + 1
	local ok, result = pcall(ThemedArenaBuilder.build, MapConfig.scaleFor(math.max(count(), 8)), THEMES[themeIndex], true, ARENA_ORIGIN, "FreeForAllArena")
	if ok then
		spawnPoints = result.spawnPoints
		AmmoService.setSpots(result.ammoSpots, "FreeForAll")
		stateFolder:SetAttribute("Arena", THEMES[themeIndex])
	else
		warn(`[FreeForAllService] Building the arena failed: {result}`)
	end
end

local function spawnInArena(entry: Player_)
	local player = entry.player
	if #spawnPoints == 0 or playing[player] ~= entry then
		return
	end
	local character = SpawnService.spawn(player, nil, spawnPoints)
	if character and playing[player] == entry then
		entry.alive = true
	end
end

-- Counts an elimination and brings the player back after a short wait.
local function watchCharacter(entry: Player_, character: Model)
	local found = character:WaitForChild("Humanoid", 10)
	if not found or not found:IsA("Humanoid") then
		return
	end
	local humanoid = found :: Humanoid
	humanoid.Died:Once(function()
		if playing[entry.player] ~= entry or not entry.alive then
			return
		end
		entry.alive = false
		entry.deaths += 1
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			AmmoService.dropAt(root.Position)
		end
		local tag = humanoid:FindFirstChild("creator")
		local killer = if tag and tag:IsA("ObjectValue") and tag.Value and tag.Value:IsA("Player") then tag.Value :: Player else nil
		local killerEntry = if killer then playing[killer] else nil
		local credited: Player? = nil
		if killerEntry and killer ~= entry.player then
			killerEntry.eliminations += 1
			killerEntry.player:SetAttribute("FfaEliminations", killerEntry.eliminations)
			credited = killerEntry.player
			QuestService.progress(killerEntry.player, "Elimination")
		end
		PlayerDataService.recordElimination(credited, entry.player, nil)
		publish()
		task.delay(RESPAWN_DELAY, function()
			if playing[entry.player] == entry and not entry.alive then
				spawnInArena(entry)
			end
		end)
	end)
end

function FreeForAllService.isPlaying(player: Player): boolean
	return playing[player] ~= nil
end

function FreeForAllService.canFire(player: Player): boolean
	local entry = playing[player]
	return entry ~= nil and entry.alive and roundActive
end

function FreeForAllService.canDamage(attacker: Player, victim: Player?): boolean
	return roundActive and playing[attacker] ~= nil and victim ~= nil and victim ~= attacker and playing[victim] ~= nil
end

function FreeForAllService.join(player: Player)
	local status = player:GetAttribute(PATTR.Status)
	if playing[player] or busy[player] or player.Parent ~= Players or (status ~= "Lobby" and status ~= "Queued") then
		return
	end
	busy[player] = true
	if #spawnPoints == 0 then
		buildArena()
	end
	local entry: Player_ = { player = player, eliminations = 0, deaths = 0, alive = false, connections = {} }
	playing[player] = entry
	player:SetAttribute(PATTR.Status, "InMatch")
	player:SetAttribute(PATTR.Team, nil)
	player:SetAttribute(FFA_ATTRIBUTE, true)
	player:SetAttribute("FfaEliminations", 0)
	table.insert(entry.connections, player.CharacterAdded:Connect(function(character: Model)
		watchCharacter(entry, character)
	end))
	LobbyService.useMatchCamera(player)
	if not roundActive then
		roundActive = true
		roundEndsAt = os.clock() + ROUND_TIME
	end
	spawnInArena(entry)
	busy[player] = nil
	publish()
end

function FreeForAllService.leave(player: Player, toLobby: boolean?)
	local entry = playing[player]
	if not entry or busy[player] then
		return
	end
	busy[player] = true
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	playing[player] = nil
	if player.Parent == Players then
		player:SetAttribute(FFA_ATTRIBUTE, nil)
		player:SetAttribute("FfaEliminations", nil)
		player:SetAttribute(PATTR.Status, "Lobby")
		if toLobby ~= false then
			LobbyService.spawn(player)
		end
	end
	busy[player] = nil
	if count() == 0 then
		roundActive = false -- nobody left: the next player starts a fresh round
	end
	publish()
end

-- The end of a round: the winner gets a win, everyone gets XP, then a break.
local function finishRound()
	roundActive = false
	local winnerEntry = leader()
	local winner = if winnerEntry and winnerEntry.eliminations > 0 then winnerEntry.player else nil
	local message = if winner then `{winner.DisplayName} wins the round!` else "Round over!"
	for player, entry in playing do
		local won = player == winner
		if won then
			PlayerDataService.recordWin(player)
			QuestService.reward(player, QuestConfig.WIN_COINS, "Free for all victory!")
			QuestService.progress(player, "WinMatch")
		else
			PlayerDataService.recordNoWin(player)
			Net.event("RewardToast"):FireClient(player, message, 0)
		end
		PlayerDataService.addXp(player, Progression.matchXp(entry.eliminations, won))
		QuestService.progress(player, "PlayMatch")
	end
	stateFolder:SetAttribute("LastWinner", if winner then winner.DisplayName else "")
	publish()

	-- A short break, then a new arena and a fresh round for everyone still here.
	task.wait(BREAK_TIME)
	if count() == 0 then
		return
	end
	buildArena()
	for player, entry in playing do
		entry.eliminations = 0
		entry.deaths = 0
		entry.alive = false
		player:SetAttribute("FfaEliminations", 0)
	end
	roundActive = true
	roundEndsAt = os.clock() + ROUND_TIME
	for _, entry in playing do
		task.spawn(spawnInArena, entry)
	end
	publish()
end

local function standingOn(player: Player, pad: BasePart, radius: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local offset = root.Position - pad.Position
	return Vector2.new(offset.X, offset.Z).Magnitude <= radius and math.abs(offset.Y) <= 6
end

local function update()
	-- Anyone stepping on the lobby pad jumps straight in.
	local pad = LobbyService.getFfaPad()
	if pad then
		for _, player in Players:GetPlayers() do
			local status = player:GetAttribute(PATTR.Status)
			if (status == "Lobby" or status == "Queued") and not playing[player] and standingOn(player, pad.part, pad.radius) then
				task.spawn(FreeForAllService.join, player)
			end
		end
	end
	-- The round ends at the target score or when time runs out.
	if roundActive and count() > 0 then
		local top = leader()
		if (top and top.eliminations >= TARGET) or os.clock() >= roundEndsAt then
			task.spawn(finishRound)
		end
	end
end

function FreeForAllService.start()
	if started then
		return
	end
	started = true
	stateFolder = Instance.new("Folder")
	stateFolder.Name = "FreeForAllState"
	stateFolder.Parent = ReplicatedStorage
	publish()

	Net.event("FreeForAllLeave").OnServerEvent:Connect(function(player: Player)
		if leaveLimiter:allow(player) then
			FreeForAllService.leave(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		FreeForAllService.leave(player, false)
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(update)
			if not ok then
				warn("[FreeForAllService]", err)
			end
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return FreeForAllService

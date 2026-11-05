--!strict
--[[
	PlayerData
	Loads, holds and saves each player's progress (coins, kills, colors).

	How it keeps progress safe:
	  * Retries: every DataStore request is retried with growing waits
	    (1s, 2s, 4s, 8s) because Roblox's servers occasionally hiccup.
	  * Session lock: while a player is in this server, their save is marked
	    "in use here". If they hop to another server too quickly, that server
	    waits for us to finish saving instead of loading old data.
	  * Never overwrite on failure: if loading fails we play with temporary
	    data and do NOT save it, so a blip can't wipe real progress.
	  * Autosave every minute, save when leaving, and save everyone when the
	    server shuts down (BindToClose).

	Other scripts should only change data through PlayerData.update(), so the
	leaderboard and the player's screen always stay in sync.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

type PlayerData = Types.PlayerData

local STORE_NAME = "PlayerData_v1"
local SCHEMA_VERSION = 1
local MAX_ATTEMPTS = 5 -- tries per DataStore request
local AUTOSAVE_SECONDS = 60
local LOCK_STALE_SECONDS = 300 -- a lock older than this belonged to a crashed server, so we may take it
local LOCK_WAIT_ATTEMPTS = 5 -- how many times to re-check a lock held by another server
local LOCK_WAIT_SECONDS = 6
local SHUTDOWN_TIMEOUT = 25 -- Roblox gives BindToClose about 30 seconds

type Session = {
	Data: PlayerData,
	CanSave: boolean, -- false when loading failed: never save temporary data over the real thing
	IsSaving: boolean,
}

type LoadOutcome = "Loaded" | "Locked" | "Failed"

local PlayerData = {}

local sessions: { [Player]: Session } = {}
local changedCallbacks: { (Player, PlayerData) -> () } = {}
local pendingSaves = 0

local dataChangedRemote = Remotes.event("DataChanged")
local getDataRemote = Remotes.func("GetData")

-- GetDataStore can fail (for example in a place that was never published).
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn(`[PlayerData] DataStores unavailable, progress will NOT be saved: {result}`)
	end
end

local function keyFor(userId: number): string
	return `Player_{userId}`
end

local function makeDefaultData(): PlayerData
	return {
		Version = SCHEMA_VERSION,
		Coins = 0,
		Kills = 0,
		Deaths = 0,
		OwnedColors = { [ShopCatalog.DefaultColorId] = true },
		EquippedColor = ShopCatalog.DefaultColorId,
	}
end

-- Turns whatever was in the DataStore into a clean PlayerData. Missing fields
-- (from older saves) get defaults, and junk values are ignored.
local function reconcile(raw: any): PlayerData
	local data = makeDefaultData()
	if typeof(raw) ~= "table" then
		return data -- brand new player
	end

	local function wholeNumber(value: any): number?
		if typeof(value) == "number" and value == value and value >= 0 and value < math.huge then
			return math.floor(value)
		end
		return nil
	end

	data.Coins = wholeNumber(raw.Coins) or 0
	data.Kills = wholeNumber(raw.Kills) or 0
	data.Deaths = wholeNumber(raw.Deaths) or 0

	if typeof(raw.OwnedColors) == "table" then
		for id, owned in raw.OwnedColors do
			-- Keep ids even if a color was later removed from the shop, so nothing is ever lost.
			if typeof(id) == "string" and owned == true then
				data.OwnedColors[id] = true
			end
		end
	end

	local equipped = raw.EquippedColor
	if typeof(equipped) == "string" and data.OwnedColors[equipped] and ShopCatalog.find(equipped) then
		data.EquippedColor = equipped
	end

	-- Future upgrades go here, e.g. `if raw.Version < 2 then ... end`
	data.Version = SCHEMA_VERSION
	return data
end

-- Runs `request` until it succeeds, waiting longer after each failure.
local function withRetries(label: string, request: () -> ()): boolean
	for attempt = 1, MAX_ATTEMPTS do
		local ok, err = pcall(request)
		if ok then
			return true
		end
		warn(`[PlayerData] {label} failed (attempt {attempt}/{MAX_ATTEMPTS}): {err}`)
		if attempt < MAX_ATTEMPTS then
			task.wait(2 ^ (attempt - 1))
		end
	end
	return false
end

local function isLockedByOtherServer(record: any, now: number): boolean
	return typeof(record) == "table"
		and typeof(record.LockedBy) == "string"
		and record.LockedBy ~= game.JobId
		and typeof(record.LockedAt) == "number"
		and now - record.LockedAt < LOCK_STALE_SECONDS
end

local function loadData(userId: number): (LoadOutcome, PlayerData?)
	local activeStore = store
	if not activeStore then
		return "Failed", nil
	end
	local key = keyFor(userId)

	for _ = 1, LOCK_WAIT_ATTEMPTS do
		local loaded: PlayerData? = nil

		-- UpdateAsync reads and writes in one safe step: we read the save
		-- and claim the lock at the same time.
		local ok = withRetries(`Load {key}`, function()
			activeStore:UpdateAsync(key, function(old: any): any
				loaded = nil
				if isLockedByOtherServer(old, os.time()) then
					return nil -- returning nil means "don't write anything"
				end
				local data = reconcile(if typeof(old) == "table" then old.Data else nil)
				loaded = data
				return { Data = data, LockedBy = game.JobId, LockedAt = os.time() }
			end)
		end)

		if not ok then
			return "Failed", nil
		end
		if loaded then
			return "Loaded", loaded
		end
		-- Another server still has the lock (it's probably saving right now). Wait and try again.
		task.wait(LOCK_WAIT_SECONDS)
	end
	return "Locked", nil
end

-- Saves a player's data. `release` = true when they're leaving, which also
-- removes our lock so the next server can load them straight away.
local function saveData(player: Player, session: Session, release: boolean): boolean
	local activeStore = store
	if not session.CanSave or not activeStore then
		return false
	end

	-- Count this save straight away, so shutdown waits for it even while it's queued.
	pendingSaves += 1

	-- Never let two saves for the same player overlap.
	while session.IsSaving do
		task.wait()
	end
	session.IsSaving = true

	local key = keyFor(player.UserId)
	local ok = withRetries(`Save {key}`, function()
		activeStore:UpdateAsync(key, function(old: any): any
			if typeof(old) == "table" and typeof(old.LockedBy) == "string" and old.LockedBy ~= game.JobId then
				-- Another server has taken over this player's data. Writing now
				-- would roll their progress back, so we stop.
				return nil
			end
			return {
				Data = session.Data,
				LockedBy = if release then nil else game.JobId,
				LockedAt = if release then nil else os.time(),
			}
		end)
	end)

	pendingSaves -= 1
	session.IsSaving = false
	return ok
end

local function toPublic(session: Session): Types.PublicData
	local data = session.Data
	return {
		Coins = data.Coins,
		Kills = data.Kills,
		Deaths = data.Deaths,
		OwnedColors = table.clone(data.OwnedColors),
		EquippedColor = data.EquippedColor,
		SavingEnabled = session.CanSave,
	}
end

-- The "leaderstats" folder makes Roblox show Coins and Kills on the player list.
local function createLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	for _, statName in { "Kills", "Coins" } do
		local value = Instance.new("IntValue")
		value.Name = statName
		value.Parent = leaderstats
	end
	leaderstats.Parent = player
end

-- Pushes the latest data to the leaderboard, the player's screen and other server scripts.
local function publish(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local kills = leaderstats:FindFirstChild("Kills")
		local coins = leaderstats:FindFirstChild("Coins")
		if kills and kills:IsA("IntValue") then
			kills.Value = session.Data.Kills
		end
		if coins and coins:IsA("IntValue") then
			coins.Value = session.Data.Coins
		end
	end
	dataChangedRemote:FireClient(player, toPublic(session))
	for _, callback in changedCallbacks do
		task.spawn(callback, player, session.Data)
	end
end

local function onPlayerAdded(player: Player)
	createLeaderstats(player)

	local outcome, data = loadData(player.UserId)
	if outcome == "Locked" then
		player:Kick("Your progress is still saving on another server. Please rejoin in a minute!")
		return
	end

	local session: Session
	if outcome == "Loaded" and data then
		session = { Data = data, CanSave = true, IsSaving = false }
	else
		warn(`[PlayerData] Could not load {player.Name}; using temporary data that will NOT be saved.`)
		session = { Data = makeDefaultData(), CanSave = false, IsSaving = false }
	end

	-- They might have left while we were loading. If so, just release the lock.
	if player.Parent ~= Players then
		saveData(player, session, true)
		return
	end

	sessions[player] = session
	publish(player)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return -- still loading; onPlayerAdded will release the lock when it finishes
	end
	sessions[player] = nil
	saveData(player, session, true)
end

------------------------------------------------------------------------
-- Public functions for other server scripts
------------------------------------------------------------------------

-- Returns the player's data for READING. Use PlayerData.update to change it.
function PlayerData.get(player: Player): PlayerData?
	local session = sessions[player]
	return if session then session.Data else nil
end

-- Changes a player's data and tells everyone who cares. Returns false if
-- the player's data isn't loaded (yet).
function PlayerData.update(player: Player, mutate: (PlayerData) -> ()): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	mutate(session.Data)
	publish(player)
	return true
end

-- Saves soon, without waiting (used after purchases).
function PlayerData.requestSave(player: Player)
	local session = sessions[player]
	if session then
		task.spawn(saveData, player, session, false)
	end
end

-- Calls `callback(player, data)` whenever someone's data changes.
function PlayerData.onChanged(callback: (Player, PlayerData) -> ())
	table.insert(changedCallbacks, callback)
end

function PlayerData.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- A client can ask for its own data when its scripts start up.
	getDataRemote.OnServerInvoke = function(player: Player): Types.PublicData?
		local session = sessions[player]
		return if session then toPublic(session) else nil
	end

	-- Autosave, in case the server crashes.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player, session in sessions do
				task.spawn(saveData, player, session, false)
			end
		end
	end)

	-- When the server shuts down, save everyone and wait for it to finish.
	game:BindToClose(function()
		for player, session in sessions do
			sessions[player] = nil
			task.spawn(saveData, player, session, true)
		end
		local deadline = os.clock() + SHUTDOWN_TIMEOUT
		while pendingSaves > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerData

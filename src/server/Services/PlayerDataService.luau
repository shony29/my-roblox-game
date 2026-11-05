--!strict
--[[
	PlayerDataService
	=================
	Loads and saves each player's lifetime stats (eliminations, wins, coins)
	with DataStores, and tracks this round's eliminations and deaths.

	How progress is kept safe:
	  * Retries: every DataStore call is retried with growing waits
	    (1s, 2s, 4s, ...) before giving up.
	  * Session lock: while a player is in this server, the save is marked
	    as "owned" by this server. If they hop servers quickly, the new
	    server waits for the old one to finish saving, so a stale copy can
	    never overwrite newer progress.
	  * Autosave every couple of minutes, a save when the player leaves,
	    and a save for everyone when the server shuts down (BindToClose).
	  * If loading fails, we never save over their real data.

	How other server code uses this (for example the combat system):

		local PlayerDataService = require(ServerScriptService.Server.Services.PlayerDataService)
		PlayerDataService.recordElimination(killerPlayer, victimPlayer)
		PlayerDataService.recordWin(winnerPlayer)
		PlayerDataService.resetRoundStats() -- at the start of each round

	The shop (Server/Shop) uses purchaseItem and setEquippedItem.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Schema = require(Shared:WaitForChild("Data"):WaitForChild("PlayerDataSchema"))
local GameContract = require(Shared:WaitForChild("Net"):WaitForChild("GameContract"))
local ShopConfig = require(Shared:WaitForChild("Config"):WaitForChild("ShopConfig"))
local UpgradeConfig = require(Shared:WaitForChild("Config"):WaitForChild("UpgradeConfig"))

type PlayerData = Schema.PlayerData

-- What purchaseItem answers.
export type PurchaseResult = "Bought" | "NotLoaded" | "AlreadyOwned" | "NotEnoughCoins"

type SessionLock = {
	jobId: string,
	time: number,
}

-- The exact shape stored in the DataStore.
type StoredRecord = {
	data: PlayerData,
	lock: SessionLock?,
}

type Profile = {
	player: Player,
	key: string,
	data: PlayerData,
	canSave: boolean, -- false if loading failed or the lock was lost
	released: boolean, -- true after the final save released the lock
	saving: boolean,
	dirty: boolean, -- true if something changed since the last save
}

-- Settings ------------------------------------------------------------------

local DATASTORE_NAME = "PlayerData_v1"
local MAX_ATTEMPTS = 5
local AUTOSAVE_INTERVAL = 120 -- seconds
local LOCK_EXPIRY = 600 -- a lock older than this is treated as abandoned
local LOCK_WAIT_ATTEMPTS = 6 -- how many times to wait for another server's lock
local SHUTDOWN_TIMEOUT = 25 -- Roblox gives BindToClose about 30 seconds
local BUDGET_WAIT_LIMIT = 10 -- seconds to wait for DataStore request budget

local ATTR = GameContract.PlayerAttributes
local JOB_ID = if game.JobId ~= "" then game.JobId else "studio"

-- State ---------------------------------------------------------------------

local PlayerDataService = {}

-- Seconds between Daily Squishy claims.
PlayerDataService.DAILY_COOLDOWN = 24 * 60 * 60

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}
-- UserIds whose leave-save is still running (for quick rejoins to this server)
local releasing: { [number]: boolean } = {}
local started = false
local shuttingDown = false
local killFeedRemote: RemoteEvent? = nil

-- Helpers -------------------------------------------------------------------

local function keyFor(player: Player): string
	return "player_" .. tostring(player.UserId)
end

local function backoff(attempt: number)
	-- 1, 2, 4, 8 ... seconds, plus a little randomness so servers don't
	-- all retry at the exact same moment.
	task.wait(math.min(2 ^ (attempt - 1), 16) + math.random())
end

local function waitForBudget(requestType: Enum.DataStoreRequestType)
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 and waited < BUDGET_WAIT_LIMIT do
		task.wait(0.5)
		waited += 0.5
	end
end

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		store = result
		return result
	end
	warn("[PlayerData] Could not open DataStore:", result)
	return nil
end

local function isLockedByOtherServer(record: StoredRecord?): boolean
	if record == nil or record.lock == nil then
		return false
	end
	local lock = record.lock :: SessionLock
	if lock.jobId == JOB_ID then
		return false
	end
	return os.time() - lock.time < LOCK_EXPIRY
end

-- Copies the profile's numbers onto the Player so the UI can show them.
local function publishAttributes(profile: Profile)
	local player = profile.player
	player:SetAttribute(ATTR.LifetimeEliminations, profile.data.eliminations)
	player:SetAttribute(ATTR.Wins, profile.data.wins)
	player:SetAttribute(ATTR.Coins, profile.data.coins)
	player:SetAttribute(ATTR.XP, profile.data.xp)
	player:SetAttribute(ATTR.DailyReadyAt, profile.data.lastDailyAt + PlayerDataService.DAILY_COOLDOWN)
	-- Shop: what they own and wear (everyone can see these, which is fine).
	player:SetAttribute(ATTR.OwnedItems, table.concat(profile.data.ownedItems, ","))
	player:SetAttribute(ATTR.EquippedColor, profile.data.equippedItems.Color)
	player:SetAttribute(ATTR.EquippedHat, profile.data.equippedItems.Hat)
	player:SetAttribute(ATTR.EquippedSkin, profile.data.equippedItems.Skin)
	player:SetAttribute(ATTR.EquippedTopping, profile.data.equippedItems.Topping)
	player:SetAttribute("GunLevels", UpgradeConfig.format(profile.data.gunLevels))
end

-- Loading -------------------------------------------------------------------

-- Returns the player's data, or nil if it could not be loaded safely.
local function loadData(key: string): PlayerData?
	local dataStore = getStore()
	if dataStore == nil then
		return nil
	end

	local lockWaits = 0
	local attempt = 0
	while attempt < MAX_ATTEMPTS do
		attempt += 1
		local lockedElsewhere = false
		local stealLock = lockWaits >= LOCK_WAIT_ATTEMPTS

		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local ok, result = pcall(function()
			return dataStore:UpdateAsync(key, function(old: unknown): StoredRecord?
				lockedElsewhere = false
				local oldRecord: StoredRecord? = nil
				if typeof(old) == "table" then
					oldRecord = old :: StoredRecord
				end

				if isLockedByOtherServer(oldRecord) and not stealLock then
					lockedElsewhere = true
					return nil -- returning nil cancels the write
				end

				local data = Schema.reconcile(if oldRecord then oldRecord.data else nil)
				return {
					data = data,
					lock = { jobId = JOB_ID, time = os.time() },
				}
			end)
		end)

		if ok and lockedElsewhere then
			-- Another server is still saving this player. Wait and try again;
			-- this does not count as a failed attempt.
			lockWaits += 1
			attempt -= 1
			task.wait(5)
		elseif ok and typeof(result) == "table" then
			return Schema.reconcile((result :: StoredRecord).data)
		else
			warn(string.format("[PlayerData] Load attempt %d for %s failed: %s", attempt, key, tostring(result)))
			if attempt < MAX_ATTEMPTS then
				backoff(attempt)
			end
		end
	end
	return nil
end

-- Saving --------------------------------------------------------------------

--[[
	Saves a profile. If `release` is true, the session lock is removed so
	the player's next server can load right away.
	Returns true when the save succeeded (or there was nothing to save).
]]
local function saveProfile(profile: Profile, release: boolean): boolean
	if not profile.canSave or profile.released then
		return true
	end

	-- Only one save per player at a time.
	while profile.saving do
		task.wait(0.1)
	end
	if profile.released then
		return true
	end
	if not profile.dirty and not release then
		return true
	end

	local dataStore = getStore()
	if dataStore == nil then
		return false
	end

	profile.saving = true
	-- Take a snapshot so changes during the save don't get half-written.
	local snapshot = Schema.copy(profile.data)
	profile.dirty = false

	local success = false
	local lostLock = false
	for attempt = 1, MAX_ATTEMPTS do
		lostLock = false
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local ok, err = pcall(function()
			dataStore:UpdateAsync(profile.key, function(old: unknown): StoredRecord?
				lostLock = false
				local oldRecord: StoredRecord? = nil
				if typeof(old) == "table" then
					oldRecord = old :: StoredRecord
				end
				if isLockedByOtherServer(oldRecord) then
					-- Another server took over this player. Their copy is newer.
					lostLock = true
					return nil
				end
				return {
					data = snapshot,
					lock = if release then nil else { jobId = JOB_ID, time = os.time() },
				}
			end)
		end)

		if ok then
			success = not lostLock
			break
		end
		warn(string.format("[PlayerData] Save attempt %d for %s failed: %s", attempt, profile.key, tostring(err)))
		if attempt < MAX_ATTEMPTS then
			backoff(attempt)
		end
	end

	if lostLock then
		warn("[PlayerData] Another server owns " .. profile.key .. "; this server will stop saving it.")
		profile.canSave = false
	elseif success and release then
		profile.released = true
	elseif not success then
		profile.dirty = true -- try again on the next save
	end

	profile.saving = false
	return success
end

-- Player lifecycle ----------------------------------------------------------

local function onPlayerAdded(player: Player)
	if profiles[player] or loading[player] then
		return
	end
	loading[player] = true
	player:SetAttribute(ATTR.DataLoaded, false)
	player:SetAttribute(ATTR.RoundEliminations, 0)
	player:SetAttribute(ATTR.RoundDeaths, 0)

	-- If they just left this same server, wait for that save to finish first.
	local waitStart = os.clock()
	while releasing[player.UserId] and os.clock() - waitStart < SHUTDOWN_TIMEOUT do
		task.wait(0.25)
	end

	local key = keyFor(player)
	local data = loadData(key)
	loading[player] = nil

	local profile: Profile = {
		player = player,
		key = key,
		data = data or Schema.default(),
		canSave = data ~= nil,
		released = false,
		saving = false,
		dirty = false,
	}

	if player.Parent ~= Players then
		-- They left while we were loading: release the lock and stop.
		if data then
			saveProfile(profile, true)
		end
		return
	end

	if data == nil then
		if RunService:IsStudio() then
			warn(
				"[PlayerData] Could not load data in Studio. Playing with temporary data that will NOT be saved. "
					.. "To test saving, turn on 'Enable Studio Access to API Services' in Game Settings > Security."
			)
		else
			player:Kick("We couldn't load your progress, so we stopped to keep it safe. Please rejoin in a moment!")
			return
		end
	end

	profiles[player] = profile
	publishAttributes(profile)
	player:SetAttribute(ATTR.DataLoaded, data ~= nil)
end

local function onPlayerRemoving(player: Player)
	-- If they're still loading, onPlayerAdded handles cleanup.
	local profile = profiles[player]
	if profile == nil then
		return
	end
	releasing[player.UserId] = true
	saveProfile(profile, true)
	releasing[player.UserId] = nil
	profiles[player] = nil
end

local function onShutdown()
	shuttingDown = true
	local pending = 0
	for _, profile in profiles do
		pending += 1
		task.spawn(function()
			saveProfile(profile, true)
			pending -= 1
		end)
	end

	local shutdownStart = os.clock()
	while pending > 0 and os.clock() - shutdownStart < SHUTDOWN_TIMEOUT do
		task.wait(0.1)
	end
	if pending > 0 then
		warn(string.format("[PlayerData] Shutdown: %d save(s) did not finish in time.", pending))
	end
end

local function autosaveLoop()
	while not shuttingDown do
		task.wait(AUTOSAVE_INTERVAL)
		if shuttingDown then
			break
		end
		for _, profile in profiles do
			-- Saving also refreshes the session lock so it doesn't expire.
			profile.dirty = true
			task.spawn(saveProfile, profile, false)
		end
	end
end

local function isInGame(player: unknown): boolean
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function addRoundStat(player: Player, attribute: string)
	local current = player:GetAttribute(attribute)
	player:SetAttribute(attribute, (if typeof(current) == "number" then current else 0) + 1)
end

-- Public API ----------------------------------------------------------------

function PlayerDataService.start()
	if started then
		return
	end
	started = true

	killFeedRemote = GameContract.getRemote(GameContract.RemoteNames.KillFeed)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Players who joined before this script started
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(onShutdown)
	task.spawn(autosaveLoop)
end

-- Returns a copy of the player's saved data, or nil if not loaded yet.
function PlayerDataService.getData(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile then Schema.copy(profile.data) else nil
end

-- Adds coins. Only whole, positive amounts are accepted.
--[[
	Marks today's Daily Squishy as claimed, if it's ready. Check and change
	happen together with no waiting in between, so it can't be claimed twice.
	Returns true if the claim may go ahead.
]]
function PlayerDataService.tryClaimDaily(player: Player, now: number): boolean
	local profile = profiles[player]
	if profile == nil or now < profile.data.lastDailyAt + PlayerDataService.DAILY_COOLDOWN then
		return false
	end
	profile.data.lastDailyAt = now
	profile.dirty = true
	publishAttributes(profile)
	return true
end

--[[
	Grants an item bought with Robux (called from the purchase receipt handler).
	`purchaseId` is Roblox's id for this purchase: if it was already granted,
	nothing happens again. Returns "Granted", "AlreadyGranted" or "NotLoaded".
]]
function PlayerDataService.grantPurchase(player: Player, itemId: string, purchaseId: string): string
	local profile = profiles[player]
	if profile == nil then
		return "NotLoaded"
	end
	if table.find(profile.data.receipts, purchaseId) then
		return "AlreadyGranted"
	end
	if not table.find(profile.data.ownedItems, itemId) then
		table.insert(profile.data.ownedItems, itemId)
	end
	table.insert(profile.data.receipts, purchaseId)
	while #profile.data.receipts > 100 do
		table.remove(profile.data.receipts, 1)
	end
	profile.dirty = true
	publishAttributes(profile)
	return "Granted"
end

-- A gun's upgrade level (0 = not upgraded).
function PlayerDataService.getGunLevel(player: Player, weaponId: string): number
	local profile = profiles[player]
	return if profile then profile.data.gunLevels[weaponId] or 0 else 0
end

-- Raises a gun's upgrade level by one (Daily Squishy prize). Returns the
-- new level, or nil if it was already at the top or data isn't loaded.
function PlayerDataService.upgradeGun(player: Player, weaponId: string): number?
	local profile = profiles[player]
	if profile == nil then
		return nil
	end
	local level = profile.data.gunLevels[weaponId] or 0
	if level >= UpgradeConfig.MAX_LEVEL then
		return nil
	end
	profile.data.gunLevels[weaponId] = level + 1
	profile.dirty = true
	publishAttributes(profile)
	return level + 1
end

-- Adds experience. Only whole, positive amounts are accepted (server only).
function PlayerDataService.addXp(player: Player, amount: number): boolean
	local profile = profiles[player]
	if profile == nil or typeof(amount) ~= "number" or amount ~= amount then
		return false
	end
	amount = math.floor(amount)
	if amount <= 0 then
		return false
	end
	profile.data.xp = math.min(profile.data.xp + amount, Schema.MAX_STAT_VALUE)
	profile.dirty = true
	publishAttributes(profile)
	return true
end

function PlayerDataService.addCoins(player: Player, amount: number): boolean
	local profile = profiles[player]
	if profile == nil or typeof(amount) ~= "number" or amount ~= amount then
		return false
	end
	amount = math.floor(amount)
	if amount <= 0 then
		return false
	end
	profile.data.coins = math.min(profile.data.coins + amount, Schema.MAX_STAT_VALUE)
	profile.dirty = true
	publishAttributes(profile)
	return true
end

--[[
	Call this from the server whenever someone is eliminated.
	`killer` can be nil (for example falling off the map).
	Gives the killer +1 elimination and coins, gives the victim +1 death,
	and shows the kill feed to everyone.
]]
function PlayerDataService.recordElimination(killer: Player?, victim: Player, killerName: string?)
	if not isInGame(victim) then
		return
	end
	addRoundStat(victim, ATTR.RoundDeaths)

	local validKiller = killer ~= nil and killer ~= victim and isInGame(killer)
	if validKiller then
		local killerPlayer = killer :: Player
		addRoundStat(killerPlayer, ATTR.RoundEliminations)
		local profile = profiles[killerPlayer]
		if profile then
			profile.data.eliminations = math.min(profile.data.eliminations + 1, Schema.MAX_STAT_VALUE)
			profile.dirty = true
			PlayerDataService.addCoins(killerPlayer, Schema.COINS_PER_ELIMINATION)
		end
	end

	-- Fetched here (not only in start) because the round system's Script may
	-- report an elimination before DataBootstrap has called start().
	local remote = killFeedRemote or GameContract.getRemote(GameContract.RemoteNames.KillFeed)
	killFeedRemote = remote
	-- killerName names a bot when a bot made the elimination.
	local shownKiller = if validKiller then (killer :: Player).DisplayName else killerName
	remote:FireAllClients(shownKiller, victim.DisplayName)
end

-- Kill feed only (for bots being eliminated: no stats, no coins).
function PlayerDataService.announceElimination(killerName: string?, victimName: string)
	local remote = killFeedRemote or GameContract.getRemote(GameContract.RemoteNames.KillFeed)
	killFeedRemote = remote
	remote:FireAllClients(killerName, victimName)
end

-- Call this when a player wins a round.
function PlayerDataService.recordWin(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end
	profile.data.wins = math.min(profile.data.wins + 1, Schema.MAX_STAT_VALUE)
	profile.dirty = true
	publishAttributes(profile)
end

-- Sets everyone's round eliminations and deaths back to zero.
function PlayerDataService.resetRoundStats()
	for _, player in Players:GetPlayers() do
		player:SetAttribute(ATTR.RoundEliminations, 0)
		player:SetAttribute(ATTR.RoundDeaths, 0)
	end
end

-- True if the player owns this shop item (free items are always owned).
function PlayerDataService.ownsItem(player: Player, itemId: string): boolean
	local profile = profiles[player]
	if profile == nil then
		return false
	end
	return ShopConfig.isFree(itemId) or table.find(profile.data.ownedItems, itemId) ~= nil
end

--[[
	Spends `price` coins and adds `itemId` to the player's owned items.
	The checks and the change happen together with no waiting in between,
	so two quick requests can never both spend the same coins.
	The shop checks that the item and price are real before calling this.
]]
function PlayerDataService.purchaseItem(player: Player, itemId: string, price: number): PurchaseResult
	local profile = profiles[player]
	if profile == nil then
		return "NotLoaded"
	end
	if PlayerDataService.ownsItem(player, itemId) then
		return "AlreadyOwned"
	end
	price = math.max(0, math.floor(price))
	if profile.data.coins < price then
		return "NotEnoughCoins"
	end
	if #profile.data.ownedItems >= Schema.MAX_OWNED_ITEMS then
		return "AlreadyOwned"
	end
	profile.data.coins -= price
	table.insert(profile.data.ownedItems, itemId)
	profile.dirty = true
	publishAttributes(profile)
	return "Bought"
end

-- Wears an item in its slot (Color, Hat or Skin). The item must be owned.
function PlayerDataService.setEquippedItem(player: Player, category: ShopConfig.Category, itemId: string): boolean
	local profile = profiles[player]
	if profile == nil or not PlayerDataService.ownsItem(player, itemId) then
		return false
	end
	local equipped = profile.data.equippedItems
	if category == "Color" then
		equipped.Color = itemId
	elseif category == "Hat" then
		equipped.Hat = itemId
	elseif category == "Skin" then
		equipped.Skin = itemId
	elseif category == "Topping" then
		equipped.Topping = itemId
	else
		return false -- guns are owned, not worn
	end
	profile.dirty = true
	publishAttributes(profile)
	return true
end

-- Saves a player right away (for example after a big purchase).
function PlayerDataService.saveNow(player: Player): boolean
	local profile = profiles[player]
	if profile == nil then
		return false
	end
	profile.dirty = true
	return saveProfile(profile, false)
end

return PlayerDataService

--!strict
--[[
	Net: every RemoteEvent and RemoteFunction in the game, in ONE list.

	Conventions (please follow these when adding networking):
	  * Add the name to EventName/FunctionName and to EVENTS/FUNCTIONS below.
	    A typo in a name then becomes a type error instead of a silent bug.
	  * Name remotes "<System><Action>", for example "WeaponFire".
	  * RemoteEvent for one-way messages; RemoteFunction only when the client
	    needs an answer (client -> server). The server never invokes a client.
	  * The server must check EVERY value a client sends (type, range, NaN),
	    and rate-limit requests (see server/Components/RateLimiter).
	  * Prefer attributes for state everyone can see (scores, round timer);
	    use remotes for moments (a shot, a kill-feed line).

	The server creates them all in ReplicatedStorage > Remotes (Net.setup).
	Clients wait for them, but never forever: after GameConfig.ClientWaitTimeout
	seconds they stop with a clear error naming the missing remote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("GameConfig"))

export type EventName =
	"KillFeed" -- server -> all: (killerName: string?, victimName: string)
	| "PlayPressed" -- client -> server: ()
	| "WeaponFire" -- client -> server: (weaponId, origin, direction)
	| "WeaponEquip" -- client -> server: (weaponId)
	| "WeaponReload" -- client -> server: ()
	| "WeaponState" -- server -> owner: (weaponId, ammo, reloading)
	| "WeaponHitConfirm" -- server -> shooter: (damage, killed, headshot)
	| "WeaponShotFx" -- server -> others: (shooter, weaponId, origin, endPoints)
	| "MovementRequest" -- client -> server: (action)
	| "MovementResult" -- server -> owner: (action, allowed, readyAt)
	| "MapVote" -- client -> server: (mapId)
	| "MatchResults" -- server -> participants: (results table, see MatchService)
	| "RematchVote" -- client -> server: ()
	| "QuickPlay" -- client -> server: () the lobby's PLAY button (QueueService)
	| "PracticeEnter" -- client -> server: () go to the practice range (PracticeService)
	| "PracticeLeave" -- client -> server: () back to the lobby
	| "TargetPop" -- server -> all: (position, color) a practice target popped
	| "RewardToast" -- server -> owner: (text, coins) a task or reward was earned
	| "SettingsSave" -- client -> server: (volume, sensitivity, fieldOfView) Settings window
	| "FreeForAllLeave" -- client -> server: () leave the free-for-all arena

export type FunctionName =
	"ShopBuyItem" -- client asks: (itemId) -> (ok, message)
	| "ShopEquipItem" -- client asks: (itemId) -> (ok, message)
	| "DailyClaim" -- client asks: () -> result table (see DailyService)
	| "ShopUpgradeGun" -- client asks: (weapon item Id) -> (ok, message)

local EVENTS: { EventName } = {
	"KillFeed",
	"PlayPressed",
	"WeaponFire",
	"WeaponEquip",
	"WeaponReload",
	"WeaponState",
	"WeaponHitConfirm",
	"WeaponShotFx",
	"MovementRequest",
	"MovementResult",
	"MapVote",
	"MatchResults",
	"RematchVote",
	"QuickPlay",
	"PracticeEnter",
	"PracticeLeave",
	"TargetPop",
	"RewardToast",
	"SettingsSave",
	"FreeForAllLeave",
}
local FUNCTIONS: { FunctionName } = { "ShopBuyItem", "ShopEquipItem", "DailyClaim", "ShopUpgradeGun" }

local FOLDER_NAME = "Remotes"

local Net = {}

local function getFolder(): Instance
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, GameConfig.ClientWaitTimeout)
	if folder == nil then
		error(`[Net] ReplicatedStorage.{FOLDER_NAME} never appeared. Did the server start?`)
	end
	return folder
end

local ready = false

-- SERVER ONLY: creates every remote. Safe to call many times.
function Net.setup()
	if ready then
		return
	end
	assert(RunService:IsServer(), "Net.setup() must only be called on the server")
	local folder = getFolder()
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
	ready = true
end

local function find(name: string, className: string): Instance
	if RunService:IsServer() then
		Net.setup()
	end
	local folder = getFolder()
	local remote = if RunService:IsServer()
		then folder:FindFirstChild(name)
		else folder:WaitForChild(name, GameConfig.ClientWaitTimeout)
	if remote == nil or not remote:IsA(className) then
		error(`[Net] {className} "{name}" is missing. Is it listed in Shared/Net/Net.luau?`)
	end
	return remote
end

function Net.event(name: EventName): RemoteEvent
	return find(name, "RemoteEvent") :: RemoteEvent
end

function Net.func(name: FunctionName): RemoteFunction
	return find(name, "RemoteFunction") :: RemoteFunction
end

return Net

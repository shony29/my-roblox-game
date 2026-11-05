--!strict
--[[
	Remotes
	"Remotes" are how the server and players' computers talk to each other.
	  * RemoteEvent    = a one-way message ("I pressed fire!")
	  * RemoteFunction = a question that gets an answer ("Can I buy this?" -> "Yes")

	The server creates them all once at startup (Remotes.setup), and both
	sides fetch them by name. The name lists below act as a single source
	of truth, so a typo becomes a type error instead of a silent bug.

	SAFETY RULE: anything a client sends could be faked by a cheater, so the
	server must check every value it receives. See CombatService/ShopService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type EventName =
	"Fire" -- client -> server: (origin: Vector3, direction: Vector3)
	| "Reload" -- client -> server: ()
	| "AmmoChanged" -- server -> client: (ammo: number, reloading: boolean)
	| "ShotFired" -- server -> all clients: (shooter: Player, origin: Vector3, hitPosition: Vector3)
	| "HitConfirmed" -- server -> shooter: (killed: boolean)
	| "KillFeed" -- server -> all clients: (killer: Player?, victim: Player)
	| "DataChanged" -- server -> one client: (data: PublicData)

export type FunctionName =
	"GetData" -- client asks: () -> PublicData?
	| "BuyColor" -- client asks: (colorId: string) -> (success: boolean, message: string)
	| "EquipColor" -- client asks: (colorId: string) -> (success: boolean, message: string)

local EVENT_NAMES: { EventName } =
	{ "Fire", "Reload", "AmmoChanged", "ShotFired", "HitConfirmed", "KillFeed", "DataChanged" }
local FUNCTION_NAMES: { FunctionName } = { "GetData", "BuyColor", "EquipColor" }

local FOLDER_NAME = "Remotes"

local Remotes = {}

local function getFolder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	-- Clients wait, because the server might not have created it yet.
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local function findRemote(name: string): Instance
	local folder = getFolder()
	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			error(`Remote "{name}" does not exist. Did the server call Remotes.setup()?`)
		end
		return remote
	end
	return folder:WaitForChild(name)
end

-- SERVER ONLY: creates every remote. Call this first thing at startup.
function Remotes.setup()
	assert(RunService:IsServer(), "Remotes.setup() must only be called on the server")
	local folder = getFolder()
	for _, name in EVENT_NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTION_NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Remotes.event(name: EventName): RemoteEvent
	local remote = findRemote(name)
	if remote:IsA("RemoteEvent") then
		return remote
	end
	error(`"{name}" is not a RemoteEvent`)
end

function Remotes.func(name: FunctionName): RemoteFunction
	local remote = findRemote(name)
	if remote:IsA("RemoteFunction") then
		return remote
	end
	error(`"{name}" is not a RemoteFunction`)
end

return Remotes

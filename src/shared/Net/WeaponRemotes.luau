--!strict
--[[
	WeaponRemotes: the "phone lines" between each player's computer and the server.

	The server creates them in ReplicatedStorage > WeaponRemotes, and the
	client waits for them. Doing it in code means nobody has to edit the
	Rojo project file to add them.

	Messages:
	  Fire       client -> server  (weaponId, origin, direction)  "I pulled the trigger, aiming here"
	  Equip      client -> server  (weaponId)                     "I pressed 1, 2 or 3"
	  Reload     client -> server  ()                             "I pressed R"
	  State      server -> client  (weaponId, ammo, reloading)    "Here is your real ammo count"
	  HitConfirm server -> client  (damage, killed, headshot)     "Your shot really hit someone"
	  ShotFx     server -> others  (shooter, weaponId, origin, endPoints)  "Draw this person's shot"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "WeaponRemotes"

export type Remotes = {
	Fire: RemoteEvent,
	Equip: RemoteEvent,
	Reload: RemoteEvent,
	State: RemoteEvent,
	HitConfirm: RemoteEvent,
	ShotFx: RemoteEvent,
}

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
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local function getRemote(folder: Instance, name: string): RemoteEvent
	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

local cached: Remotes? = nil

local WeaponRemotes = {}

-- Returns all weapon remotes. Safe to call many times; it only builds them once.
function WeaponRemotes.get(): Remotes
	if cached then
		return cached
	end
	local folder = getFolder()
	local remotes: Remotes = {
		Fire = getRemote(folder, "Fire"),
		Equip = getRemote(folder, "Equip"),
		Reload = getRemote(folder, "Reload"),
		State = getRemote(folder, "State"),
		HitConfirm = getRemote(folder, "HitConfirm"),
		ShotFx = getRemote(folder, "ShotFx"),
	}
	cached = remotes
	return remotes
end

return WeaponRemotes

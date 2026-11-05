--!strict
--[[
	ShopRemotes: the two "phone lines" the shop uses.

	The server creates them in ReplicatedStorage > ShopRemotes and the client
	waits for them. The client can only ASK; the server decides.

	  BuyItem    client -> server  (itemId)  returns (ok, message)  "Please buy item X"
	  EquipItem  client -> server  (itemId)  returns (ok, message)  "Please equip item X"

	What the player owns and wears is sent back to everyone through
	attributes on the Player (see Shared/Data/GameContract).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "ShopRemotes"

export type Remotes = {
	BuyItem: RemoteFunction,
	EquipItem: RemoteFunction,
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

local function getRemote(folder: Instance, name: string): RemoteFunction
	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing and existing:IsA("RemoteFunction") then
			return existing
		end
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name) :: RemoteFunction
end

local cached: Remotes? = nil

local ShopRemotes = {}

function ShopRemotes.get(): Remotes
	if cached then
		return cached
	end
	local folder = getFolder()
	local remotes: Remotes = {
		BuyItem = getRemote(folder, "BuyItem"),
		EquipItem = getRemote(folder, "EquipItem"),
	}
	cached = remotes
	return remotes
end

return ShopRemotes

--!strict
--[[
	MovementNet
	===========
	The two "phone lines" between client and server for movement:

	  Request (client -> server): "I want to Dash / DoubleJump / Slide."
	  Result  (server -> client): "Allowed or not, and when you may do it again."

	The server creates the remotes; the client waits for them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Action = "Dash" | "DoubleJump" | "Slide"

export type Remotes = {
	Request: RemoteEvent,
	Result: RemoteEvent,
}

local FOLDER_NAME = "MovementRemotes"

local MovementNet = {}

-- Checks that a value sent by a client is one of our known actions.
function MovementNet.isAction(value: unknown): boolean
	return value == "Dash" or value == "DoubleJump" or value == "Slide"
end

local function getOrCreateRemote(folder: Instance, name: string): RemoteEvent
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local function waitForRemote(folder: Instance, name: string): RemoteEvent
	local remote = folder:WaitForChild(name)
	assert(remote:IsA("RemoteEvent"), `{name} should be a RemoteEvent`)
	return remote
end

local cached: Remotes? = nil

function MovementNet.get(): Remotes
	if cached then
		return cached
	end

	local remotes: Remotes
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			local newFolder = Instance.new("Folder")
			newFolder.Name = FOLDER_NAME
			newFolder.Parent = ReplicatedStorage
			folder = newFolder
		end
		assert(folder, "MovementRemotes folder missing")
		remotes = {
			Request = getOrCreateRemote(folder, "Request"),
			Result = getOrCreateRemote(folder, "Result"),
		}
	else
		local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
		remotes = {
			Request = waitForRemote(folder, "Request"),
			Result = waitForRemote(folder, "Result"),
		}
	end

	cached = remotes
	return remotes
end

return MovementNet

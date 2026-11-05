--!strict
--[[
	MovementNet: the movement system's two remotes (listed in Shared/Net/Net.luau).

	  Request (client -> server): "I want to Dash / DoubleJump / Slide."
	  Result  (server -> client): "Allowed or not, and when you may do it again."
]]

local Net = require(script.Parent:WaitForChild("Net"))

export type Action = "Dash" | "DoubleJump" | "Slide"

export type Remotes = {
	Request: RemoteEvent,
	Result: RemoteEvent,
}

local MovementNet = {}

-- Checks that a value sent by a client is one of our known actions.
function MovementNet.isAction(value: unknown): boolean
	return value == "Dash" or value == "DoubleJump" or value == "Slide"
end

local cached: Remotes? = nil

function MovementNet.get(): Remotes
	if cached then
		return cached
	end
	local remotes: Remotes = {
		Request = Net.event("MovementRequest"),
		Result = Net.event("MovementResult"),
	}
	cached = remotes
	return remotes
end

return MovementNet

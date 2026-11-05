--!strict
--[[
	RateLimiter: stops a player from spamming a remote.

	Usage (server):
		local limiter = RateLimiter.new(5, 1) -- at most 5 requests per 1 second
		remote.OnServerEvent:Connect(function(player)
			if not limiter:allow(player) then
				return -- too fast, ignore it
			end
			...
		end)

	It forgets players automatically when they leave.
]]

local Players = game:GetService("Players")

export type RateLimiter = {
	allow: (self: RateLimiter, player: Player) -> boolean,
}

type Window = {
	startedAt: number,
	count: number,
}

local RateLimiter = {}

function RateLimiter.new(maxRequests: number, windowSeconds: number): RateLimiter
	local windows: { [Player]: Window } = {}

	Players.PlayerRemoving:Connect(function(player: Player)
		windows[player] = nil
	end)

	local limiter = {}

	function limiter.allow(_self: RateLimiter, player: Player): boolean
		local now = os.clock()
		local window = windows[player]
		if window == nil or now - window.startedAt >= windowSeconds then
			windows[player] = { startedAt = now, count = 1 }
			return true
		end
		window.count += 1
		return window.count <= maxRequests
	end

	return (limiter :: any) :: RateLimiter
end

return RateLimiter

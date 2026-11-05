--!strict
--[[
	RateLimiter
	Stops a player (or a cheat script) from spamming a remote thousands of
	times a second. Usage:

		local canBuy = RateLimiter.new(6, 2) -- at most 6 calls every 2 seconds
		if not canBuy(player) then return end
]]

local Players = game:GetService("Players")

type Window = { count: number, startedAt: number }

local RateLimiter = {}

function RateLimiter.new(maxCalls: number, perSeconds: number): (Player) -> boolean
	local windows: { [Player]: Window } = {}

	-- Forget players who leave, so this table doesn't grow forever.
	Players.PlayerRemoving:Connect(function(player: Player)
		windows[player] = nil
	end)

	return function(player: Player): boolean
		local now = os.clock()
		local window = windows[player]
		if not window or now - window.startedAt >= perSeconds then
			windows[player] = { count = 1, startedAt = now }
			return true
		end
		if window.count >= maxCalls then
			return false
		end
		window.count += 1
		return true
	end
end

return RateLimiter

--!strict
--[[
	VoteService: map voting for one match (the voting logic only; the
	cards on screen are client/Controllers/TransitionController).

	  * Every map is offered, always in the same order (MapConfig.Order).
	  * Only the match's players can vote, only for an offered map, and not
	    faster than a few times a second. Changing your vote is allowed.
	  * Live counts are shared as attributes (Votes<MapId>) on MatchState.
	  * Most votes wins; a tie (including no votes) is broken at random.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local MatchState = require(ReplicatedStorage.Shared.Match.MatchState)
local Net = require(ReplicatedStorage.Shared.Net.Net)
local RateLimiter = require(script.Parent.Parent.Components.RateLimiter)

local VoteService = {}

local random = Random.new()
local limiter = RateLimiter.new(4, 1)

-- The maps to vote on, always in the same order (MapConfig.Order). If there
-- are more maps than MaxChoices, a random few are offered, still in that order.
function VoteService.pickOptions(): { string }
	if #MapConfig.Order <= MapConfig.MaxChoices then
		return table.clone(MapConfig.Order)
	end
	local chosen: { [string]: boolean } = {}
	local pool = table.clone(MapConfig.Order)
	for _ = 1, MapConfig.MaxChoices do
		chosen[table.remove(pool, random:NextInteger(1, #pool)) :: string] = true
	end
	local options: { string } = {}
	for _, mapId in MapConfig.Order do
		if chosen[mapId] then
			table.insert(options, mapId)
		end
	end
	return options
end

--[[
	Runs a vote among `voters` for `seconds` and returns the winning map Id.
	Yields. `stateFolder` is ReplicatedStorage.MatchState.
]]
function VoteService.run(stateFolder: Folder, voters: { [Player]: any }, options: { string }, seconds: number): string
	local votes: { [Player]: string } = {}
	local function publish()
		local counts: { [string]: number } = {}
		for _, mapId in votes do
			counts[mapId] = (counts[mapId] or 0) + 1
		end
		for _, mapId in options do
			stateFolder:SetAttribute("Votes" .. mapId, counts[mapId] or 0)
		end
		return counts
	end

	stateFolder:SetAttribute(MatchState.Attr.VoteOptions, table.concat(options, ","))
	publish()

	local connection = Net.event("MapVote").OnServerEvent:Connect(function(player: Player, mapRaw: unknown)
		if voters[player] == nil or not limiter:allow(player) then
			return
		end
		if typeof(mapRaw) ~= "string" or not table.find(options, mapRaw) then
			return
		end
		votes[player] = mapRaw
		publish()
	end)

	task.wait(seconds)
	connection:Disconnect()

	-- Count, then break ties at random.
	local counts = publish()
	local best = -1
	local leaders: { string } = {}
	for _, mapId in options do
		local count = counts[mapId] or 0
		if count > best then
			best = count
			leaders = { mapId }
		elseif count == best then
			table.insert(leaders, mapId)
		end
	end
	stateFolder:SetAttribute(MatchState.Attr.VoteOptions, "")
	return leaders[random:NextInteger(1, #leaders)]
end

return VoteService

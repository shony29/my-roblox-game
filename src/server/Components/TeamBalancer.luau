--!strict
--[[
	TeamBalancer: splits players into two even teams.
	Pure logic (no Roblox objects changed), so it's easy to reason about.

	Players are shuffled, then dealt out like cards: A, B, A, B, ...
	so team sizes never differ by more than one.
]]

local TeamBalancer = {}

function TeamBalancer.split<T>(players: { T }, random: Random?): ({ T }, { T })
	local rng = random or Random.new()
	local shuffled = table.clone(players)
	for i = #shuffled, 2, -1 do
		local j = rng:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	local teamA: { T }, teamB: { T } = {}, {}
	for index, player in shuffled do
		table.insert(if index % 2 == 1 then teamA else teamB, player)
	end
	return teamA, teamB
end

return TeamBalancer

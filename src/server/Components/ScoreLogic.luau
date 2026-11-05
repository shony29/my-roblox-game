--!strict
-- ScoreLogic: small "pure" helpers with no Roblox side effects, so they are
-- easy to reason about and easy to test.

local ScoreLogic = {}

-- Returns everyone tied for the highest score, plus that score.
-- Works with any key type (Players in the game, plain strings in tests).
function ScoreLogic.findLeaders<K>(scores: { [K]: number }): ({ K }, number)
	local leaders: { K } = {}
	local best = 0
	for key, score in scores do
		if score > best then
			best = score
			leaders = { key }
		elseif score == best and score > 0 then
			table.insert(leaders, key)
		end
	end
	return leaders, best
end

-- Turns the leaders into the sentence shown at the end of a round.
function ScoreLogic.describeWinners(names: { string }, score: number): string
	if #names == 0 or score <= 0 then
		return "Nobody scored this round"
	elseif #names == 1 then
		return `{names[1]} wins with {score}!`
	end
	table.sort(names)
	return `Tie! {table.concat(names, ", ")} with {score}`
end

return ScoreLogic

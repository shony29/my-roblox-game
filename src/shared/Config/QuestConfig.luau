--!strict
--[[
	QuestConfig: everything in the Tasks panel.

	  * Beginner tasks teach the basics. They stay until they're done.
	  * Daily quests start fresh every day at midnight (UTC time, so every
	    server agrees on when a day starts).
	Each task pays its coins the moment it's finished (Services/QuestService).

	"Stat" is what counts toward a task. The game calls
	QuestService.progress(player, stat) whenever that thing happens:
	  VisitRange    went into the practice range
	  BreakTargets  popped a practice target
	  Slide         did a slide
	  PlayMatch     finished a real match (not practice against bots)
	  Elimination   eliminated someone in a real match
	  WinMatch      won a real match

	Want a new task? Copy a line, give it a new Id (B_ for beginner, D_ for
	daily) and pick one of the stats above.
]]

export type Quest = {
	Id: string,
	Stat: string,
	Text: string,
	Goal: number,
	Reward: number, -- coins
	Icon: string,
}

export type QuestState = { progress: number, done: boolean }

local QuestConfig = {}

QuestConfig.Beginner = {
	{ Id = "B_Range", Stat = "VisitRange", Text = "Visit the practice range", Goal = 1, Reward = 10, Icon = "🎯" },
	{ Id = "B_Targets", Stat = "BreakTargets", Text = "Pop practice targets", Goal = 5, Reward = 15, Icon = "💥" },
	{ Id = "B_Slide", Stat = "Slide", Text = "Sprint, then crouch to slide", Goal = 3, Reward = 10, Icon = "💨" },
} :: { Quest }

QuestConfig.Daily = {
	{ Id = "D_Play", Stat = "PlayMatch", Text = "Play matches", Goal = 2, Reward = 15, Icon = "🎮" },
	{ Id = "D_Elims", Stat = "Elimination", Text = "Get eliminations", Goal = 10, Reward = 20, Icon = "⚔️" },
	{ Id = "D_Win", Stat = "WinMatch", Text = "Win a match", Goal = 1, Reward = 25, Icon = "🏆" },
} :: { Quest }

-- Extra coins for winning a real match (each elimination already gives coins).
-- Rewards are kept small on purpose, so shop items stay a real goal.
QuestConfig.WIN_COINS = 10

-- Today's number: whole days since 1 January 1970, in UTC.
function QuestConfig.today(): number
	return math.floor(workspace:GetServerTimeNow() / 86400)
end

-- Seconds until the daily quests start fresh.
function QuestConfig.secondsUntilReset(): number
	local now = workspace:GetServerTimeNow()
	return (math.floor(now / 86400) + 1) * 86400 - now
end

-- Attributes can't hold tables, so progress travels as short text:
-- "B_Range:1:1,B_Targets:3:0"  (Id : progress : done).
function QuestConfig.encode(list: { Quest }, progress: { [string]: number }, done: { [string]: boolean }): string
	local parts: { string } = {}
	for _, quest in list do
		table.insert(parts, `{quest.Id}:{progress[quest.Id] or 0}:{if done[quest.Id] then 1 else 0}`)
	end
	return table.concat(parts, ",")
end

function QuestConfig.decode(value: unknown): { [string]: QuestState }
	local result: { [string]: QuestState } = {}
	if typeof(value) ~= "string" then
		return result
	end
	for id, progress, done in string.gmatch(value :: string, "([%w_]+):(%d+):(%d)") do
		result[id] = { progress = tonumber(progress) or 0, done = done == "1" }
	end
	return result
end

return QuestConfig

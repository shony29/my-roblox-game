--!strict
--[[
	QuestService: beginner tasks and daily quests.

	The game tells this service when something happens, for example
		QuestService.progress(player, "Slide")
	and it moves every matching task forward (Config/QuestConfig). A task
	that reaches its goal pays its coins at once, and the player gets a
	little "Task done! +50 coins" message.

	Everything is counted here on the server: a client can't claim progress.
	Progress is saved with the rest of the player's data (PlayerDataService).

	Also: daily quests start fresh when the day changes (midnight UTC).
	(There are no coins just for playing: coins come from eliminations,
	wins, tasks and quests.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local QuestConfig = require(Shared.Config.QuestConfig)
local Net = require(Shared.Net.Net)
local Schema = require(Shared.Data.PlayerDataSchema)
local PlayerDataService = require(script.Parent.PlayerDataService)

type Quest = QuestConfig.Quest

local CHECK_INTERVAL = 60 -- seconds between new-day checks

local QuestService = {}

local started = false

local allQuests: { Quest } = {}
for _, quest in QuestConfig.Beginner do
	table.insert(allQuests, quest)
end
for _, quest in QuestConfig.Daily do
	table.insert(allQuests, quest)
end

local function isDaily(quest: Quest): boolean
	return string.sub(quest.Id, 1, 2) == "D_"
end

-- A new day: wipe yesterday's daily quests.
local function rollDay(quests: Schema.QuestData)
	local today = QuestConfig.today()
	if quests.day ~= today then
		quests.day = today
		for _, quest in QuestConfig.Daily do
			quests.progress[quest.Id] = nil
			quests.done[quest.Id] = nil
		end
	end
end

local function toast(player: Player, text: string, coins: number)
	if player.Parent == Players then
		Net.event("RewardToast"):FireClient(player, text, coins)
	end
end

-- Counts `amount` (default 1) toward every unfinished task for `stat`.
function QuestService.progress(player: Player, stat: string, amount: number?)
	local add = math.max(1, math.floor(amount or 1))
	local finished: { Quest } = {}
	PlayerDataService.updateQuests(player, function(quests: Schema.QuestData)
		rollDay(quests)
		for _, quest in allQuests do
			if quest.Stat == stat and not quests.done[quest.Id] then
				local value = math.min((quests.progress[quest.Id] or 0) + add, quest.Goal)
				quests.progress[quest.Id] = value
				if value >= quest.Goal then
					quests.done[quest.Id] = true
					table.insert(finished, quest)
				end
			end
		end
	end)
	for _, quest in finished do
		PlayerDataService.addCoins(player, quest.Reward)
		toast(player, `{if isDaily(quest) then "Daily quest" else "Task"} done: {quest.Text}`, quest.Reward)
	end
end

-- Extra coins (match wins, ...) with the same little message.
function QuestService.reward(player: Player, coins: number, text: string)
	if PlayerDataService.addCoins(player, coins) then
		toast(player, text, coins)
	end
end

local function checkPlayers()
	for _, player in Players:GetPlayers() do
		-- A new day: show fresh daily quests even before any progress.
		local data = PlayerDataService.getData(player)
		if data and data.quests.day ~= QuestConfig.today() then
			PlayerDataService.updateQuests(player, rollDay)
		end
	end
end

function QuestService.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			local ok, err = pcall(checkPlayers)
			if not ok then
				warn("[QuestService] check failed:", err)
			end
		end
	end)
end

return QuestService

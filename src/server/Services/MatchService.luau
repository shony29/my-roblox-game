--!strict
--[[
	MatchService: runs matches from start to finish. The server is the only
	one who changes match state; clients just read MatchState attributes.

	  1. QueueService hands over players when a mode's queue is full
	     (MatchService.startMatch). Teams are balanced (MatchFound).
	  3. Each round: everyone respawns on their team's side, frozen, with full
	     health and ammo (Countdown) -> combat (InMatch) -> RoundEnd.
	     Eliminated players sit out until the next round.
	  4. A round ends when one team has nobody left, or the timer runs out
	     (more players alive wins, then more total health, else a draw).
	  5. First team to win RoundsToWin rounds wins (MatchResults), wins are
	     saved, then everyone goes back to the lobby (Returning).

	Safety: only one match runs at a time; firing and damage are only allowed
	during InMatch, by alive participants, against the other team
	(Components/CombatRules). If a whole team leaves, the other team wins.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local ModeConfig = require(Shared.Config.ModeConfig)
local SpawnConfig = require(Shared.Config.SpawnConfig)
local MatchState = require(Shared.Match.MatchState)
local MapConfig = require(Shared.Config.MapConfig)
local Schema = require(Shared.Data.PlayerDataSchema)
local Progression = require(Shared.Data.Progression)
local Net = require(Shared.Net.Net)
local GameContract = require(Shared.Net.GameContract)
local Components = script.Parent.Parent.Components
local CombatRules = require(Components.CombatRules)
local TeamBalancer = require(Components.TeamBalancer)
local RateLimiter = require(Components.RateLimiter)
local PlayerDataService = require(script.Parent.PlayerDataService)
local SpawnService = require(script.Parent.SpawnService)
local BotService = require(script.Parent.BotService)
local LobbyService = require(script.Parent.LobbyService)
local MapService = require(script.Parent.MapService)
local VoteService = require(script.Parent.VoteService)

type State = MatchState.State
type TeamId = MatchState.TeamId
type Mode = ModeConfig.Mode

type Participant = {
	player: Player,
	team: TeamId,
	alive: boolean,
	eliminations: number,
	deaths: number,
	damage: number,
	connections: { RBXScriptConnection },
}

type BotEntry = {
	team: TeamId,
	alive: boolean,
	name: string,
}

type Match = {
	mode: Mode,
	participants: { [Player]: Participant },
	score: { [TeamId]: number },
	round: number,
	state: State,
	forfeitWinner: TeamId?,
	withBots: boolean, -- practice: bots fill the empty places
	bots: { [Model]: BotEntry },
}

local MATCH_FOUND_TIME = 2
local RESULTS_TIME = 10 -- seconds on the results screen (rematch voting happens here)
local RETURN_TIME = 1
local POLL = 0.1

local ATTR = MatchState.Attr
local PATTR = MatchState.PlayerAttr

local MatchService = {}

local stateFolder: Folder
local endedListeners: { () -> () } = {}
local rematchLimiter = RateLimiter.new(2, 1)
local current: Match? = nil
local started = false

---------------------------------------------------------------------------
-- Shared state
---------------------------------------------------------------------------

local function setState(state: State, duration: number?)
	BotService.setActive(state == "InMatch")
	local match = current
	if match then
		match.state = state
	end
	stateFolder:SetAttribute(ATTR.State, state)
	stateFolder:SetAttribute(ATTR.PhaseEndsAt, if duration then Workspace:GetServerTimeNow() + duration else 0)
end

local function publishScore(match: Match)
	stateFolder:SetAttribute(ATTR.ScoreA, match.score.A or 0)
	stateFolder:SetAttribute(ATTR.ScoreB, match.score.B or 0)
end

local function setStatus(player: Player, status: string)
	if player.Parent == Players then
		player:SetAttribute(PATTR.Status, status)
	end
end

---------------------------------------------------------------------------
-- Combat rules (who may shoot whom, and when)
---------------------------------------------------------------------------

local function canFire(shooter: Player): boolean
	local match = current
	if match then
		local participant = match.participants[shooter]
		if participant then
			return match.state == "InMatch" and participant.alive
		end
	end
	-- Not in a match: no shooting (the lobby has no guns).
	return false
end

local function canDamage(attacker: Player, victim: Player?, victimModel: Model?): boolean
	local match = current
	local attackerInfo = if match then match.participants[attacker] else nil
	if match and attackerInfo then
		if match.state ~= "InMatch" then
			return false
		end
		if victim == nil then
			-- A bot: only hurt it if it's on the other team.
			local bot = if victimModel then match.bots[victimModel] else nil
			return bot == nil or bot.team ~= attackerInfo.team
		end
		local victimInfo = match.participants[victim]
		return victimInfo ~= nil and victimInfo.team ~= attackerInfo.team
	end
	-- Not in a match: nobody can be hurt.
	return false
end

local function onDamage(attacker: Player, _victim: Player?, amount: number)
	local match = current
	local participant = match and match.participants[attacker]
	if participant then
		participant.damage += amount
		attacker:SetAttribute(PATTR.Damage, math.floor(participant.damage))
	end
end

---------------------------------------------------------------------------
-- Participants
---------------------------------------------------------------------------

local function getKiller(humanoid: Humanoid): Player?
	local tag = humanoid:FindFirstChild("creator")
	if tag and tag:IsA("ObjectValue") then
		local value = tag.Value
		if value and value:IsA("Player") then
			return value
		end
	end
	return nil
end

local function watchCharacter(match: Match, participant: Participant, character: Model)
	local found = character:WaitForChild("Humanoid", 10)
	if not found or not found:IsA("Humanoid") then
		return
	end
	local humanoid = found :: Humanoid
	humanoid.Died:Once(function()
		if current ~= match or match.participants[participant.player] ~= participant or not participant.alive then
			return
		end
		participant.alive = false
		participant.deaths += 1
		participant.player:SetAttribute(PATTR.Deaths, participant.deaths)

		local killer = getKiller(humanoid)
		local killerInfo = if killer then match.participants[killer] else nil
		local credited: Player? = nil
		if killerInfo and killerInfo.team ~= participant.team then
			killerInfo.eliminations += 1
			killerInfo.player:SetAttribute(PATTR.Eliminations, killerInfo.eliminations)
			credited = killerInfo.player
		end
		-- Kill feed, scoreboard numbers, saved eliminations and coins.
		local botName = humanoid:GetAttribute("LastHitBy")
		PlayerDataService.recordElimination(credited, participant.player, if typeof(botName) == "string" then botName else nil)
	end)
end

local function addParticipant(match: Match, player: Player, team: TeamId)
	local participant: Participant = {
		player = player,
		team = team,
		alive = false,
		eliminations = 0,
		deaths = 0,
		damage = 0,
		connections = {},
	}
	match.participants[player] = participant
	player:SetAttribute(PATTR.Team, team)
	player:SetAttribute(PATTR.Eliminations, 0)
	player:SetAttribute(PATTR.Deaths, 0)
	player:SetAttribute(PATTR.Damage, 0)
	setStatus(player, "InMatch")
	LobbyService.useMatchCamera(player)
	table.insert(participant.connections, player.CharacterAdded:Connect(function(character: Model)
		watchCharacter(match, participant, character)
	end))
end

local function removeParticipant(match: Match, player: Player, toLobby: boolean?)
	local participant = match.participants[player]
	if not participant then
		return
	end
	for _, connection in participant.connections do
		connection:Disconnect()
	end
	match.participants[player] = nil
	if player.Parent == Players then
		player:SetAttribute(PATTR.Team, nil)
		setStatus(player, "Lobby")
		local character = player.Character
		if character then
			character:Destroy() -- out of the arena...
		end
		if toLobby ~= false then
			task.spawn(LobbyService.spawn, player) -- ...and back to the lobby
		end
	end
end

local function teamCount(match: Match, team: TeamId, aliveOnly: boolean): number
	local count = 0
	for _, participant in match.participants do
		if participant.team == team and (participant.alive or not aliveOnly) then
			count += 1
		end
	end
	for _, bot in match.bots do
		if bot.team == team and (bot.alive or not aliveOnly) then
			count += 1
		end
	end
	return count
end

local function teamHealth(match: Match, team: TeamId): number
	local total = 0
	for player, participant in match.participants do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if participant.team == team and participant.alive and humanoid then
			total += humanoid.Health
		end
	end
	for model, bot in match.bots do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if bot.team == team and bot.alive and humanoid then
			total += humanoid.Health
		end
	end
	return total
end

---------------------------------------------------------------------------
-- Rounds
---------------------------------------------------------------------------

-- Respawns every participant on their side, frozen until the countdown ends.
-- Practice matches: bots fill every empty place on both teams.
local function spawnBots(match: Match)
	BotService.removeAll()
	table.clear(match.bots)
	for _, team in { "A", "B" } :: { TeamId } do
		local humans = 0
		for _, participant in match.participants do
			if participant.team == team then
				humans += 1
			end
		end
		for _ = 1, match.mode.TeamSize - humans do
			local model = BotService.spawn(team, SpawnService.chooseSpawn(nil, team))
			local root = model:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				root.Anchored = true -- frozen until the countdown ends, like players
			end
			local entry: BotEntry = { team = team, alive = true, name = model.Name }
			match.bots[model] = entry
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Died:Once(function()
					if current ~= match or match.bots[model] ~= entry then
						return
					end
					entry.alive = false
					local killer = getKiller(humanoid)
					local killerInfo = if killer then match.participants[killer] else nil
					if killerInfo and killerInfo.team ~= team then
						killerInfo.eliminations += 1
						killerInfo.player:SetAttribute(PATTR.Eliminations, killerInfo.eliminations)
					end
					local lastHit = humanoid:GetAttribute("LastHitBy")
					local killerName = if killerInfo then killerInfo.player.DisplayName elseif typeof(lastHit) == "string" then lastHit else nil
					PlayerDataService.announceElimination(killerName, entry.name)
				end)
			end
		end
	end
end

local function spawnAll(match: Match)
	if match.withBots then
		spawnBots(match)
	end
	local pending = 0
	for player, participant in match.participants do
		pending += 1
		participant.alive = false
		task.spawn(function()
			local character = SpawnService.spawn(player, participant.team)
			if character and match.participants[player] == participant then
				participant.alive = true
				local root = character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					root.Anchored = true
				end
			end
			pending -= 1
		end)
	end
	local waited = 0
	while pending > 0 and waited < SpawnConfig.LOAD_TIMEOUT do
		waited += task.wait(POLL)
	end
end

local function unfreezeAll(match: Match)
	for model in match.bots do
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.Anchored = false
			BotService.release(model)
		end
	end
	for player in match.participants do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.Anchored = false
		end
	end
end

-- Waits, but stops early if the match is forfeited.
local function waitFor(match: Match, seconds: number)
	local deadline = os.clock() + seconds
	while os.clock() < deadline and not match.forfeitWinner do
		task.wait(POLL)
	end
end

-- Returns (winner or nil for a draw, whether the round is decided).
local function checkRound(match: Match): (TeamId?, boolean)
	if match.forfeitWinner then
		return match.forfeitWinner, true
	end
	local aliveA, aliveB = teamCount(match, "A", true), teamCount(match, "B", true)
	if aliveA == 0 and aliveB == 0 then
		return nil, true
	elseif aliveA == 0 then
		return "B", true
	elseif aliveB == 0 then
		return "A", true
	end
	return nil, false
end

-- Timer ran out: more players alive wins, then more total health.
local function winnerOnTime(match: Match): TeamId?
	local aliveA, aliveB = teamCount(match, "A", true), teamCount(match, "B", true)
	if aliveA ~= aliveB then
		return if aliveA > aliveB then "A" else "B"
	end
	local healthA, healthB = teamHealth(match, "A"), teamHealth(match, "B")
	if math.abs(healthA - healthB) >= 1 then
		return if healthA > healthB then "A" else "B"
	end
	return nil
end

local function isOver(match: Match): boolean
	local toWin = match.mode.RoundsToWin
	return match.forfeitWinner ~= nil or (match.score.A or 0) >= toWin or (match.score.B or 0) >= toWin
end

local function playRound(match: Match)
	local mode = match.mode
	match.round += 1
	stateFolder:SetAttribute(ATTR.Round, match.round)
	stateFolder:SetAttribute(ATTR.RoundWinner, "")

	spawnAll(match)
	setState("Countdown", mode.CountdownTime)
	waitFor(match, mode.CountdownTime)
	unfreezeAll(match)
	if match.forfeitWinner then
		return
	end

	setState("InMatch", mode.RoundTime)
	GameContract.setRoundTimeRemaining(mode.RoundTime)
	local deadline = os.clock() + mode.RoundTime
	local winner: TeamId?, decided = nil, false
	while os.clock() < deadline do
		winner, decided = checkRound(match)
		if decided then
			break
		end
		task.wait(POLL)
	end
	if not decided then
		winner = winnerOnTime(match)
	end
	GameContract.setRoundTimeRemaining(nil)

	if winner then
		match.score[winner] = (match.score[winner] or 0) + 1
	end
	publishScore(match)
	stateFolder:SetAttribute(ATTR.RoundWinner, winner or "")
	setState("RoundEnd", mode.RoundEndTime)
	waitFor(match, mode.RoundEndTime)
end

---------------------------------------------------------------------------
-- Matches
---------------------------------------------------------------------------

-- Sends each participant the results screen data.
local function sendResults(match: Match, winner: TeamId?)
	local rows = {}
	local mvp: Participant? = nil
	for player, participant in match.participants do
		table.insert(rows, {
			name = player.DisplayName,
			team = participant.team,
			eliminations = participant.eliminations,
			deaths = participant.deaths,
			damage = math.floor(participant.damage),
			coins = if match.withBots then 0 else participant.eliminations * Schema.COINS_PER_ELIMINATION,
			xp = if match.withBots then 0 else Progression.matchXp(participant.eliminations, winner ~= nil and participant.team == winner),
		})
		if mvp == nil
			or participant.eliminations > mvp.eliminations
			or (participant.eliminations == mvp.eliminations and participant.damage > mvp.damage)
		then
			mvp = participant
		end
	end
	local results = {
		mode = match.mode.DisplayName,
		winner = winner or "",
		scoreA = match.score.A or 0,
		scoreB = match.score.B or 0,
		mvp = if mvp then mvp.player.DisplayName else "",
		players = rows,
	}
	local remote = Net.event("MatchResults")
	for player in match.participants do
		remote:FireClient(player, results)
	end
end

local function runMatch(match: Match, players: { Player })
	local teamA, teamB = TeamBalancer.split(players)
	if match.withBots then
		teamA, teamB = players, {} -- practice: humans together, bots fill the rest
	end
	for _, player in teamA do
		addParticipant(match, player, "A")
	end
	for _, player in teamB do
		addParticipant(match, player, "B")
	end
	PlayerDataService.resetRoundStats() -- clears the scoreboard's ELIMS / DEATHS
	stateFolder:SetAttribute(ATTR.Mode, match.mode.Id)
	stateFolder:SetAttribute(ATTR.RoundsToWin, match.mode.RoundsToWin)
	stateFolder:SetAttribute(ATTR.Round, 0)
	stateFolder:SetAttribute(ATTR.MatchWinner, "")
	publishScore(match)
	setState("MatchFound", MATCH_FOUND_TIME)
	waitFor(match, MATCH_FOUND_TIME)

	-- Map voting (only when there are 2+ maps), then build the chosen map.
	local mapId = MapService.currentId() or MapConfig.Default
	local options = VoteService.pickOptions()
	if #options >= 2 and not match.forfeitWinner then
		setState("MapVoting", MapConfig.VoteTime)
		mapId = VoteService.run(stateFolder, match.participants, options, MapConfig.VoteTime)
	end
	stateFolder:SetAttribute(ATTR.MapId, mapId)
	if mapId ~= MapService.currentId() then
		setState("Loading")
		if not MapService.load(mapId) then
			MapService.load(MapConfig.Default) -- fall back to a map we know works
			stateFolder:SetAttribute(ATTR.MapId, MapConfig.Default)
		end
	end

	while not isOver(match) do
		playRound(match)
	end

	-- Results (all numbers come from the server, so they can be trusted).
	local scoreA, scoreB = match.score.A or 0, match.score.B or 0
	local winner: TeamId? = match.forfeitWinner
		or (if scoreA > scoreB then "A" elseif scoreB > scoreA then "B" else nil)
	stateFolder:SetAttribute(ATTR.MatchWinner, winner or "")
	for player, participant in match.participants do
		local won = winner ~= nil and participant.team == winner
		if not match.withBots then -- practice against bots gives no rewards
			if won then
				PlayerDataService.recordWin(player)
			end
			PlayerDataService.addXp(player, Progression.matchXp(participant.eliminations, won))
		end
	end
	BotService.removeAll()
	sendResults(match, winner)

	-- Rematch: if everyone still here presses REMATCH, the same players play again.
	local rematchVotes: { [Player]: boolean } = {}
	local function countVotes(): (number, number)
		local total, voted = 0, 0
		for player in match.participants do
			total += 1
			if rematchVotes[player] then
				voted += 1
			end
		end
		return total, voted
	end
	local total = countVotes()
	stateFolder:SetAttribute(ATTR.RematchVotes, 0)
	stateFolder:SetAttribute(ATTR.RematchNeeded, total)
	local rematchConnection = Net.event("RematchVote").OnServerEvent:Connect(function(player: Player)
		if match.participants[player] and rematchLimiter:allow(player) then
			rematchVotes[player] = true
			local _, voted = countVotes()
			stateFolder:SetAttribute(ATTR.RematchVotes, voted)
		end
	end)
	local function everyoneWantsRematch(): boolean
		local count, voted = countVotes()
		return count >= 2 and voted == count
	end
	setState("MatchResults", RESULTS_TIME)
	local deadline = os.clock() + RESULTS_TIME
	while os.clock() < deadline and not everyoneWantsRematch() do
		task.wait(POLL)
	end
	rematchConnection:Disconnect()
	local rematch = everyoneWantsRematch()

	-- Clean up: back to the lobby, or straight into the rematch.
	setState("Returning", RETURN_TIME)
	local returning: { Player } = {}
	for player in match.participants do
		table.insert(returning, player)
	end
	for _, player in returning do
		removeParticipant(match, player, not rematch)
	end
	task.wait(RETURN_TIME)
	current = nil
	setState("Lobby")
	GameContract.setRoundTimeRemaining(nil)

	if rematch then
		local stillHere: { Player } = {}
		for _, player in returning do
			if player.Parent == Players then
				table.insert(stillHere, player)
			end
		end
		if #stillHere == #returning and MatchService.startMatch(match.mode, stillHere, match.withBots) then
			return
		end
		for _, player in stillHere do
			task.spawn(LobbyService.spawn, player) -- someone left: everyone back to the lobby
		end
	end

	-- Let the queue start the next match if enough players are waiting.
	for _, listener in endedListeners do
		task.spawn(listener)
	end
end

-- True while a match is running (there is one arena, so one match at a time).
function MatchService.isBusy(): boolean
	return current ~= nil
end

-- Called with no arguments after every match, once players are back in the lobby.
function MatchService.onMatchEnded(listener: () -> ())
	table.insert(endedListeners, listener)
end

-- Starts a match for exactly these players. Returns false if one is already running.
function MatchService.startMatch(mode: Mode, players: { Player }, withBots: boolean?): boolean
	if current then
		return false
	end
	local match: Match = {
		mode = mode,
		participants = {},
		score = { A = 0, B = 0 },
		round = 0,
		state = "MatchFound",
		forfeitWinner = nil,
		withBots = withBots == true,
		bots = {},
	}
	current = match -- set before anything yields, so two matches can never start
	task.spawn(runMatch, match, players)
	return true
end

local function onPlayerRemoving(player: Player)
	local match = current
	if match and match.participants[player] then
		removeParticipant(match, player)
		-- A team with nobody left forfeits (in practice: no humans left at all).
		local humansLeft = next(match.participants) ~= nil
		if match.withBots and not humansLeft then
			match.forfeitWinner = "B"
		elseif not match.forfeitWinner then
			if teamCount(match, "A", false) == 0 then
				match.forfeitWinner = "B"
			elseif teamCount(match, "B", false) == 0 then
				match.forfeitWinner = "A"
			end
		end
	end
end

function MatchService.start()
	if started then
		return
	end
	started = true

	stateFolder = Instance.new("Folder")
	stateFolder.Name = MatchState.FOLDER_NAME
	stateFolder:SetAttribute(ATTR.ScoreA, 0)
	stateFolder:SetAttribute(ATTR.ScoreB, 0)
	stateFolder:SetAttribute(ATTR.Round, 0)
	stateFolder.Parent = ReplicatedStorage
	setState("Lobby")

	-- We decide when and where people spawn (also set in default.project.json).
	Players.CharacterAutoLoads = false
	-- The rules ask about the current match each time, so set them once.
	CombatRules.setRules(canFire, canDamage)
	CombatRules.onDamage(onDamage)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return MatchService

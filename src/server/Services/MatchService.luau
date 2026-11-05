--!strict
--[[
	MatchService: runs matches from start to finish. The server is the only
	one who changes match state; clients just read MatchState attributes.

	  1. Players who press Play join the queue (Phase 6 adds a real lobby and
	     mode picker; for now everyone queues for the default mode, 1v1 Duel).
	  2. When enough players are queued: teams are balanced (MatchFound).
	  3. Each round: everyone respawns on their team's side, frozen, with full
	     health and ammo (Countdown) -> combat (InMatch) -> RoundEnd.
	     Eliminated players sit out until the next round.
	  4. A round ends when one team has nobody left, or the timer runs out
	     (more players alive wins, then more total health, else a draw).
	  5. First team to win RoundsToWin rounds wins (MatchResults), wins are
	     saved, then everyone is cleaned up (Returning) and re-queued.

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
local GameContract = require(Shared.Net.GameContract)
local Components = script.Parent.Parent.Components
local CombatRules = require(Components.CombatRules)
local TeamBalancer = require(Components.TeamBalancer)
local PlayerDataService = require(script.Parent.PlayerDataService)
local SpawnService = require(script.Parent.SpawnService)

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

type Match = {
	mode: Mode,
	participants: { [Player]: Participant },
	score: { [TeamId]: number },
	round: number,
	state: State,
	forfeitWinner: TeamId?,
}

local MATCH_FOUND_TIME = 2
local RESULTS_TIME = 6
local RETURN_TIME = 1
local POLL = 0.1

local ATTR = MatchState.Attr
local PATTR = MatchState.PlayerAttr

local MatchService = {}

local stateFolder: Folder
local queue: { Player } = {}
local current: Match? = nil
local started = false

---------------------------------------------------------------------------
-- Shared state
---------------------------------------------------------------------------

local function setState(state: State, duration: number?)
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
	if not match or match.state ~= "InMatch" then
		return false
	end
	local participant = match.participants[shooter]
	return participant ~= nil and participant.alive
end

local function canDamage(attacker: Player, victim: Player?): boolean
	local match = current
	if not match or match.state ~= "InMatch" then
		return false
	end
	local attackerInfo = match.participants[attacker]
	if not attackerInfo then
		return false
	end
	if victim == nil then
		return true -- practice dummies and other non-player targets
	end
	local victimInfo = match.participants[victim]
	return victimInfo ~= nil and victimInfo.team ~= attackerInfo.team
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
		PlayerDataService.recordElimination(credited, participant.player)
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
	table.insert(participant.connections, player.CharacterAdded:Connect(function(character: Model)
		watchCharacter(match, participant, character)
	end))
end

local function removeParticipant(match: Match, player: Player)
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
			character:Destroy() -- back out of the arena
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
	return total
end

---------------------------------------------------------------------------
-- Rounds
---------------------------------------------------------------------------

-- Respawns every participant on their side, frozen until the countdown ends.
local function spawnAll(match: Match)
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

local enqueue: (Player) -> ()

local function runMatch(match: Match, players: { Player })
	local teamA, teamB = TeamBalancer.split(players)
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
	CombatRules.setRules(canFire, canDamage)
	waitFor(match, MATCH_FOUND_TIME)

	while not isOver(match) do
		playRound(match)
	end

	-- Results.
	local scoreA, scoreB = match.score.A or 0, match.score.B or 0
	local winner: TeamId? = match.forfeitWinner
		or (if scoreA > scoreB then "A" elseif scoreB > scoreA then "B" else nil)
	stateFolder:SetAttribute(ATTR.MatchWinner, winner or "")
	CombatRules.reset()
	setState("MatchResults", RESULTS_TIME)
	for player, participant in match.participants do
		if winner and participant.team == winner then
			PlayerDataService.recordWin(player)
		end
	end
	task.wait(RESULTS_TIME)

	-- Clean up and send everyone back.
	setState("Returning", RETURN_TIME)
	local returning: { Player } = {}
	for player in match.participants do
		table.insert(returning, player)
	end
	for _, player in returning do
		removeParticipant(match, player)
	end
	task.wait(RETURN_TIME)
	current = nil
	setState("Lobby")
	GameContract.setRoundTimeRemaining(nil)

	-- Phase 5 prototype: players who are still here queue again straight away.
	for _, player in returning do
		if player.Parent == Players then
			enqueue(player)
		end
	end
end

function MatchService.tryStart()
	if current or not started then
		return
	end
	for i = #queue, 1, -1 do
		if queue[i].Parent ~= Players then
			table.remove(queue, i)
		end
	end
	local mode = ModeConfig.Modes[ModeConfig.Default]
	local needed = mode.TeamSize * mode.TeamCount
	if #queue < needed then
		return
	end
	local players: { Player } = {}
	for _ = 1, needed do
		table.insert(players, table.remove(queue, 1) :: Player)
	end
	local match: Match = {
		mode = mode,
		participants = {},
		score = { A = 0, B = 0 },
		round = 0,
		state = "MatchFound",
		forfeitWinner = nil,
	}
	current = match -- set before anything yields, so two matches can never start
	task.spawn(runMatch, match, players)
end

enqueue = function(player: Player)
	if player.Parent ~= Players or table.find(queue, player) then
		return
	end
	local match = current
	if match and match.participants[player] then
		return
	end
	table.insert(queue, player)
	setStatus(player, "Queued")
	MatchService.tryStart()
end

local function onPlayerAdded(player: Player)
	setStatus(player, "Lobby")
	local function onPlayPressed()
		if player:GetAttribute(GameContract.PlayerAttributes.PressedPlay) == true then
			enqueue(player)
		end
	end
	player:GetAttributeChangedSignal(GameContract.PlayerAttributes.PressedPlay):Connect(onPlayPressed)
	onPlayPressed()
end

local function onPlayerRemoving(player: Player)
	local index = table.find(queue, player)
	if index then
		table.remove(queue, index)
	end
	local match = current
	if match and match.participants[player] then
		removeParticipant(match, player)
		-- A team with nobody left forfeits.
		if not match.forfeitWinner then
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
	CombatRules.reset()
	CombatRules.onDamage(onDamage)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return MatchService

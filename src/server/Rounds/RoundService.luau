--!strict
-- RoundService: runs the free-for-all round loop and owns every score.
--
--   Waiting  -> (enough players) -> Intermission (10s) -> Playing (5 min,
--   or until someone hits 25) -> Intermission showing the winner -> ...
--
-- Only this server code ever changes a score. Clients just read them.
--
-- How an elimination is counted: when a Humanoid dies, we look for an
-- ObjectValue named "creator" inside it whose Value is the Player who landed
-- the final hit. This is a long-standing Roblox convention, so the blaster
-- code just needs to add that tag before calling Humanoid:TakeDamage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RoundConfig = require(ReplicatedStorage.Shared.Rounds.RoundConfig)
local RoundState = require(ReplicatedStorage.Shared.Rounds.RoundState)
local ScoreLogic = require(script.Parent.ScoreLogic)
local SpawnService = require(script.Parent.SpawnService)

type Phase = RoundState.Phase

local RoundService = {}

local scores: { [Player]: number } = {}
local phase: Phase = "Waiting"
local roundNumber = 0
local goalReached = false

local stateFolder: Folder
local eliminatedEvent: RemoteEvent

---------------------------------------------------------------------------
-- Shared state that clients can see
---------------------------------------------------------------------------

local function createState()
	stateFolder = Instance.new("Folder")
	stateFolder.Name = RoundState.FOLDER_NAME

	eliminatedEvent = Instance.new("RemoteEvent")
	eliminatedEvent.Name = RoundState.ELIMINATED_EVENT
	eliminatedEvent.Parent = stateFolder

	stateFolder:SetAttribute(RoundState.ATTR_PHASE, phase)
	stateFolder:SetAttribute(RoundState.ATTR_ENDS_AT, 0)
	stateFolder:SetAttribute(RoundState.ATTR_ROUND_NUMBER, 0)
	stateFolder:SetAttribute(RoundState.ATTR_WINNER_TEXT, "")
	stateFolder:SetAttribute(RoundState.ATTR_WINNER_SCORE, 0)
	stateFolder.Parent = ReplicatedStorage
end

local function setPhase(newPhase: Phase, duration: number)
	phase = newPhase
	stateFolder:SetAttribute(RoundState.ATTR_PHASE, newPhase)
	-- Server time is the same on every client, so all timers stay in sync.
	stateFolder:SetAttribute(RoundState.ATTR_ENDS_AT, Workspace:GetServerTimeNow() + duration)
end

---------------------------------------------------------------------------
-- Scores
---------------------------------------------------------------------------

local function setScore(player: Player, value: number)
	scores[player] = value
	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild(RoundState.SCORE_STAT)
	if stat and stat:IsA("IntValue") then
		stat.Value = value
	end
end

local function resetAllScores()
	for _, player in Players:GetPlayers() do
		setScore(player, 0)
	end
end

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

local function onEliminated(victim: Player, killer: Player?)
	if phase ~= "Playing" then
		return -- eliminations during the break don't count
	end

	-- Only a different player who is still in the game earns a point.
	local scorer: Player? = nil
	if killer and killer ~= victim and killer.Parent == Players then
		scorer = killer
		local newScore = (scores[killer] or 0) + 1
		setScore(killer, newScore)
		if newScore >= RoundConfig.ELIMINATIONS_TO_WIN then
			goalReached = true
		end
	end

	eliminatedEvent:FireAllClients(if scorer then scorer.Name else nil, victim.Name)
end

---------------------------------------------------------------------------
-- Players joining, dying and leaving
---------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Once(function()
		onEliminated(player, getKiller(humanoid))

		-- Near-instant respawn. If something else already respawned them
		-- (like a new round starting), skip it so they don't spawn twice.
		task.delay(RoundConfig.RESPAWN_DELAY, function()
			if player.Character == character then
				SpawnService.spawn(player)
			end
		end)
	end)
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local stat = Instance.new("IntValue")
	stat.Name = RoundState.SCORE_STAT
	stat.Parent = leaderstats
	leaderstats.Parent = player
	scores[player] = 0

	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	SpawnService.spawn(player)
end

local function onPlayerRemoving(player: Player)
	scores[player] = nil
end

---------------------------------------------------------------------------
-- The round loop
---------------------------------------------------------------------------

local function respawnEveryone()
	for _, player in Players:GetPlayers() do
		task.spawn(SpawnService.spawn, player)
	end
end

local function waitForPlayers()
	if #Players:GetPlayers() >= RoundConfig.MIN_PLAYERS then
		return
	end
	setPhase("Waiting", 0)
	while #Players:GetPlayers() < RoundConfig.MIN_PLAYERS do
		task.wait(1)
	end
end

local function playRound()
	roundNumber += 1
	goalReached = false
	resetAllScores()
	stateFolder:SetAttribute(RoundState.ATTR_ROUND_NUMBER, roundNumber)
	stateFolder:SetAttribute(RoundState.ATTR_WINNER_TEXT, "")
	stateFolder:SetAttribute(RoundState.ATTR_WINNER_SCORE, 0)

	-- Everyone starts the round fresh at a spawn point.
	respawnEveryone()
	setPhase("Playing", RoundConfig.ROUND_LENGTH)

	local endsAt = os.clock() + RoundConfig.ROUND_LENGTH
	while not goalReached and os.clock() < endsAt do
		task.wait(0.1)
	end

	-- Work out who won and show it during the break.
	local leaders, topScore = ScoreLogic.findLeaders(scores)
	local names: { string } = {}
	for _, player in leaders do
		table.insert(names, player.Name)
	end
	stateFolder:SetAttribute(RoundState.ATTR_WINNER_TEXT, ScoreLogic.describeWinners(names, topScore))
	stateFolder:SetAttribute(RoundState.ATTR_WINNER_SCORE, topScore)
end

function RoundService.start()
	createState()

	Players.CharacterAutoLoads = false -- we decide when and where people spawn
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			waitForPlayers()
			setPhase("Intermission", RoundConfig.INTERMISSION_LENGTH)
			task.wait(RoundConfig.INTERMISSION_LENGTH)
			playRound()
		end
	end)
end

return RoundService

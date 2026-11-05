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
-- the final hit. The weapon system (Weapons/WeaponService) adds that tag on
-- the server just before it deals damage, so clients can't fake it.
--
-- What happens on an elimination (during a round):
--   1. The killer's round score goes up here (and the win check runs).
--   2. PlayerDataService.recordElimination updates the scoreboard numbers,
--      the saved lifetime eliminations and coins, and shows the kill feed.
--   3. The victim respawns at a safe spawn point (SpawnService).
--
-- Players only get a character after pressing Play on the main menu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RoundConfig = require(ReplicatedStorage.Shared.Config.RoundConfig)
local RoundState = require(ReplicatedStorage.Shared.Match.RoundState)
local GameContract = require(ReplicatedStorage.Shared.Net.GameContract)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ScoreLogic = require(script.Parent.Parent.Components.ScoreLogic)
local SpawnService = require(script.Parent.SpawnService)

type Phase = RoundState.Phase

local RoundService = {}

local scores: { [Player]: number } = {}
local phase: Phase = "Waiting"
local roundNumber = 0
local goalReached = false

local stateFolder: Folder

---------------------------------------------------------------------------
-- Shared state that clients can see
---------------------------------------------------------------------------

local function createState()
	stateFolder = Instance.new("Folder")
	stateFolder.Name = RoundState.FOLDER_NAME

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
	-- The main HUD's timer (UI/Hud.luau) reads this. nil hides it while waiting.
	GameContract.setRoundTimeRemaining(if newPhase == "Waiting" then nil else duration)
end

---------------------------------------------------------------------------
-- Who is playing (pressed Play on the main menu)
---------------------------------------------------------------------------

local function isReady(player: Player): boolean
	return player.Parent == Players and player:GetAttribute(GameContract.PlayerAttributes.PressedPlay) == true
end

local function readyPlayers(): { Player }
	local list: { Player } = {}
	for _, player in Players:GetPlayers() do
		if isReady(player) then
			table.insert(list, player)
		end
	end
	return list
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
	-- Also clears the ELIMS / DEATHS columns on the Tab scoreboard.
	PlayerDataService.resetRoundStats()
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

	-- Scoreboard numbers, saved eliminations + coins, and the kill feed.
	PlayerDataService.recordElimination(scorer, victim)
end

---------------------------------------------------------------------------
-- Players joining, dying and leaving
---------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local found = character:WaitForChild("Humanoid", 10)
	if not found or not found:IsA("Humanoid") then
		return
	end
	local humanoid = found :: Humanoid
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

	-- Spawn once they press Play (DataBootstrap sets this attribute).
	local function trySpawn()
		if isReady(player) and player.Character == nil then
			SpawnService.spawn(player)
		end
	end
	player:GetAttributeChangedSignal(GameContract.PlayerAttributes.PressedPlay):Connect(trySpawn)
	trySpawn()
end

local function onPlayerRemoving(player: Player)
	scores[player] = nil
end

---------------------------------------------------------------------------
-- The round loop
---------------------------------------------------------------------------

local function respawnEveryone()
	for _, player in readyPlayers() do
		task.spawn(SpawnService.spawn, player)
	end
end

local function waitForPlayers()
	if #readyPlayers() >= RoundConfig.MIN_PLAYERS then
		return
	end
	setPhase("Waiting", 0)
	while #readyPlayers() < RoundConfig.MIN_PLAYERS do
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
		table.insert(names, player.DisplayName)
		if topScore > 0 and player.Parent == Players then
			PlayerDataService.recordWin(player) -- saved "Wins" on the main menu
		end
	end
	stateFolder:SetAttribute(RoundState.ATTR_WINNER_TEXT, ScoreLogic.describeWinners(names, topScore))
	stateFolder:SetAttribute(RoundState.ATTR_WINNER_SCORE, topScore)
end

function RoundService.start()
	createState()

	-- We decide when and where people spawn. (Also set in default.project.json,
	-- so nobody spawns in the moment before this script runs.)
	Players.CharacterAutoLoads = false
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

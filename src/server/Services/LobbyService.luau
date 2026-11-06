--!strict
--[[
	LobbyService: the floating lobby island where players wait between matches.

	  * Pressing Play on the main menu puts you in the lobby (status "Lobby").
	  * In the lobby the camera is third person with a free mouse, so menus
	    are easy to click; matches switch to first person.
	  * Fall off or get knocked out in the lobby? You reappear on the plaza.
	  * No guns in the lobby. Walk through the portal to the hallway and
	    stand on a queue pad (QueueService) to join a match.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MatchState = require(ReplicatedStorage.Shared.Match.MatchState)
local GameContract = require(ReplicatedStorage.Shared.Net.GameContract)
local LobbyBuilder = require(script.Parent.Parent.Map.LobbyBuilder)

local PATTR = MatchState.PlayerAttr
local RESPAWN_DELAY = 1.5
local SPAWN_SPREAD = 4

local LobbyService = {}

local lobby: LobbyBuilder.Lobby? = nil
local random = Random.new()
local started = false

-- The queue pads in the hallway (empty until the lobby is built).
function LobbyService.getPads(): { LobbyBuilder.Pad }
	local current = lobby
	return if current then current.pads else {}
end

-- The glowing pad that takes players to the practice range (nil if missing).
function LobbyService.getRangePad(): BasePart?
	local current = lobby
	return if current then current.rangePad else nil
end

-- The big FREE FOR ALL pad at the end of the hallway (nil if missing).
function LobbyService.getFfaPad(): LobbyBuilder.Pad?
	local current = lobby
	return if current then current.ffaPad else nil
end

function LobbyService.isInLobby(player: Player): boolean
	local status = player:GetAttribute(PATTR.Status)
	return status == "Lobby" or status == "Queued"
end

function LobbyService.useLobbyCamera(player: Player)
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance = 14
	player.CameraMinZoomDistance = 8
end

function LobbyService.useMatchCamera(player: Player)
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
	player.CameraMode = Enum.CameraMode.LockFirstPerson
end

--[[
	If the place uses instance streaming (Workspace.StreamingEnabled), a
	player's device only loads parts near them. Before moving someone far
	away, ask Roblox to load the floor there first, so they can't fall
	through it. Waits at most 5 seconds; does nothing without streaming.
]]
function LobbyService.streamAround(player: Player, position: Vector3)
	if not Workspace.StreamingEnabled then
		return
	end
	local ok, err = pcall(function()
		player:RequestStreamAroundAsync(position, 5)
	end)
	if not ok then
		warn(`[LobbyService] Couldn't pre-load the area for {player.Name}: {err}`)
	end
end

-- Puts the player on the lobby plaza with a fresh character. Yields.
function LobbyService.spawn(player: Player)
	local current = lobby
	if player.Parent ~= Players or current == nil then
		return
	end
	if player:GetAttribute(PATTR.Status) ~= "Queued" then
		player:SetAttribute(PATTR.Status, "Lobby")
	end
	LobbyService.useLobbyCamera(player)
	local nudge = Vector3.new(random:NextNumber(-SPAWN_SPREAD, SPAWN_SPREAD), 0, random:NextNumber(-SPAWN_SPREAD, SPAWN_SPREAD))
	local target = current.spawnCFrame + nudge
	LobbyService.streamAround(player, target.Position)
	if player.Parent ~= Players then
		return
	end
	player:LoadCharacter()
	local character = player.Character
	if character and player.Parent == Players then
		character:PivotTo(target)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local found = character:WaitForChild("Humanoid", 10)
	if not found or not found:IsA("Humanoid") then
		return
	end
	local humanoid = found :: Humanoid
	humanoid.Died:Once(function()
		task.delay(RESPAWN_DELAY, function()
			if player.Parent == Players and LobbyService.isInLobby(player) and player.Character == character then
				LobbyService.spawn(player)
			end
		end)
	end)
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(PATTR.Status, "Menu")
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	local function onPlayPressed()
		if player:GetAttribute(GameContract.PlayerAttributes.PressedPlay) == true
			and player:GetAttribute(PATTR.Status) == "Menu"
		then
			LobbyService.spawn(player)
		end
	end
	player:GetAttributeChangedSignal(GameContract.PlayerAttributes.PressedPlay):Connect(onPlayPressed)
	onPlayPressed()
end

-- If the bunker can't be built, a plain floor still lets players in
-- (the error is printed in the Output window).
local function fallbackLobby(): LobbyBuilder.Lobby
	local model = Instance.new("Model")
	model.Name = "Lobby"
	local floor = Instance.new("Part")
	floor.Name = "FallbackFloor"
	floor.Anchored = true
	floor.Size = Vector3.new(80, 2, 80)
	floor.CFrame = CFrame.new(0, 299, 700)
	floor.Color = Color3.fromRGB(70, 74, 82)
	floor.Material = Enum.Material.DiamondPlate
	floor.Parent = model
	model.Parent = Workspace
	return { model = model, spawnCFrame = CFrame.new(0, 304, 700), origin = Vector3.new(0, 300, 700), pads = {}, problems = {}, rangePad = nil }
end

function LobbyService.start()
	if started then
		return
	end
	started = true
	-- Listen for players first, so the Play button works even if building fails.
	Players.PlayerAdded:Connect(onPlayerAdded)
	local ok, result = pcall(LobbyBuilder.build)
	local problemText = ""
	if ok then
		lobby = result
		problemText = table.concat((result :: LobbyBuilder.Lobby).problems, "  |  ")
	else
		warn(`[LobbyService] Building the lobby failed, using a plain floor instead: {result}`)
		lobby = fallbackLobby()
		problemText = `the whole lobby failed: {result}`
	end
	-- Shown at the top of players' screens (client start-up report).
	ReplicatedStorage:SetAttribute("LobbyProblems", string.sub(problemText, 1, 400))
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return LobbyService

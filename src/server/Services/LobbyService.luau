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
	player:LoadCharacter()
	local character = player.Character
	if character and player.Parent == Players then
		local nudge = Vector3.new(random:NextNumber(-SPAWN_SPREAD, SPAWN_SPREAD), 0, random:NextNumber(-SPAWN_SPREAD, SPAWN_SPREAD))
		character:PivotTo(current.spawnCFrame + nudge)
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

function LobbyService.start()
	if started then
		return
	end
	started = true
	lobby = LobbyBuilder.build()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return LobbyService

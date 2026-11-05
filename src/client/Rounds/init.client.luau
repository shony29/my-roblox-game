--!strict
-- Rounds HUD: the round caption under the timer, the big "GO!" / winner
-- banner, and a spawn-protection notice.
--
-- The timer itself, the kill feed and the scoreboard are part of the main
-- HUD (UI/Hud.luau, UI/KillFeed.luau, UI/Scoreboard.luau), so they are not
-- repeated here.
--
-- This script only *reads* what the server shares. It never sends anything
-- to the server, so there is nothing here a cheater could abuse.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SharedRounds = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rounds")
local RoundConfig = require(SharedRounds:WaitForChild("RoundConfig"))
local RoundState = require(SharedRounds:WaitForChild("RoundState"))

local localPlayer = Players.LocalPlayer
local stateFolder = ReplicatedStorage:WaitForChild(RoundState.FOLDER_NAME)

local FONT = Enum.Font.FredokaOne
local ACCENT = Color3.fromRGB(255, 205, 105)
local SOFT = Color3.fromRGB(235, 238, 250)

---------------------------------------------------------------------------
-- Build the HUD
---------------------------------------------------------------------------

local function label(parent: Instance, name: string, text: string, size: UDim2, position: UDim2): TextLabel
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = name
	textLabel.Text = text
	textLabel.Size = size
	textLabel.Position = position
	textLabel.AnchorPoint = Vector2.new(0.5, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = FONT
	textLabel.TextColor3 = SOFT
	textLabel.TextStrokeTransparency = 0.4
	textLabel.TextScaled = true
	textLabel.Parent = parent
	return textLabel
end

local gui = Instance.new("ScreenGui")
gui.Name = "RoundsHud"
gui.ResetOnSpawn = false -- keep the HUD when the player respawns
gui.IgnoreGuiInset = true -- same placement rules as the main HUD
gui.Parent = localPlayer:WaitForChild("PlayerGui")

-- Just under the main HUD's round timer (top centre).
local caption = label(gui, "RoundCaption", "", UDim2.fromOffset(320, 24), UDim2.new(0.5, 0, 0, 72))
caption.TextColor3 = ACCENT

-- Middle: big banner for "GO!" and the winner.
local banner = label(gui, "Banner", "", UDim2.new(0.8, 0, 0, 70), UDim2.fromScale(0.5, 0.25))
banner.TextColor3 = Color3.new(1, 1, 1)
banner.TextTransparency = 1
banner.TextStrokeTransparency = 1

-- Below the crosshair: spawn protection notice.
local protectedLabel = label(gui, "Protected", "Spawn protected", UDim2.fromOffset(220, 26), UDim2.fromScale(0.5, 0.6))
protectedLabel.TextColor3 = ACCENT
protectedLabel.Visible = false

---------------------------------------------------------------------------
-- Updating the HUD
---------------------------------------------------------------------------

local function getPhase(): RoundState.Phase
	local value = stateFolder:GetAttribute(RoundState.ATTR_PHASE)
	-- Return the exact words (not `value`), so --!strict knows it is a Phase.
	if value == "Playing" then
		return "Playing"
	elseif value == "Intermission" then
		return "Intermission"
	end
	return "Waiting"
end

local function getNumber(attribute: string): number
	local value = stateFolder:GetAttribute(attribute)
	return if typeof(value) == "number" then value else 0
end

local function updateCaption()
	local phase = getPhase()
	if phase == "Playing" then
		caption.Text = `Round {getNumber(RoundState.ATTR_ROUND_NUMBER)} · first to {RoundConfig.ELIMINATIONS_TO_WIN} wins`
	elseif phase == "Intermission" then
		caption.Text = "Next round starting..."
	else
		caption.Text = `Waiting for {RoundConfig.MIN_PLAYERS} player(s) to press Play`
	end
end

local function updateProtection()
	local character = localPlayer.Character
	protectedLabel.Visible = character ~= nil and character:GetAttribute(RoundState.PROTECTED_ATTR) == true
end

local function showBanner(text: string, holdSeconds: number)
	banner.Text = text
	banner.TextTransparency = 0
	banner.TextStrokeTransparency = 0.4
	local fade = TweenService:Create(
		banner,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, holdSeconds),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	fade:Play()
end

local function onPhaseChanged()
	updateCaption()
	local phase = getPhase()
	if phase == "Playing" then
		showBanner("GO!", 1)
	elseif phase == "Intermission" then
		local winnerText = stateFolder:GetAttribute(RoundState.ATTR_WINNER_TEXT)
		if typeof(winnerText) == "string" and winnerText ~= "" then
			showBanner(winnerText, math.max(RoundConfig.INTERMISSION_LENGTH - 2, 1))
		end
	end
end

stateFolder:GetAttributeChangedSignal(RoundState.ATTR_PHASE):Connect(onPhaseChanged)
stateFolder:GetAttributeChangedSignal(RoundState.ATTR_ROUND_NUMBER):Connect(updateCaption)
updateCaption()

-- The spawn-protection attribute lives on the character, which changes on
-- every respawn, so a cheap check a few times a second is simplest.
while true do
	updateProtection()
	task.wait(0.1)
end

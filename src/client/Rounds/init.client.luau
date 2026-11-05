--!strict
-- Rounds HUD: shows the round timer, the leaderboard, the winner banner,
-- a kill feed and a spawn-protection notice.
--
-- This script only *reads* what the server shares. It never sends anything
-- to the server, so there is nothing here a cheater could abuse.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local RoundConfig = require(ReplicatedStorage.Shared.Rounds.RoundConfig)
local RoundState = require(ReplicatedStorage.Shared.Rounds.RoundState)

local localPlayer = Players.LocalPlayer
local stateFolder = ReplicatedStorage:WaitForChild(RoundState.FOLDER_NAME) :: Folder
local eliminatedEvent = stateFolder:WaitForChild(RoundState.ELIMINATED_EVENT) :: RemoteEvent

local FONT = Enum.Font.FredokaOne
local LEADERBOARD_ROWS = 5
local KILL_FEED_LINES = 4

local Theme = {
	panel = Color3.fromRGB(30, 34, 52),
	text = Color3.fromRGB(255, 255, 255),
	soft = Color3.fromRGB(200, 205, 225),
	accent = Color3.fromRGB(255, 205, 105),
	you = Color3.fromRGB(120, 230, 160),
}

---------------------------------------------------------------------------
-- Small UI helpers
---------------------------------------------------------------------------

local function rounded(object: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = object
end

local function panel(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor
	frame.BackgroundColor3 = Theme.panel
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	rounded(frame, 12)
	frame.Parent = parent
	return frame
end

local function label(parent: Instance, name: string, text: string, size: UDim2, position: UDim2): TextLabel
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = name
	textLabel.Text = text
	textLabel.Size = size
	textLabel.Position = position
	textLabel.BackgroundTransparency = 1
	textLabel.Font = FONT
	textLabel.TextColor3 = Theme.text
	textLabel.TextScaled = true
	textLabel.Parent = parent
	return textLabel
end

---------------------------------------------------------------------------
-- Build the HUD
---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "RoundsHud"
gui.ResetOnSpawn = false -- keep the HUD when the player respawns
gui.Parent = localPlayer:WaitForChild("PlayerGui")

-- Top middle: phase + timer + goal.
local topBar = panel(gui, "TopBar", UDim2.fromOffset(220, 84), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
local phaseLabel = label(topBar, "Phase", "", UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 6))
phaseLabel.TextColor3 = Theme.accent
local timerLabel = label(topBar, "Timer", "", UDim2.new(1, -16, 0, 36), UDim2.fromOffset(8, 26))
local goalLabel = label(topBar, "Goal", "", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(8, 62))
goalLabel.TextColor3 = Theme.soft

-- Top right: leaderboard.
local boardHeight = 34 + LEADERBOARD_ROWS * 24 + 30
local board = panel(gui, "Leaderboard", UDim2.fromOffset(210, boardHeight), UDim2.new(1, -8, 0, 8), Vector2.new(1, 0))
label(board, "Title", "Leaderboard", UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 6)).TextColor3 = Theme.accent

local rowLabels: { TextLabel } = {}
for i = 1, LEADERBOARD_ROWS do
	local row = label(board, "Row" .. i, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 34 + (i - 1) * 24))
	row.TextXAlignment = Enum.TextXAlignment.Left
	table.insert(rowLabels, row)
end
local yourScoreLabel = label(board, "You", "", UDim2.new(1, -20, 0, 20), UDim2.new(0, 10, 1, -26))
yourScoreLabel.TextColor3 = Theme.you
yourScoreLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Top left: kill feed.
local feed = Instance.new("Frame")
feed.Name = "KillFeed"
feed.BackgroundTransparency = 1
feed.Size = UDim2.fromOffset(300, KILL_FEED_LINES * 26)
feed.Position = UDim2.fromOffset(8, 8)
feed.Parent = gui
local feedLayout = Instance.new("UIListLayout")
feedLayout.Padding = UDim.new(0, 4)
feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
feedLayout.Parent = feed

-- Middle: big banner for "GO!" and the winner.
local banner = label(gui, "Banner", "", UDim2.new(0.8, 0, 0, 70), UDim2.fromScale(0.5, 0.3))
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.TextTransparency = 1
banner.TextStrokeTransparency = 1

-- Bottom middle: spawn protection notice.
local protectedLabel = label(gui, "Protected", "Spawn protected", UDim2.fromOffset(220, 28), UDim2.new(0.5, 0, 1, -110))
protectedLabel.AnchorPoint = Vector2.new(0.5, 0)
protectedLabel.TextColor3 = Theme.accent
protectedLabel.Visible = false

---------------------------------------------------------------------------
-- Updating the HUD
---------------------------------------------------------------------------

local function getPhase(): RoundState.Phase
	local value = stateFolder:GetAttribute(RoundState.ATTR_PHASE)
	if value == "Playing" or value == "Intermission" then
		return value
	end
	return "Waiting"
end

local function getNumber(attribute: string): number
	local value = stateFolder:GetAttribute(attribute)
	return if typeof(value) == "number" then value else 0
end

local function formatTime(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function getScore(player: Player): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild(RoundState.SCORE_STAT)
	return if stat and stat:IsA("IntValue") then stat.Value else 0
end

local function updateTopBar()
	local phase = getPhase()
	local remaining = getNumber(RoundState.ATTR_ENDS_AT) - Workspace:GetServerTimeNow()
	if phase == "Playing" then
		phaseLabel.Text = `Round {getNumber(RoundState.ATTR_ROUND_NUMBER)}`
		timerLabel.Text = formatTime(remaining)
		goalLabel.Text = `First to {RoundConfig.ELIMINATIONS_TO_WIN} wins`
	elseif phase == "Intermission" then
		phaseLabel.Text = "Next round in"
		timerLabel.Text = formatTime(remaining)
		goalLabel.Text = "Take a breather!"
	else
		phaseLabel.Text = "Waiting"
		timerLabel.Text = "..."
		goalLabel.Text = `Need {RoundConfig.MIN_PLAYERS} players`
	end
end

local function updateLeaderboard()
	local players = Players:GetPlayers()
	local scoreOf: { [Player]: number } = {}
	for _, player in players do
		scoreOf[player] = getScore(player)
	end
	table.sort(players, function(a: Player, b: Player): boolean
		if scoreOf[a] ~= scoreOf[b] then
			return scoreOf[a] > scoreOf[b]
		end
		return a.Name < b.Name
	end)

	local yourPlace = 0
	for place, player in players do
		if player == localPlayer then
			yourPlace = place
		end
	end

	for i, row in rowLabels do
		local player = players[i]
		if player then
			row.Text = `{i}. {player.DisplayName}   {scoreOf[player]}`
			row.TextColor3 = if player == localPlayer then Theme.you else Theme.text
		else
			row.Text = ""
		end
	end
	yourScoreLabel.Text = `You: {getScore(localPlayer)}  (#{yourPlace})`
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
	local phase = getPhase()
	if phase == "Playing" then
		showBanner("GO!", 1)
	elseif phase == "Intermission" then
		local winnerText = stateFolder:GetAttribute(RoundState.ATTR_WINNER_TEXT)
		if typeof(winnerText) == "string" and winnerText ~= "" then
			showBanner(winnerText, RoundConfig.INTERMISSION_LENGTH - 2)
		end
	end
end

local feedCounter = 0
local function addFeedLine(killerName: string?, victimName: string)
	feedCounter += 1
	local text = if killerName then `{killerName} eliminated {victimName}` else `{victimName} was eliminated`
	local involvesMe = killerName == localPlayer.Name or victimName == localPlayer.Name

	local line = label(feed, "Line", text, UDim2.new(1, 0, 0, 22), UDim2.new())
	line.LayoutOrder = -feedCounter -- newest on top
	line.TextScaled = false
	line.TextSize = 18
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextColor3 = if involvesMe then Theme.you else Theme.text
	line.TextStrokeTransparency = 0.5

	-- Keep only the newest few lines.
	local lines: { TextLabel } = {}
	for _, child in feed:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(lines, child)
		end
	end
	table.sort(lines, function(a: TextLabel, b: TextLabel): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = KILL_FEED_LINES + 1, #lines do
		lines[i]:Destroy()
	end

	task.delay(4, function()
		if line.Parent then
			local fade = TweenService:Create(line, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 })
			fade.Completed:Once(function()
				line:Destroy()
			end)
			fade:Play()
		end
	end)
end

eliminatedEvent.OnClientEvent:Connect(function(killerName: unknown, victimName: unknown)
	if typeof(victimName) ~= "string" then
		return
	end
	addFeedLine(if typeof(killerName) == "string" then killerName else nil, victimName)
end)

stateFolder:GetAttributeChangedSignal(RoundState.ATTR_PHASE):Connect(onPhaseChanged)

-- Refresh the numbers ten times a second; cheap, and keeps the timer smooth.
while true do
	updateTopBar()
	updateLeaderboard()
	updateProtection()
	task.wait(0.1)
end

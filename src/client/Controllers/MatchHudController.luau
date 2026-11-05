--!strict
--[[
	MatchHudController: shows the match state that the server shares.

	  * Score panel (top centre, under the round timer): BLUE 2 – 1 PINK,
	    with your team marked, and the round number.
	  * Status line: "Waiting for an opponent..." while queued.
	  * Big centre text: MATCH FOUND, the 3-2-1 countdown, GO!, who won the
	    round, and VICTORY / DEFEAT / DRAW at the end.
	  * "Spawn protected" while your protection bubble is on.

	It only READS attributes (ReplicatedStorage.MatchState and your Player);
	it never sends anything to the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local MatchState = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Match"):WaitForChild("MatchState"))

type State = MatchState.State
type TeamId = MatchState.TeamId

local ATTR = MatchState.Attr
local PATTR = MatchState.PlayerAttr
local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 205, 105)
local UPDATE_INTERVAL = 0.1

local MatchHudController = {}
local started = false

local function label(parent: Instance, name: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Size = size
	text.Position = position
	text.BackgroundTransparency = 1
	text.Font = FONT
	text.TextSize = textSize
	text.TextColor3 = WHITE
	text.TextStrokeTransparency = 0.35
	text.RichText = true
	text.Text = ""
	text.Parent = parent
	return text
end

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

function MatchHudController.start()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	local stateFolder = ReplicatedStorage:WaitForChild(MatchState.FOLDER_NAME)

	local gui = Instance.new("ScreenGui")
	gui.Name = "MatchHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2
	gui.Parent = player:WaitForChild("PlayerGui")

	local scoreLine = label(gui, "Score", UDim2.fromOffset(420, 30), UDim2.new(0.5, 0, 0, 70), 26)
	local roundLine = label(gui, "Round", UDim2.fromOffset(420, 20), UDim2.new(0.5, 0, 0, 100), 17)
	roundLine.TextColor3 = GOLD
	local status = label(gui, "Status", UDim2.fromOffset(600, 30), UDim2.new(0.5, 0, 0, 130), 22)
	local big = label(gui, "Big", UDim2.fromOffset(900, 90), UDim2.fromScale(0.5, 0.26), 72)
	local subtitle = label(gui, "Subtitle", UDim2.fromOffset(900, 34), UDim2.new(0.5, 0, 0.26, 92), 26)
	local protectedLabel = label(gui, "Protected", UDim2.fromOffset(240, 26), UDim2.fromScale(0.5, 0.6), 20)
	protectedLabel.Text = "Spawn protected"
	protectedLabel.TextColor3 = GOLD

	local function myTeam(): TeamId?
		return MatchState.toTeam(player:GetAttribute(PATTR.Team))
	end

	local function getNumber(attribute: string): number
		local value = stateFolder:GetAttribute(attribute)
		return if typeof(value) == "number" then value else 0
	end

	-- A short pop-in for the big centre text.
	local function pop(text: string, color: Color3, sub: string?)
		big.Text = text
		big.TextColor3 = color
		subtitle.Text = sub or ""
		big.TextTransparency = 0
		big.TextSize = 92
		TweenService:Create(big, TweenInfo.new(0.25, Enum.EasingStyle.Back), { TextSize = 72 }):Play()
	end

	local function clearBig()
		big.Text = ""
		subtitle.Text = ""
	end

	local lastState: State = "Lobby"
	local lastCountdown = -1

	local function onStateChanged()
		local state = MatchState.toState(stateFolder:GetAttribute(ATTR.State))
		local team = myTeam()
		lastState = state
		lastCountdown = -1
		if team == nil then
			clearBig()
			return
		end
		local teamInfo = MatchState.teamInfo(team)
		if state == "MatchFound" then
			pop("MATCH FOUND!", GOLD, `You're on the <font color="{hex(teamInfo.Color)}">{teamInfo.Name}</font> team`)
		elseif state == "InMatch" then
			pop("GO!", WHITE)
			task.delay(0.8, function()
				if lastState == "InMatch" then
					clearBig()
				end
			end)
		elseif state == "RoundEnd" then
			local winner = MatchState.toTeam(stateFolder:GetAttribute(ATTR.RoundWinner))
			if winner == nil then
				pop("DRAW", WHITE, "Nobody wins this round")
			elseif winner == team then
				pop("ROUND WON!", MatchState.teamInfo(winner).Color)
			else
				pop("ROUND LOST", MatchState.teamInfo(winner).Color)
			end
		elseif state == "MatchResults" then
			local winner = MatchState.toTeam(stateFolder:GetAttribute(ATTR.MatchWinner))
			local final = `{getNumber(ATTR.ScoreA)} – {getNumber(ATTR.ScoreB)}`
			if winner == nil then
				pop("DRAW", WHITE, final)
			elseif winner == team then
				pop("VICTORY!", GOLD, final)
			else
				pop("DEFEAT", MatchState.teamInfo(winner).Color, final)
			end
		elseif state ~= "Countdown" then
			clearBig()
		end
	end

	local function update()
		local team = myTeam()
		local inMatch = team ~= nil
		local state = lastState

		-- Score panel (only while you're in a match).
		if inMatch then
			local blue, pink = MatchState.teamInfo("A"), MatchState.teamInfo("B")
			local you = if team == "A" then " (you)" else ""
			local youB = if team == "B" then " (you)" else ""
			scoreLine.Text = `<font color="{hex(blue.Color)}">{string.upper(blue.Name)}{you}</font>  {getNumber(ATTR.ScoreA)} – {getNumber(ATTR.ScoreB)}  <font color="{hex(pink.Color)}">{string.upper(pink.Name)}{youB}</font>`
			roundLine.Text = `Round {getNumber(ATTR.Round)} · first to {getNumber(ATTR.RoundsToWin)}`
		else
			scoreLine.Text = ""
			roundLine.Text = ""
		end

		-- Status line.
		local playerStatus = player:GetAttribute(PATTR.Status)
		status.Text = if playerStatus == "Queued" then "Waiting for an opponent..." else ""

		-- Countdown numbers, from the server's end time.
		if inMatch and state == "Countdown" then
			local secondsLeft = math.ceil(getNumber(ATTR.PhaseEndsAt) - Workspace:GetServerTimeNow())
			if secondsLeft ~= lastCountdown and secondsLeft > 0 then
				lastCountdown = secondsLeft
				pop(tostring(secondsLeft), WHITE, "Get ready!")
			end
		end

		local character = player.Character
		protectedLabel.Visible = inMatch
			and character ~= nil
			and character:GetAttribute(MatchState.PROTECTED_ATTR) == true
	end

	stateFolder:GetAttributeChangedSignal(ATTR.State):Connect(onStateChanged)
	player:GetAttributeChangedSignal(PATTR.Team):Connect(onStateChanged)
	onStateChanged()

	task.spawn(function()
		while gui.Parent do
			update()
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

return MatchHudController

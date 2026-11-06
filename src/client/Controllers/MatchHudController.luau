--!strict
--[[
	MatchHudController: shows the match state that the server shares.

	  * Team bar (top, either side of the round timer): your team's avatars
	    on the left, the other team's on the right, each with its score.
	    Eliminated players fade out and turn grey. Bots show as "BOT".
	    Under the timer: the round number.
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

	local scoreLine = label(gui, "Score", UDim2.fromOffset(420, 30), UDim2.new(0.5, 0, 0, 92), 22)
	local roundLine = label(gui, "Round", UDim2.fromOffset(420, 20), UDim2.new(0.5, 0, 0, 70), 13)
	roundLine.Font = Enum.Font.Michroma
	roundLine.TextColor3 = Color3.fromRGB(190, 200, 225)

	-- Team bar: a box of avatar pictures on each side of the timer --------
	local SCI_PANEL = Color3.fromRGB(16, 20, 32)
	local AVATAR = 44
	local function teamBox(name: string, anchorX: number, offsetX: number, color: Color3): (Frame, TextLabel)
		local box = Instance.new("Frame")
		box.Name = name
		box.AnchorPoint = Vector2.new(anchorX, 0)
		box.Position = UDim2.new(0.5, offsetX, 0, 14)
		box.Size = UDim2.fromOffset(AVATAR + 16, 52)
		box.AutomaticSize = Enum.AutomaticSize.X
		box.BackgroundColor3 = SCI_PANEL
		box.BackgroundTransparency = 0.1
		box.Visible = false
		box.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = box
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = box
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingRight = UDim.new(0, 8)
		padding.Parent = box
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = if anchorX > 0.5 then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 6)
		layout.Parent = box
		-- The team's score, in big numbers on the outer side of the box.
		local score = Instance.new("TextLabel")
		score.Name = "TeamScore"
		score.LayoutOrder = if anchorX > 0.5 then 0 else 999
		score.Size = UDim2.fromOffset(34, 44)
		score.BackgroundTransparency = 1
		score.Font = Enum.Font.Michroma
		score.TextSize = 28
		score.TextColor3 = WHITE
		score.TextStrokeTransparency = 0.5
		score.Text = "0"
		score.Parent = box
		return box, score
	end
	local myBox, myScore = teamBox("MyTeam", 1, -76, Color3.fromRGB(90, 200, 255))
	local theirBox, theirScore = teamBox("TheirTeam", 0, 76, Color3.fromRGB(255, 90, 110))
	-- Your team's score sits on the far left of its box, theirs on the far right.
	myScore.LayoutOrder = -1
	theirScore.LayoutOrder = 999

	type Member = { key: string, userId: number?, name: string, character: Model? }
	local shown: { [Frame]: string } = {}
	local function avatarImage(parent: Frame, member: Member, order: number): ImageLabel
		local picture = Instance.new("ImageLabel")
		picture.Name = "Avatar"
		picture.LayoutOrder = order
		picture.Size = UDim2.fromOffset(AVATAR, AVATAR)
		picture.BackgroundColor3 = Color3.fromRGB(40, 46, 66)
		picture.BackgroundTransparency = 0
		picture.Image = if member.userId then `rbxthumb://type=AvatarHeadShot&id={member.userId}&w=150&h=150` else ""
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = picture
		if not member.userId then
			local bot = Instance.new("TextLabel")
			bot.BackgroundTransparency = 1
			bot.Size = UDim2.fromScale(1, 1)
			bot.Font = Enum.Font.Michroma
			bot.TextSize = 12
			bot.TextColor3 = Color3.fromRGB(200, 210, 235)
			bot.Text = "BOT"
			bot.Parent = picture
		end
		picture.Parent = parent
		return picture
	end
	-- Everyone on `team` (players and bots), in a steady order.
	local function membersOf(team: TeamId): { Member }
		local list: { Member } = {}
		for _, other in Players:GetPlayers() do
			if MatchState.toTeam(other:GetAttribute(PATTR.Team)) == team and other:GetAttribute("FreeForAll") ~= true then
				table.insert(list, { key = tostring(other.UserId), userId = other.UserId, name = other.DisplayName, character = other.Character })
			end
		end
		for _, model in workspace:GetChildren() do
			if model:IsA("Model") and MatchState.toTeam(model:GetAttribute("BotTeam")) == team then
				table.insert(list, { key = model.Name, userId = nil, name = model.Name, character = model })
			end
		end
		table.sort(list, function(a: Member, b: Member): boolean
			return a.key < b.key
		end)
		return list
	end
	local function isAlive(member: Member): boolean
		local character = member.character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return humanoid ~= nil and humanoid.Health > 0
	end
	local function refreshBox(box: Frame, members: { Member })
		-- Rebuild the pictures only when the team changes.
		local keys = {}
		for _, member in members do
			table.insert(keys, member.key)
		end
		local signature = table.concat(keys, ",")
		if shown[box] ~= signature then
			shown[box] = signature
			for _, child in box:GetChildren() do
				if child:IsA("ImageLabel") then
					child:Destroy()
				end
			end
			for index, member in members do
				local picture = avatarImage(box, member, index)
				picture:SetAttribute("MemberKey", member.key)
			end
		end
		-- Eliminated players fade out and turn grey.
		local byKey: { [string]: Member } = {}
		for _, member in members do
			byKey[member.key] = member
		end
		for _, child in box:GetChildren() do
			if child:IsA("ImageLabel") then
				local member = byKey[child:GetAttribute("MemberKey") :: string]
				local alive = member ~= nil and isAlive(member)
				child.ImageTransparency = if alive then 0 else 0.6
				child.ImageColor3 = if alive then WHITE else Color3.fromRGB(120, 120, 130)
				child.BackgroundTransparency = if alive then 0 else 0.6
			end
		end
	end
	local status = label(gui, "Status", UDim2.fromOffset(600, 30), UDim2.new(0.5, 0, 0, 130), 22)
	local big = label(gui, "Big", UDim2.fromOffset(900, 90), UDim2.fromScale(0.5, 0.26), 72)
	local subtitle = label(gui, "Subtitle", UDim2.fromOffset(900, 34), UDim2.new(0.5, 0, 0.26, 92), 26)
	local protectedLabel = label(gui, "Protected", UDim2.fromOffset(240, 26), UDim2.fromScale(0.5, 0.6), 20)
	protectedLabel.Text = "Spawn protected"
	protectedLabel.TextColor3 = GOLD

	local function myTeam(): TeamId?
		return MatchState.toTeam(player:GetAttribute(PATTR.Team))
	end

	-- Free for all: everyone for themselves (see ModeConfig.FreeForAll).
	local function isFreeForAll(): boolean
		return stateFolder:GetAttribute(ATTR.Mode) == "FreeForAll"
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
		if state == "MatchFound" and isFreeForAll() then
			pop("MATCH FOUND!", GOLD, "Free for all: everyone for themselves!")
		elseif state == "RoundEnd" and isFreeForAll() then
			local leader = stateFolder:GetAttribute(ATTR.LeaderName)
			pop("MATCH OVER!", GOLD, if typeof(leader) == "string" and leader ~= "" then `{leader} wins!` else "Nobody scored")
		elseif state == "MatchFound" then
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
			clearBig() -- the results screen (ResultsController) shows the outcome
		elseif state ~= "Countdown" then
			clearBig()
		end
	end

	local function update()
		local team = myTeam()
		local inMatch = team ~= nil
		local state = lastState

		-- Score panel (only while you're in a match).
		if inMatch and isFreeForAll() then
			local mine = player:GetAttribute(PATTR.Eliminations)
			local leader = stateFolder:GetAttribute(ATTR.LeaderName)
			local leaderText = if typeof(leader) == "string" and leader ~= ""
				then `  ·  LEADER <font color="{hex(GOLD)}">{leader} {getNumber(ATTR.LeaderScore)}</font>`
				else ""
			scoreLine.Text = `FREE FOR ALL  ·  YOU {if typeof(mine) == "number" then mine else 0}{leaderText}`
			roundLine.Text = `First to {getNumber(ATTR.EliminationsToWin)} eliminations`
		elseif inMatch and team then
			-- Avatars instead of team names: yours on the left, theirs on the right.
			local enemy: TeamId = if team == "A" then "B" else "A"
			scoreLine.Text = ""
			roundLine.Text = `ROUND {getNumber(ATTR.Round)} · FIRST TO {getNumber(ATTR.RoundsToWin)}`
			myScore.Text = tostring(getNumber(if team == "A" then ATTR.ScoreA else ATTR.ScoreB))
			theirScore.Text = tostring(getNumber(if team == "A" then ATTR.ScoreB else ATTR.ScoreA))
			refreshBox(myBox, membersOf(team))
			refreshBox(theirBox, membersOf(enemy))
		else
			scoreLine.Text = ""
			roundLine.Text = ""
		end
		local showBars = inMatch and team ~= nil and not isFreeForAll()
		myBox.Visible = showBars
		theirBox.Visible = showBars

		-- Status line (queue status is shown on the lobby's Play panel instead).
		status.Text = ""

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

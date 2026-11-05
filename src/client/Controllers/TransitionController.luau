--!strict
--[[
	TransitionController: the screens between "match found" and the fight.

	  * Map voting (MapVoting state): map cards slide in, click one to vote
	    (you can change your mind), live vote counts, a countdown. Your pick
	    grows slightly. The server counts the votes and picks the winner.
	  * Loading (Loading state): a calm loading screen naming the map while
	    the server builds it. No fake progress bar: it simply waits for the
	    server to say the map is ready (the Countdown state).

	Only shown to players in the match. Everything shown comes from
	attributes the server sets on ReplicatedStorage.MatchState.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapConfig = require(Shared:WaitForChild("Config"):WaitForChild("MapConfig"))
local MatchState = require(Shared:WaitForChild("Match"):WaitForChild("MatchState"))
local Net = require(Shared:WaitForChild("Net"):WaitForChild("Net"))
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIHelpers = require(UIFolder:WaitForChild("UIHelpers"))
local ResponsiveScale = require(UIFolder:WaitForChild("ResponsiveScale"))

local Colors = Theme.Colors
local ATTR = MatchState.Attr
local CARD_SIZE = Vector2.new(230, 170)

local TransitionController = {}
local started = false

function TransitionController.start()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	local stateFolder = ReplicatedStorage:WaitForChild(MatchState.FOLDER_NAME)
	local mapVote = Net.event("MapVote")

	local gui = UIHelpers.screenGui("Transitions", 8, player:WaitForChild("PlayerGui"))
	ResponsiveScale.apply(gui)

	-- Voting -----------------------------------------------------------------
	local voting = Instance.new("Frame")
	voting.Name = "Voting"
	voting.BackgroundTransparency = 1
	voting.Size = UDim2.fromScale(1, 1)
	voting.Visible = false
	voting.Parent = gui

	local voteTitle = UIHelpers.label("Title", "VOTE FOR A MAP", 36, Theme.Fonts.Title)
	voteTitle.Size = UDim2.new(1, 0, 0, 50)
	voteTitle.Position = UDim2.fromScale(0, 0.2)
	voteTitle.TextColor3 = Colors.Yolk
	UIHelpers.textStroke(voteTitle, 3)
	voteTitle.Parent = voting

	local cardRow = Instance.new("Frame")
	cardRow.Name = "Cards"
	cardRow.BackgroundTransparency = 1
	cardRow.AnchorPoint = Vector2.new(0.5, 0.5)
	cardRow.Position = UDim2.fromScale(0.5, 0.5)
	cardRow.Size = UDim2.fromOffset(3 * (CARD_SIZE.X + 20), CARD_SIZE.Y + 20)
	cardRow.Parent = voting
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 20)
	rowLayout.Parent = cardRow

	local myVote: string? = nil
	local cards: { [string]: { button: TextButton, votes: TextLabel, scale: UIScale } } = {}
	local shownOptions = ""

	local function buildCards(optionsText: string)
		for _, card in cards do
			card.button:Destroy()
		end
		table.clear(cards)
		myVote = nil
		for index, mapId in string.split(optionsText, ",") do
			local info = MapConfig.get(mapId)
			if not info then
				continue
			end
			local button = Instance.new("TextButton")
			button.Name = mapId
			button.Text = ""
			button.AutoButtonColor = false
			button.LayoutOrder = index
			button.Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
			button.BackgroundColor3 = Colors.Panel
			button.Modal = true -- frees the mouse in first person while voting
			UIHelpers.corner(button, UDim.new(0, 16))
			UIHelpers.stroke(button, Colors.Ink, 3)
			button.Parent = cardRow

			local preview = UIHelpers.frame("Preview", UDim2.new(1, -16, 0, 70), UDim2.fromOffset(8, 8))
			preview.BackgroundColor3 = info.PreviewColor
			preview.BackgroundTransparency = 0
			UIHelpers.corner(preview, UDim.new(0, 10))
			preview.Parent = button

			local name = UIHelpers.label("Name", info.DisplayName, 22, Theme.Fonts.Title)
			name.Size = UDim2.new(1, -16, 0, 28)
			name.Position = UDim2.fromOffset(8, 82)
			name.Parent = button

			local votes = UIHelpers.label("Votes", "0 votes", 16)
			votes.Size = UDim2.new(1, -16, 0, 22)
			votes.Position = UDim2.fromOffset(8, 112)
			votes.TextColor3 = Colors.Yolk
			votes.Parent = button

			local scale = Instance.new("UIScale")
			scale.Scale = 0.8
			scale.Parent = button
			-- Staggered entrance: each card pops in a moment after the last.
			task.delay(0.06 * index, function()
				UIHelpers.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end)

			button.Activated:Connect(function()
				myVote = mapId
				mapVote:FireServer(mapId)
			end)
			cards[mapId] = { button = button, votes = votes, scale = scale }
		end
	end

	-- Loading -----------------------------------------------------------------
	local loading = UIHelpers.frame("Loading", UDim2.fromScale(1, 1), UDim2.new())
	loading.BackgroundColor3 = Colors.Ink
	loading.BackgroundTransparency = 0.1
	loading.Visible = false
	loading.Parent = gui
	local loadingText = UIHelpers.label("Text", "Loading...", 34, Theme.Fonts.Title)
	loadingText.Size = UDim2.new(1, 0, 0, 50)
	loadingText.Position = UDim2.fromScale(0, 0.45)
	loadingText.Parent = loading
	local spinner = UIHelpers.frame("Spinner", UDim2.fromOffset(36, 36), UDim2.fromScale(0.5, 0.58), Vector2.new(0.5, 0.5))
	spinner.BackgroundColor3 = Colors.Yolk
	spinner.BackgroundTransparency = 0
	UIHelpers.corner(spinner, UDim.new(0, 8))
	spinner.Parent = loading

	-- Updating ------------------------------------------------------------------
	local function refresh()
		local inMatch = MatchState.toTeam(player:GetAttribute(MatchState.PlayerAttr.Team)) ~= nil
		local state = MatchState.toState(stateFolder:GetAttribute(ATTR.State))

		local optionsText = stateFolder:GetAttribute(ATTR.VoteOptions)
		local isVoting = inMatch and state == "MapVoting" and typeof(optionsText) == "string" and optionsText ~= ""
		voting.Visible = isVoting
		if isVoting and optionsText ~= shownOptions then
			shownOptions = optionsText :: string
			buildCards(shownOptions)
		elseif not isVoting then
			shownOptions = ""
		end
		if isVoting then
			local secondsLeft = math.max(0, UIHelpers.numberAttribute(stateFolder, ATTR.PhaseEndsAt) - Workspace:GetServerTimeNow())
			voteTitle.Text = `VOTE FOR A MAP · {math.ceil(secondsLeft)}`
			for mapId, card in cards do
				local count = UIHelpers.numberAttribute(stateFolder, "Votes" .. mapId)
				card.votes.Text = if count == 1 then "1 vote" else `{count} votes`
				local mine = mapId == myVote
				card.button.BackgroundColor3 = if mine then Colors.SkyDeep else Colors.Panel
				card.scale.Scale = if mine then 1.06 else math.min(card.scale.Scale, 1)
			end
		end

		local isLoading = inMatch and state == "Loading"
		loading.Visible = isLoading
		if isLoading then
			local info = MapConfig.get(stateFolder:GetAttribute(ATTR.MapId))
			loadingText.Text = if info then `Loading {info.DisplayName}...` else "Loading..."
			spinner.Rotation = (spinner.Rotation + 12) % 360
		end
	end

	task.spawn(function()
		while gui.Parent do
			refresh()
			task.wait(1 / 30)
		end
	end)
end

return TransitionController

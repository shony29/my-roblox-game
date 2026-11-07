--!strict
--[[
	TransitionController: the screens between "match found" and the fight.

	  * Map voting (MapVoting state): every map as a card in a grid, each
	    with little 3D charms of its theme, its name and a short description.
	    Click one to vote (you can change your mind); live vote counts and a
	    countdown. Your pick glows green. The server counts the votes.
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
local CharmBuilder = require(Shared:WaitForChild("Cosmetics"):WaitForChild("CharmBuilder"))

local Colors = Theme.Colors
local Sci = Theme.SciFi
local SCI_FONT = Theme.SciFiFonts.Title
local BODY_FONT = Theme.SciFiFonts.Body
local ATTR = MatchState.Attr
local CARD_SIZE = Vector2.new(178, 196)
local COLUMNS = 5

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

	-- A dark backdrop so the cards stand out.
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Sci.Void
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Parent = voting

	local voteTitle = UIHelpers.label("Title", "VOTE FOR A MAP", 28, SCI_FONT)
	voteTitle.Size = UDim2.new(1, 0, 0, 44)
	voteTitle.AnchorPoint = Vector2.new(0, 1)
	voteTitle.Position = UDim2.new(0, 0, 0.5, -(CARD_SIZE.Y + 30))
	voteTitle.TextColor3 = Sci.Green
	voteTitle.Parent = voting

	local cardRow = Instance.new("Frame")
	cardRow.Name = "Cards"
	cardRow.BackgroundTransparency = 1
	cardRow.AnchorPoint = Vector2.new(0.5, 0.5)
	cardRow.Position = UDim2.fromScale(0.5, 0.5)
	cardRow.Size = UDim2.fromOffset(COLUMNS * (CARD_SIZE.X + 14), 2 * (CARD_SIZE.Y + 14))
	cardRow.Parent = voting
	local rowLayout = Instance.new("UIGridLayout")
	rowLayout.CellSize = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
	rowLayout.CellPadding = UDim2.fromOffset(14, 14)
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = cardRow

	local myVote: string? = nil
	local cards: { [string]: { button: TextButton, votes: TextLabel, scale: UIScale, edge: UIStroke, color: Color3 } } = {}
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
			button.BackgroundColor3 = Sci.Panel
			button.Modal = true -- frees the mouse in first person while voting
			UIHelpers.corner(button, UDim.new(0, 14))
			local edge = UIHelpers.stroke(button, info.PreviewColor, 2)
			button.Parent = cardRow

			-- The picture: the map's colour fading to dark, with its charms in 3D.
			local preview = UIHelpers.frame("Preview", UDim2.new(1, -14, 0, 92), UDim2.fromOffset(7, 7))
			preview.BackgroundColor3 = info.PreviewColor
			preview.BackgroundTransparency = 0
			UIHelpers.corner(preview, UDim.new(0, 10))
			preview.Parent = button
			local fade = Instance.new("UIGradient")
			fade.Rotation = 90
			fade.Color = ColorSequence.new(info.PreviewColor, info.PreviewColor:Lerp(Sci.Void, 0.65))
			fade.Parent = preview
			local viewport = Instance.new("ViewportFrame")
			viewport.Size = UDim2.fromScale(1, 1)
			viewport.BackgroundTransparency = 1
			viewport.Ambient = Color3.fromRGB(200, 200, 210)
			viewport.LightDirection = Vector3.new(-1, -2, 1)
			viewport.Parent = preview
			local camera = Instance.new("Camera")
			camera.FieldOfView = 30
			camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, -7), Vector3.zero)
			camera.Parent = viewport
			viewport.CurrentCamera = camera
			local emblems = info.Emblems
			for slot, charmName in emblems do
				local charm = CharmBuilder.build(charmName, { scale = if #emblems == 1 then 1.4 else 1.05 })
				local x = (slot - (#emblems + 1) / 2) * 1.25
				charm:PivotTo(CFrame.new(x, if slot % 2 == 0 then 0.15 else -0.1, 0) * CFrame.Angles(0, 0, math.rad((slot - 2) * -12)))
				charm.Parent = viewport
			end

			local name = UIHelpers.label("Name", string.upper(info.DisplayName), 13, SCI_FONT)
			name.Size = UDim2.new(1, -14, 0, 22)
			name.Position = UDim2.fromOffset(7, 104)
			name.TextColor3 = Sci.Text
			name.TextScaled = true
			local nameLimit = Instance.new("UITextSizeConstraint")
			nameLimit.MaxTextSize = 13
			nameLimit.Parent = name
			name.Parent = button

			local about = UIHelpers.label("About", info.Description, 11, BODY_FONT)
			about.Size = UDim2.new(1, -16, 0, 40)
			about.Position = UDim2.fromOffset(8, 126)
			about.TextWrapped = true
			about.TextColor3 = Sci.Dim
			about.Parent = button

			local votes = UIHelpers.label("Votes", "0 votes", 12, SCI_FONT)
			votes.Size = UDim2.new(1, -16, 0, 20)
			votes.Position = UDim2.fromOffset(8, 170)
			votes.TextColor3 = Sci.Yellow
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
			cards[mapId] = { button = button, votes = votes, scale = scale, edge = edge, color = info.PreviewColor }
		end
	end

	-- Loading -----------------------------------------------------------------
	-- (Sci-fi, like the loading screen you see when you join.)
	local loading = UIHelpers.frame("Loading", UDim2.fromScale(1, 1), UDim2.new())
	loading.BackgroundColor3 = Sci.Void
	loading.BackgroundTransparency = 0.04
	loading.Visible = false
	loading.Parent = gui
	local loadingGlow = Instance.new("UIGradient")
	loadingGlow.Rotation = 90
	loadingGlow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 30, 34)),
		ColorSequenceKeypoint.new(0.6, Sci.Void),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 14, 36)),
	})
	loadingGlow.Parent = loading
	local loadingText = UIHelpers.label("Text", "LOADING...", 26, SCI_FONT)
	loadingText.Size = UDim2.new(1, 0, 0, 44)
	loadingText.Position = UDim2.fromScale(0, 0.4)
	loadingText.TextColor3 = Sci.Green
	loadingText.Parent = loading
	local loadingAbout = UIHelpers.label("About", "", 16, BODY_FONT)
	loadingAbout.Size = UDim2.new(1, 0, 0, 26)
	loadingAbout.Position = UDim2.new(0, 0, 0.4, 48)
	loadingAbout.TextColor3 = Sci.Dim
	loadingAbout.Parent = loading
	-- A spinning neon ring (half of it fades out, so it reads as a turning arc).
	local spinner = UIHelpers.frame("Spinner", UDim2.fromOffset(46, 46), UDim2.fromScale(0.5, 0.6), Vector2.new(0.5, 0.5))
	spinner.BackgroundTransparency = 1
	UIHelpers.corner(spinner, UDim.new(1, 0))
	spinner.Parent = loading
	local ring = UIHelpers.stroke(spinner, Sci.Cyan, 4)
	local arc = Instance.new("UIGradient")
	arc.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.55, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	arc.Parent = ring

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
				card.button.BackgroundColor3 = if mine then Sci.PanelLight else Sci.Panel
				card.edge.Color = if mine then Sci.Green else card.color
				card.edge.Thickness = if mine then 3 else 2
				card.scale.Scale = if mine then 1.05 else math.min(card.scale.Scale, 1)
			end
		end

		local isLoading = inMatch and state == "Loading"
		loading.Visible = isLoading
		if isLoading then
			local info = MapConfig.get(stateFolder:GetAttribute(ATTR.MapId))
			loadingText.Text = if info then `LOADING {string.upper(info.DisplayName)}` else "LOADING..."
			loadingAbout.Text = if info then info.Description else ""
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

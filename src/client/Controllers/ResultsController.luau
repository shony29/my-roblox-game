--!strict
--[[
	ResultsController: the end-of-match screen.

	  * VICTORY / DEFEAT / DRAW, the final score and the mode.
	  * The MVP (most eliminations, then most damage).
	  * Every player's eliminations, deaths, damage and coins earned.
	  * REMATCH: if everyone presses it, the same players play again.
	    LOBBY: closes the screen (everyone returns to the lobby when the
	    results timer ends anyway).

	All numbers come from the server (the MatchResults remote); this script
	only checks they look right and displays them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared:WaitForChild("Match"):WaitForChild("MatchState"))
local Net = require(Shared:WaitForChild("Net"):WaitForChild("Net"))
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIHelpers = require(UIFolder:WaitForChild("UIHelpers"))
local ResponsiveScale = require(UIFolder:WaitForChild("ResponsiveScale"))

local Colors = Theme.Colors
local ATTR = MatchState.Attr
local ROW_HEIGHT = 30
local MAX_ROWS = 8

type Row = { name: string, team: MatchState.TeamId, eliminations: number, deaths: number, damage: number, coins: number }

local ResultsController = {}
local started = false

local function num(value: unknown): number
	return if typeof(value) == "number" and value == value then value else 0
end

-- Turns whatever arrived over the network into clean rows.
local function readRows(raw: unknown): { Row }
	local rows: { Row } = {}
	if typeof(raw) ~= "table" then
		return rows
	end
	for _, item in raw :: { any } do
		local team = MatchState.toTeam(if typeof(item) == "table" then item.team else nil)
		if typeof(item) == "table" and typeof(item.name) == "string" and team and #rows < MAX_ROWS then
			table.insert(rows, {
				name = string.sub(item.name, 1, 24),
				team = team,
				eliminations = num(item.eliminations),
				deaths = num(item.deaths),
				damage = num(item.damage),
				coins = num(item.coins),
			})
		end
	end
	table.sort(rows, function(a: Row, b: Row): boolean
		return a.eliminations > b.eliminations
	end)
	return rows
end

function ResultsController.start()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	local stateFolder = ReplicatedStorage:WaitForChild(MatchState.FOLDER_NAME)
	local rematchVote = Net.event("RematchVote")

	local gui = UIHelpers.screenGui("Results", 9, player:WaitForChild("PlayerGui"))
	ResponsiveScale.apply(gui)
	gui.Enabled = false

	local panel = UIHelpers.frame("Panel", UDim2.fromOffset(640, 420), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	panel.BackgroundTransparency = 0.08
	UIHelpers.corner(panel, UDim.new(0, 20))
	UIHelpers.stroke(panel, Colors.Yolk, 3)
	panel.Parent = gui
	local panelScale = Instance.new("UIScale")
	panelScale.Parent = panel

	local title = UIHelpers.label("Title", "", 48, Theme.Fonts.Title)
	title.Size = UDim2.new(1, 0, 0, 56)
	title.Position = UDim2.fromOffset(0, 12)
	UIHelpers.textStroke(title, 3)
	title.Parent = panel

	local subtitle = UIHelpers.label("Subtitle", "", 18)
	subtitle.Size = UDim2.new(1, 0, 0, 24)
	subtitle.Position = UDim2.fromOffset(0, 68)
	subtitle.TextColor3 = Colors.Shell
	subtitle.Parent = panel

	local mvpLabel = UIHelpers.label("MVP", "", 20, Theme.Fonts.Title)
	mvpLabel.Size = UDim2.new(1, 0, 0, 26)
	mvpLabel.Position = UDim2.fromOffset(0, 94)
	mvpLabel.TextColor3 = Colors.Yolk
	mvpLabel.Parent = panel

	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(24, 128)
	list.Size = UDim2.new(1, -48, 0, ROW_HEIGHT * (MAX_ROWS + 1))
	list.Parent = panel
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local function addRow(order: number, cells: { string }, color: Color3, bold: boolean)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.LayoutOrder = order
		row.Parent = list
		local widths = { 0.4, 0.15, 0.15, 0.15, 0.15 }
		local x = 0
		for i, text in cells do
			local cell = UIHelpers.label("Cell" .. i, text, if bold then 15 else 17, if bold then Theme.Fonts.Body else Theme.Fonts.Title)
			cell.Position = UDim2.fromScale(x, 0)
			cell.Size = UDim2.fromScale(widths[i], 1)
			cell.TextXAlignment = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
			cell.TextTruncate = Enum.TextTruncate.AtEnd
			cell.TextColor3 = color
			cell.Parent = row
			x += widths[i]
		end
	end

	local function makeButton(name: string, text: string, xScale: number, color: Color3): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.Text = text
		button.Font = Theme.Fonts.Title
		button.TextSize = 22
		button.TextColor3 = Colors.Ink
		button.BackgroundColor3 = color
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.Position = UDim2.new(xScale, 0, 1, -16)
		button.Size = UDim2.fromOffset(220, 46)
		button.Modal = true -- frees the mouse in first person while results show
		UIHelpers.corner(button, UDim.new(0, 12))
		UIHelpers.stroke(button, Colors.Ink, 2)
		button.Parent = panel
		return button
	end
	local rematchButton = makeButton("Rematch", "REMATCH", 0.3, Colors.Mint)
	local lobbyButton = makeButton("Lobby", "LOBBY", 0.7, Colors.White)

	local votedRematch = false
	local hasResults = false -- results arrived for the current match
	local dismissed = false -- the player pressed LOBBY
	local refresh: () -> ()
	rematchButton.Activated:Connect(function()
		if not votedRematch then
			votedRematch = true
			rematchVote:FireServer()
		end
	end)
	lobbyButton.Activated:Connect(function()
		dismissed = true
		refresh()
	end)

	local function show(results: { [string]: any })
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local myTeam = MatchState.toTeam(player:GetAttribute(MatchState.PlayerAttr.Team))
		local winner = MatchState.toTeam(results.winner)
		if winner == nil then
			title.Text = "DRAW"
			title.TextColor3 = Colors.White
		elseif winner == myTeam then
			title.Text = "VICTORY!"
			title.TextColor3 = Colors.Yolk
		else
			title.Text = "DEFEAT"
			title.TextColor3 = MatchState.teamInfo(winner).Color
		end
		local mode = if typeof(results.mode) == "string" then results.mode else ""
		subtitle.Text = `{mode} · Blue {num(results.scoreA)} – {num(results.scoreB)} Pink`
		local mvp = if typeof(results.mvp) == "string" then string.sub(results.mvp, 1, 24) else ""
		mvpLabel.Text = if mvp ~= "" then `MVP: {mvp}` else ""

		addRow(0, { "PLAYER", "ELIMS", "DEATHS", "DAMAGE", "COINS" }, Colors.Sky, true)
		for index, row in readRows(results.players) do
			addRow(index, {
				row.name,
				tostring(row.eliminations),
				tostring(row.deaths),
				tostring(math.floor(row.damage)),
				`+{row.coins}`,
			}, MatchState.teamInfo(row.team).Color, false)
		end

		votedRematch = false
		hasResults = true
		dismissed = false
		refresh()
	end

	Net.event("MatchResults").OnClientEvent:Connect(function(raw: unknown)
		if typeof(raw) == "table" then
			show(raw :: { [string]: any })
		end
	end)

	-- Shown only during MatchResults, once the results have arrived, until
	-- dismissed. (Results arrive just before the state switches over.)
	refresh = function()
		local state = MatchState.toState(stateFolder:GetAttribute(ATTR.State))
		if state == "Returning" or state == "Lobby" or state == "Countdown" then
			hasResults = false
		end
		local visible = hasResults and not dismissed and state == "MatchResults"
		if visible ~= gui.Enabled then
			gui.Enabled = visible
			if visible then
				panelScale.Scale = 0.85
				UIHelpers.tween(panelScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end
		if not visible then
			return
		end
		local votes = UIHelpers.numberAttribute(stateFolder, ATTR.RematchVotes)
		local needed = UIHelpers.numberAttribute(stateFolder, ATTR.RematchNeeded)
		rematchButton.Text = if votedRematch then `WAITING ({votes}/{needed})` else `REMATCH ({votes}/{needed})`
	end
	stateFolder:GetAttributeChangedSignal(ATTR.State):Connect(refresh)
	stateFolder:GetAttributeChangedSignal(ATTR.RematchVotes):Connect(refresh)
end

return ResultsController

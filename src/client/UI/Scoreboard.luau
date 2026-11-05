--!strict
--[[
	Scoreboard
	==========
	Hold Tab to see every player's eliminations and deaths for this round.
	On phones (no keyboard) a small "Scores" button toggles it instead.
	Players are sorted by most eliminations, then fewest deaths.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIHelpers = require(script.Parent:WaitForChild("UIHelpers"))
local GameContract = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("GameContract"))
local MatchState = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Match"):WaitForChild("MatchState"))

local Colors = Theme.Colors
local ATTR = GameContract.PlayerAttributes
local ROW_HEIGHT = 36
local REFRESH_INTERVAL = 0.5 -- seconds, only while the board is open

local Scoreboard = {}

type Row = {
	name: string,
	eliminations: number,
	deaths: number,
	isMe: boolean,
	teamColor: Color3?, -- Blue or Pink while in a match
}

local function collectRows(): { Row }
	local rows: { Row } = {}
	for _, p in Players:GetPlayers() do
		table.insert(rows, {
			name = p.DisplayName,
			eliminations = UIHelpers.numberAttribute(p, ATTR.RoundEliminations),
			deaths = UIHelpers.numberAttribute(p, ATTR.RoundDeaths),
			isMe = p == Players.LocalPlayer,
			teamColor = (function(): Color3?
				local team = MatchState.toTeam(p:GetAttribute(MatchState.PlayerAttr.Team))
				return if team then MatchState.teamInfo(team).Color else nil
			end)(),
		})
	end
	table.sort(rows, function(a: Row, b: Row)
		if a.eliminations ~= b.eliminations then
			return a.eliminations > b.eliminations
		end
		if a.deaths ~= b.deaths then
			return a.deaths < b.deaths
		end
		return a.name < b.name
	end)
	return rows
end

-- One line of the table: name, eliminations, deaths.
local function makeRow(parent: Instance, order: number, cells: { string }, isHeader: boolean, highlight: boolean, nameColor: Color3?)
	local row = Instance.new("Frame")
	row.Name = if isHeader then "Header" else "Row"
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BorderSizePixel = 0
	row.BackgroundColor3 = if highlight then Colors.Yolk else Colors.White
	row.BackgroundTransparency = if isHeader then 1 elseif highlight then 0.55 else (if order % 2 == 0 then 0.92 else 0.97)
	UIHelpers.corner(row, UDim.new(0, 8))
	row.Parent = parent

	local widths = { 0.6, 0.2, 0.2 }
	local x = 0
	for i, text in cells do
		local cell = UIHelpers.label("Cell" .. i, text, if isHeader then 16 else 18, if isHeader then Theme.Fonts.Body else Theme.Fonts.Title)
		cell.Position = UDim2.fromScale(x, 0)
		cell.Size = UDim2.fromScale(widths[i], 1)
		cell.TextXAlignment = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
		cell.TextTruncate = Enum.TextTruncate.AtEnd
		cell.TextColor3 = if isHeader then Colors.Sky elseif i == 1 and nameColor then nameColor else Colors.Shell
		if i == 1 then
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 12)
			pad.Parent = cell
		end
		cell.Parent = row
		x += widths[i]
	end
end

function Scoreboard.create(gui: ScreenGui)
	local panel = UIHelpers.frame("Scoreboard", UDim2.fromOffset(560, 460), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	panel.BackgroundTransparency = 0.12
	panel.Visible = false
	UIHelpers.corner(panel, UDim.new(0, 18))
	UIHelpers.stroke(panel, Colors.Yolk, 3)
	UIHelpers.padding(panel, 16)
	panel.Parent = gui

	local title = UIHelpers.label("Title", "SCOREBOARD", 30, Theme.Fonts.Title)
	title.Size = UDim2.new(1, 0, 0, 40)
	title.TextColor3 = Colors.Yolk
	UIHelpers.textStroke(title)
	title.Parent = panel

	local headerHolder = Instance.new("Frame")
	headerHolder.Name = "HeaderHolder"
	headerHolder.BackgroundTransparency = 1
	headerHolder.Position = UDim2.fromOffset(0, 46)
	headerHolder.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	headerHolder.Parent = panel
	local headerLayout = Instance.new("UIListLayout")
	headerLayout.Parent = headerHolder
	makeRow(headerHolder, 0, { "PLAYER", "ELIMS", "DEATHS" }, true, false)

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 46 + ROW_HEIGHT + 4)
	list.Size = UDim2.new(1, 0, 1, -(46 + ROW_HEIGHT + 4))
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Colors.Yolk
	list.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	local function refresh()
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for i, row in collectRows() do
			makeRow(list, i, { row.name, tostring(row.eliminations), tostring(row.deaths) }, false, row.isMe, row.teamColor)
		end
	end

	local isOpen = false
	local openCount = 0 -- lets an old refresh loop notice it should stop
	local function setOpen(open: boolean)
		if open == isOpen then
			return
		end
		isOpen = open
		panel.Visible = open
		if open then
			openCount += 1
			local myOpen = openCount
			refresh()
			-- Keep the numbers fresh while it's open.
			task.spawn(function()
				while isOpen and openCount == myOpen do
					task.wait(REFRESH_INTERVAL)
					if isOpen and openCount == myOpen then
						refresh()
					end
				end
			end)
		end
	end

	-- Hold Tab (PC)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if input.KeyCode == Enum.KeyCode.Tab and not gameProcessed then
			setOpen(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Tab then
			setOpen(false)
		end
	end)

	-- Tap button (phones and tablets)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local button = Instance.new("TextButton")
		button.Name = "ScoresButton"
		button.Text = "Scores"
		button.Font = Theme.Fonts.Title
		button.TextSize = 20
		button.TextColor3 = Colors.Ink
		button.BackgroundColor3 = Colors.Yolk
		button.AnchorPoint = Vector2.new(0, 0)
		button.Position = UDim2.fromOffset(Theme.Margin, 70)
		button.Size = UDim2.fromOffset(110, 44)
		button.AutoButtonColor = true
		UIHelpers.corner(button, UDim.new(1, 0))
		UIHelpers.stroke(button, Colors.Ink, 3)
		button.Parent = gui
		button.Activated:Connect(function()
			setOpen(not isOpen)
		end)
	end
end

return Scoreboard

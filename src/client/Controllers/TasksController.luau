--!strict
--[[
	TasksController: the Tasks panel, the task tracker and reward messages.

	  * Tasks panel (TASKS button in the lobby, or press T): Beginner Tasks
	    with a "GO TO THE RANGE" button, and Daily Quests with the time
	    left until they start fresh. Each card shows the task, a progress
	    bar and its coin reward.
	  * Tracker (left side, in the lobby and practice range): your beginner
	    tasks until they're all done, then today's daily quests.
	  * A message slides in whenever you finish a task or earn bonus coins.

	All progress comes from the server (the QuestBeginner, QuestDaily and
	QuestDay attributes, see PlayerDataService); this script only draws it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuestConfig = require(Shared:WaitForChild("Config"):WaitForChild("QuestConfig"))
local Net = require(Shared:WaitForChild("Net"):WaitForChild("Net"))
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIHelpers = require(UIFolder:WaitForChild("UIHelpers"))
local ResponsiveScale = require(UIFolder:WaitForChild("ResponsiveScale"))

type Quest = QuestConfig.Quest
type QuestState = QuestConfig.QuestState
type Card = { root: Frame, fill: Frame, count: TextLabel, done: TextLabel }
type TrackerRow = { root: Frame, text: TextLabel, count: TextLabel, fill: Frame }

local Colors = Theme.Colors
local player = Players.LocalPlayer
local CARD_COLOR = Color3.fromRGB(44, 50, 74)
local DONE_GREEN = Color3.fromRGB(110, 220, 120)

local TasksController = {}

local started = false
local isOpen = false
local gui: ScreenGui
local trackerGui: ScreenGui
local overlay: TextButton
local refreshAll: () -> () = function() end

-- Reads progress for a list of quests (daily ones count as zero on a new day).
local function readStates(list: { Quest }, attribute: string, daily: boolean): { [string]: QuestState }
	local states = QuestConfig.decode(player:GetAttribute(attribute))
	if daily and player:GetAttribute("QuestDay") ~= QuestConfig.today() then
		return {}
	end
	return states
end

local function countDone(list: { Quest }, states: { [string]: QuestState }): number
	local count = 0
	for _, quest in list do
		local state = states[quest.Id]
		if state and state.done then
			count += 1
		end
	end
	return count
end

local function formatLeft(seconds: number): string
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	return if hours > 0 then `{hours}h {minutes}m` else `{minutes}m`
end

-- One task card in the panel.
local function makeCard(parent: Instance, quest: Quest, order: number): Card
	local root = UIHelpers.frame(quest.Id, UDim2.fromOffset(232, 156), UDim2.new(), nil)
	root.LayoutOrder = order
	root.BackgroundColor3 = CARD_COLOR
	root.BackgroundTransparency = 0
	UIHelpers.corner(root, UDim.new(0, 14))
	UIHelpers.stroke(root, Color3.fromRGB(80, 90, 130), 2)
	root.Parent = parent

	local title = UIHelpers.label("Title", quest.Text, 18, Theme.Fonts.Title)
	title.Position = UDim2.fromOffset(8, 6)
	title.Size = UDim2.new(1, -16, 0, 44)
	title.TextWrapped = true
	title.TextColor3 = Colors.White
	title.Parent = root

	local icon = UIHelpers.label("Icon", quest.Icon, 34, Theme.Fonts.Title)
	icon.Position = UDim2.fromOffset(0, 50)
	icon.Size = UDim2.new(1, 0, 0, 40)
	icon.Parent = root

	local track = UIHelpers.frame("Track", UDim2.new(1, -28, 0, 20), UDim2.fromOffset(14, 96), nil)
	track.BackgroundColor3 = Color3.fromRGB(25, 28, 44)
	track.BackgroundTransparency = 0
	UIHelpers.corner(track, UDim.new(1, 0))
	track.Parent = root
	local fill = UIHelpers.frame("Fill", UDim2.fromScale(0, 1), UDim2.new(), nil)
	fill.BackgroundColor3 = Colors.Sky
	fill.BackgroundTransparency = 0
	UIHelpers.corner(fill, UDim.new(1, 0))
	fill.Parent = track
	local count = UIHelpers.label("Count", "0 / 0", 16, Theme.Fonts.Title)
	UIHelpers.textStroke(count)
	count.Parent = track

	local reward = UIHelpers.label("Reward", `+{quest.Reward} 🪙`, 20, Theme.Fonts.Title)
	reward.Position = UDim2.fromOffset(0, 122)
	reward.Size = UDim2.new(1, 0, 0, 28)
	reward.TextColor3 = Colors.Yolk
	UIHelpers.textStroke(reward)
	reward.Parent = root

	local done = UIHelpers.label("Done", "DONE ✓", 30, Theme.Fonts.Title)
	done.BackgroundColor3 = Color3.fromRGB(20, 60, 30)
	done.BackgroundTransparency = 0.25
	done.TextColor3 = DONE_GREEN
	UIHelpers.textStroke(done, 2)
	UIHelpers.corner(done, UDim.new(0, 14))
	done.ZIndex = 5
	done.Visible = false
	done.Parent = root

	return { root = root, fill = fill, count = count, done = done }
end

local function updateCard(card: Card, quest: Quest, state: QuestState?)
	local progress = if state then state.progress else 0
	local finished = state ~= nil and state.done
	card.fill.Size = UDim2.fromScale(math.clamp(progress / quest.Goal, 0, 1), 1)
	card.fill.BackgroundColor3 = if finished then DONE_GREEN else Colors.Sky
	card.count.Text = `{math.min(progress, quest.Goal)} / {quest.Goal}`
	card.done.Visible = finished
end

-- A section of the panel: header row and a row of cards.
local function makeSection(parent: Instance, order: number, list: { Quest }): (TextLabel, Frame, { [string]: Card })
	local header = UIHelpers.frame("Header", UDim2.new(1, 0, 0, 40), UDim2.new(), nil)
	header.BackgroundTransparency = 1
	header.LayoutOrder = order
	header.Parent = parent
	local title = UIHelpers.label("Title", "", 26, Theme.Fonts.Title)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(0.6, 0, 1, 0)
	title.TextColor3 = Colors.White
	UIHelpers.textStroke(title)
	title.Parent = header

	local row = UIHelpers.frame("Cards", UDim2.new(1, 0, 0, 156), UDim2.new(), nil)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order + 1
	row.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local cards: { [string]: Card } = {}
	for index, quest in list do
		cards[quest.Id] = makeCard(row, quest, index)
	end
	return title, header, cards
end

local function buildPanel()
	gui = UIHelpers.screenGui("Tasks", 22, player:WaitForChild("PlayerGui"))
	gui.Enabled = false
	ResponsiveScale.apply(gui)

	-- Dark backdrop. A button with Modal frees the mouse in first person.
	overlay = Instance.new("TextButton")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.AutoButtonColor = false
	overlay.Text = ""
	overlay.Modal = true
	overlay.Parent = gui
	overlay.Activated:Connect(function()
		TasksController.close()
	end)

	local panel = UIHelpers.frame("Panel", UDim2.fromOffset(780, 520), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	panel.BackgroundColor3 = Colors.Panel
	panel.BackgroundTransparency = 0.05
	UIHelpers.corner(panel, UDim.new(0, 20))
	UIHelpers.stroke(panel, Colors.Ink, 4)
	panel.Active = true -- clicks on the panel don't close it
	panel.Parent = gui
	UIHelpers.padding(panel, 18)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = panel

	local top = UIHelpers.frame("Top", UDim2.new(1, 0, 0, 44), UDim2.new(), nil)
	top.BackgroundTransparency = 1
	top.LayoutOrder = 0
	top.Parent = panel
	local title = UIHelpers.label("Title", "📋 TASKS", 34, Theme.Fonts.Title)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Colors.Yolk
	UIHelpers.textStroke(title, 2)
	title.Parent = top
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(44, 44)
	close.BackgroundColor3 = Colors.Coral
	close.Font = Theme.Fonts.Title
	close.TextSize = 26
	close.TextColor3 = Colors.White
	close.Text = "X"
	UIHelpers.corner(close, UDim.new(0, 10))
	UIHelpers.stroke(close, Colors.Ink, 3)
	close.Parent = top
	close.Activated:Connect(function()
		TasksController.close()
	end)

	local beginnerTitle, beginnerHeader, beginnerCards = makeSection(panel, 1, QuestConfig.Beginner)
	local goButton = Instance.new("TextButton")
	goButton.Name = "GoToRange"
	goButton.AnchorPoint = Vector2.new(1, 0.5)
	goButton.Position = UDim2.new(1, 0, 0.5, 0)
	goButton.Size = UDim2.fromOffset(230, 38)
	goButton.BackgroundColor3 = Colors.SkyDeep
	goButton.Font = Theme.Fonts.Title
	goButton.TextSize = 20
	goButton.TextColor3 = Colors.White
	goButton.Text = "🎯 GO TO THE RANGE"
	UIHelpers.corner(goButton, UDim.new(0, 10))
	UIHelpers.stroke(goButton, Colors.Ink, 3)
	UIHelpers.textStroke(goButton)
	goButton.Parent = beginnerHeader
	goButton.Activated:Connect(function()
		Net.event("PracticeEnter"):FireServer()
		TasksController.close()
	end)

	local dailyTitle, dailyHeader, dailyCards = makeSection(panel, 3, QuestConfig.Daily)
	local resetLabel = UIHelpers.label("Reset", "", 18, Theme.Fonts.Title)
	resetLabel.AnchorPoint = Vector2.new(1, 0)
	resetLabel.Position = UDim2.new(1, 0, 0, 0)
	resetLabel.Size = UDim2.new(0.45, 0, 1, 0)
	resetLabel.TextXAlignment = Enum.TextXAlignment.Right
	resetLabel.TextColor3 = Color3.fromRGB(170, 180, 210)
	resetLabel.Parent = dailyHeader

	local function refreshPanel()
		local beginner = readStates(QuestConfig.Beginner, "QuestBeginner", false)
		local daily = readStates(QuestConfig.Daily, "QuestDaily", true)
		beginnerTitle.Text = `Beginner Tasks [{countDone(QuestConfig.Beginner, beginner)}/{#QuestConfig.Beginner}]`
		dailyTitle.Text = `Daily Quests [{countDone(QuestConfig.Daily, daily)}/{#QuestConfig.Daily}]`
		for _, quest in QuestConfig.Beginner do
			updateCard(beginnerCards[quest.Id], quest, beginner[quest.Id])
		end
		for _, quest in QuestConfig.Daily do
			updateCard(dailyCards[quest.Id], quest, daily[quest.Id])
		end
		resetLabel.Text = `New quests in {formatLeft(QuestConfig.secondsUntilReset())}`
		-- Only from the lobby (not mid-match).
		local status = player:GetAttribute("MatchStatus")
		goButton.Visible = status == "Lobby" or status == "Queued"
	end
	return refreshPanel
end

-- The small list on the left of the screen.
local function buildTracker(): () -> ()
	trackerGui = UIHelpers.screenGui("TaskTracker", 2, player:WaitForChild("PlayerGui"))
	ResponsiveScale.apply(trackerGui)
	local box = UIHelpers.frame("Tracker", UDim2.fromOffset(290, 0), UDim2.new(0, 12, 0.36, 0), nil)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.BackgroundColor3 = Colors.Panel
	box.BackgroundTransparency = 0.3
	UIHelpers.corner(box, UDim.new(0, 12))
	box.Parent = trackerGui
	UIHelpers.padding(box, 10)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = box
	local title = UIHelpers.label("Title", "", 20, Theme.Fonts.Title)
	title.Size = UDim2.new(1, 0, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Colors.White
	UIHelpers.textStroke(title)
	title.LayoutOrder = 0
	title.Parent = box

	local rows: { TrackerRow } = {}
	for index = 1, 3 do
		local root = UIHelpers.frame("Row", UDim2.new(1, 0, 0, 34), UDim2.new(), nil)
		root.BackgroundTransparency = 1
		root.LayoutOrder = index
		root.Parent = box
		local text = UIHelpers.label("Text", "", 16, Theme.Fonts.Title)
		text.Size = UDim2.new(0.78, 0, 0, 22)
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.TextColor3 = Colors.White
		text.Parent = root
		local count = UIHelpers.label("Count", "", 16, Theme.Fonts.Title)
		count.AnchorPoint = Vector2.new(1, 0)
		count.Position = UDim2.new(1, 0, 0, 0)
		count.Size = UDim2.new(0.22, 0, 0, 22)
		count.TextXAlignment = Enum.TextXAlignment.Right
		count.TextColor3 = Colors.Yolk
		count.Parent = root
		local track = UIHelpers.frame("Track", UDim2.new(1, 0, 0, 6), UDim2.fromOffset(0, 26), nil)
		track.BackgroundColor3 = Color3.fromRGB(25, 28, 44)
		track.BackgroundTransparency = 0
		UIHelpers.corner(track, UDim.new(1, 0))
		track.Parent = root
		local fill = UIHelpers.frame("Fill", UDim2.fromScale(0, 1), UDim2.new(), nil)
		fill.BackgroundColor3 = Colors.Sky
		fill.BackgroundTransparency = 0
		UIHelpers.corner(fill, UDim.new(1, 0))
		fill.Parent = track
		table.insert(rows, { root = root, text = text, count = count, fill = fill })
	end

	return function()
		local status = player:GetAttribute("MatchStatus")
		local beginner = readStates(QuestConfig.Beginner, "QuestBeginner", false)
		local list, states, heading = QuestConfig.Beginner, beginner, "Beginner Tasks"
		if countDone(QuestConfig.Beginner, beginner) >= #QuestConfig.Beginner then
			list, states, heading = QuestConfig.Daily, readStates(QuestConfig.Daily, "QuestDaily", true), "Daily Quests"
		end
		trackerGui.Enabled = not isOpen and (status == "Lobby" or status == "Queued" or status == "Practice")
		title.Text = `{heading} [{countDone(list, states)}/{#list}]`
		for index, row in rows do
			local quest = list[index]
			row.root.Visible = quest ~= nil
			if quest then
				local state = states[quest.Id]
				local progress = if state then state.progress else 0
				local finished = state ~= nil and state.done
				row.text.Text = `{quest.Icon} {quest.Text}`
				row.count.Text = if finished then "✓" else `{math.min(progress, quest.Goal)}/{quest.Goal}`
				row.fill.Size = UDim2.fromScale(math.clamp(progress / quest.Goal, 0, 1), 1)
				row.fill.BackgroundColor3 = if finished then DONE_GREEN else Colors.Sky
			end
		end
	end
end

-- "Task done: ...  +50 🪙" slides in at the top, one message at a time.
local function buildToasts(): (string, number) -> ()
	local toastGui = UIHelpers.screenGui("Rewards", 30, player:WaitForChild("PlayerGui"))
	ResponsiveScale.apply(toastGui)
	local pill = UIHelpers.frame("Toast", UDim2.fromOffset(560, 50), UDim2.new(0.5, 0, 0, -60), Vector2.new(0.5, 0))
	pill.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
	pill.BackgroundTransparency = 0.05
	UIHelpers.corner(pill, UDim.new(1, 0))
	UIHelpers.stroke(pill, Colors.Ink, 3)
	pill.Visible = false
	pill.Parent = toastGui
	local text = UIHelpers.label("Text", "", 22, Theme.Fonts.Title)
	text.TextColor3 = Colors.White
	UIHelpers.textStroke(text, 2)
	text.Parent = pill

	local queue: { string } = {}
	local showing = false
	local function showNext()
		local message = table.remove(queue, 1)
		if message == nil then
			showing = false
			return
		end
		showing = true
		text.Text = message
		pill.Visible = true
		pill.Position = UDim2.new(0.5, 0, 0, -60)
		UIHelpers.tween(pill, 0.35, { Position = UDim2.new(0.5, 0, 0, 112) }, Enum.EasingStyle.Back)
		task.delay(2.6, function()
			UIHelpers.tween(pill, 0.3, { Position = UDim2.new(0.5, 0, 0, -60) })
			task.delay(0.35, showNext)
		end)
	end
	return function(message: string, coins: number)
		table.insert(queue, if coins > 0 then `{message}   +{coins} 🪙` else message)
		if not showing then
			showNext()
		end
	end
end

function TasksController.open()
	TasksController.start()
	if isOpen then
		return
	end
	isOpen = true
	refreshAll()
	gui.Enabled = true
end

function TasksController.close()
	if not started or not isOpen then
		return
	end
	isOpen = false
	gui.Enabled = false
	refreshAll()
end

function TasksController.toggle()
	if isOpen then
		TasksController.close()
	else
		TasksController.open()
	end
end

function TasksController.start()
	if started then
		return
	end
	started = true
	local refreshPanel = buildPanel()
	local refreshTracker = buildTracker()
	local toast = buildToasts()
	refreshAll = function()
		refreshPanel()
		refreshTracker()
	end

	for _, attribute in { "QuestBeginner", "QuestDaily", "QuestDay", "MatchStatus" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshAll)
	end
	Net.event("RewardToast").OnClientEvent:Connect(function(message: unknown, coins: unknown)
		if typeof(message) == "string" then
			toast(message, if typeof(coins) == "number" then coins else 0)
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.T then
			local status = player:GetAttribute("MatchStatus")
			if status == "Lobby" or status == "Queued" or status == "Practice" or isOpen then
				TasksController.toggle()
			end
		end
	end)
	-- The reset countdown ticks while the panel is open.
	task.spawn(function()
		while true do
			task.wait(1)
			if isOpen then
				refreshPanel()
			end
		end
	end)
	refreshAll()
end

return TasksController

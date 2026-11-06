--!strict
--[[
	NotificationsController: the bell at the top right of the lobby.

	It collects short messages while you play and lists them under the bell,
	newest first. A red badge on the bell counts the ones you haven't seen.
	Messages come from:
	  * rewards (a task done, a victory bonus)
	  * levelling up
	  * win streaks (2 or more wins in a row)
	  * the Daily Squishy being ready again
	  * this month's themed items arriving in the shop (when you join)
	Nothing here is saved: the list starts fresh each time you play.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"):WaitForChild("Net"))
local GameContract = require(Shared:WaitForChild("Net"):WaitForChild("GameContract"))
local Progression = require(Shared:WaitForChild("Data"):WaitForChild("Progression"))
local ShopConfig = require(Shared:WaitForChild("Config"):WaitForChild("ShopConfig"))
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIHelpers = require(UIFolder:WaitForChild("UIHelpers"))
local ResponsiveScale = require(UIFolder:WaitForChild("ResponsiveScale"))

type Note = { text: string, color: Color3, at: number }

local player = Players.LocalPlayer
local ATTR = GameContract.PlayerAttributes
local Sci = Theme.SciFi
local SCI_FONT = Theme.SciFiFonts.Title
local BODY_FONT = Theme.SciFiFonts.Body
local MAX_NOTES = 20
local WIDTH = 330

local NotificationsController = {}

local started = false
local shown = false
local notes: { Note } = {}
local unread = 0
local listeners: { (number) -> () } = {}
local gui: ScreenGui
local list: ScrollingFrame
local emptyLabel: TextLabel

local function timeAgo(seconds: number): string
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return `{math.floor(seconds / 60)} min ago`
	end
	return `{math.floor(seconds / 3600)} h ago`
end

local function setUnread(count: number)
	unread = count
	for _, listener in listeners do
		task.spawn(listener, unread)
	end
end

-- Draws the list again (only while it's open).
local function redraw()
	if not shown then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	emptyLabel.Visible = #notes == 0
	local now = os.clock()
	for index, note in notes do
		-- A card: a coloured stripe on the left, the message, and when it came.
		local row = UIHelpers.frame("Note", UDim2.new(1, -8, 0, 0), UDim2.new(), nil)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.BackgroundColor3 = Sci.PanelLight
		row.BackgroundTransparency = 0.1
		row.LayoutOrder = index
		UIHelpers.corner(row, UDim.new(0, 10))
		row.Parent = list
		local stripe = UIHelpers.frame("Stripe", UDim2.new(0, 4, 1, -14), UDim2.fromOffset(7, 7), nil)
		stripe.BackgroundColor3 = note.color
		stripe.BackgroundTransparency = 0
		UIHelpers.corner(stripe, UDim.new(1, 0))
		stripe.Parent = row
		local body = UIHelpers.frame("Body", UDim2.new(1, -28, 0, 0), UDim2.fromOffset(18, 0), nil)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.BackgroundTransparency = 1
		body.Parent = row
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 8)
		padding.PaddingBottom = UDim.new(0, 8)
		padding.Parent = body
		local bodyLayout = Instance.new("UIListLayout")
		bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
		bodyLayout.Padding = UDim.new(0, 3)
		bodyLayout.Parent = body
		local text = UIHelpers.label("Text", note.text, 14, BODY_FONT)
		text.Size = UDim2.new(1, 0, 0, 0)
		text.AutomaticSize = Enum.AutomaticSize.Y
		text.TextWrapped = true
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextColor3 = Sci.Text
		text.LayoutOrder = 1
		text.Parent = body
		local when = UIHelpers.label("When", timeAgo(now - note.at), 11, BODY_FONT)
		when.Size = UDim2.new(1, 0, 0, 14)
		when.TextXAlignment = Enum.TextXAlignment.Left
		when.TextColor3 = Sci.Dim
		when.LayoutOrder = 2
		when.Parent = body
	end
end

local function build()
	gui = UIHelpers.screenGui("Notifications", 6, player:WaitForChild("PlayerGui"))
	gui.Enabled = false
	ResponsiveScale.apply(gui)

	local panel = UIHelpers.frame("Panel", UDim2.fromOffset(WIDTH, 330), UDim2.new(1, -16, 0, 76), Vector2.new(1, 0))
	panel.BackgroundColor3 = Sci.Panel
	panel.BackgroundTransparency = 0.05
	UIHelpers.corner(panel, UDim.new(0, 14))
	UIHelpers.stroke(panel, Sci.Yellow, 1.5).Transparency = 0.2
	panel.Parent = gui

	local title = UIHelpers.label("Title", "NOTIFICATIONS", 14, SCI_FONT)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -32, 0, 24)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Sci.Yellow
	title.Parent = panel
	local line = UIHelpers.frame("NeonLine", UDim2.new(1, -32, 0, 2), UDim2.fromOffset(16, 38), nil)
	line.BackgroundColor3 = Sci.Yellow
	line.BackgroundTransparency = 0.3
	line.Parent = panel

	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(12, 48)
	list.Size = UDim2.new(1, -16, 1, -58)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Sci.Yellow
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	emptyLabel = UIHelpers.label("Empty", "Nothing new yet. Go play a match!", 14, BODY_FONT)
	emptyLabel.Position = UDim2.fromOffset(16, 56)
	emptyLabel.Size = UDim2.new(1, -32, 0, 40)
	emptyLabel.TextWrapped = true
	emptyLabel.TextColor3 = Sci.Dim
	emptyLabel.Parent = panel
end

-- Adds a message to the top of the list.
function NotificationsController.push(text: string, color: Color3?)
	table.insert(notes, 1, { text = text, color = color or Sci.Cyan, at = os.clock() })
	while #notes > MAX_NOTES do
		table.remove(notes)
	end
	if shown then
		redraw()
	else
		setUnread(unread + 1)
	end
end

-- Calls `callback` with the number of unseen messages whenever it changes.
function NotificationsController.onUnreadChanged(callback: (number) -> ())
	table.insert(listeners, callback)
	task.spawn(callback, unread)
end

function NotificationsController.isShown(): boolean
	return shown
end

function NotificationsController.show()
	NotificationsController.start()
	shown = true
	gui.Enabled = true
	setUnread(0)
	redraw()
end

function NotificationsController.hide()
	if not started then
		return
	end
	shown = false
	gui.Enabled = false
end

function NotificationsController.toggle()
	if shown then
		NotificationsController.hide()
	else
		NotificationsController.show()
	end
end

function NotificationsController.start()
	if started then
		return
	end
	started = true
	build()

	-- Rewards from the server (the same ones that slide in at the top).
	Net.event("RewardToast").OnClientEvent:Connect(function(message: unknown, coins: unknown)
		if typeof(message) == "string" then
			local amount = if typeof(coins) == "number" then coins else 0
			NotificationsController.push(if amount > 0 then `{message}  +{amount} coins` else message, Sci.Green)
		end
	end)

	-- Levelling up.
	local lastLevel: number? = nil
	local function checkLevel()
		local xp = player:GetAttribute(ATTR.XP)
		if typeof(xp) ~= "number" then
			return
		end
		local level = Progression.levelFromXp(xp)
		if lastLevel and level > lastLevel then
			NotificationsController.push(`Level up! You're now level {level}.`, Sci.Cyan)
		end
		lastLevel = level
	end
	player:GetAttributeChangedSignal(ATTR.XP):Connect(checkLevel)
	checkLevel()

	-- Win streaks.
	local lastStreak: number? = nil
	local function checkStreak()
		local streak = player:GetAttribute(ATTR.WinStreak)
		if typeof(streak) ~= "number" then
			return
		end
		if lastStreak then
			if streak >= 2 and streak > lastStreak then
				NotificationsController.push(`{streak} wins in a row! Keep it going.`, Sci.Yellow)
			elseif streak == 0 and lastStreak >= 2 then
				NotificationsController.push(`Your win streak ended at {lastStreak}. Start a new one!`, Sci.Dim)
			end
		end
		lastStreak = streak
	end
	player:GetAttributeChangedSignal(ATTR.WinStreak):Connect(checkStreak)
	checkStreak()

	-- This month's themed items.
	local month = ShopConfig.currentMonth()
	for _, theme in ShopConfig.Themes do
		if theme.Month == month then
			NotificationsController.push(`New this month: {theme.Name} items are in the shop!`, Sci.Purple)
		end
	end

	-- The Daily Squishy being ready (once each time it becomes ready).
	task.spawn(function()
		local toldFor = -1
		while true do
			local readyAt = player:GetAttribute(ATTR.DailyReadyAt)
			if typeof(readyAt) == "number" and readyAt ~= toldFor and Workspace:GetServerTimeNow() >= readyAt then
				toldFor = readyAt
				NotificationsController.push("Your Daily Squishy is ready! Find the machine in the lobby.", Sci.Green)
			end
			task.wait(5)
		end
	end)

	-- Keep the "x min ago" times fresh while the list is open.
	task.spawn(function()
		while true do
			task.wait(30)
			redraw()
		end
	end)
end

return NotificationsController

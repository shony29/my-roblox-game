--!strict
--[[
	CornerMenuController: three round sci-fi buttons at the top right of the
	screen, in the lobby and the practice range.

	  * Settings       opens the Settings window (SettingsController)
	  * Tasks          shows or hides your task list under the buttons
	                   (TasksController); its badge counts tasks still to do
	  * Notifications  shows or hides your recent messages
	                   (NotificationsController); a red badge counts new ones

	Only one list is open at a time. The icons are drawn from shapes
	(UI/Icons), so they look the same everywhere.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchState = require(Shared:WaitForChild("Match"):WaitForChild("MatchState"))
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIHelpers = require(UIFolder:WaitForChild("UIHelpers"))
local ResponsiveScale = require(UIFolder:WaitForChild("ResponsiveScale"))
local Icons = require(UIFolder:WaitForChild("Icons"))
local SettingsController = require(script.Parent:WaitForChild("SettingsController"))
local TasksController = require(script.Parent:WaitForChild("TasksController"))
local NotificationsController = require(script.Parent:WaitForChild("NotificationsController"))

local player = Players.LocalPlayer
local PATTR = MatchState.PlayerAttr
local Sci = Theme.SciFi
local SCI_FONT = Theme.SciFiFonts.Title
local BUTTON_SIZE = 50

local CornerMenuController = {}
local started = false

-- A round dark button with a neon ring and a drawn icon. Returns the button
-- and a function that shows a number badge on it (0 hides the badge).
local function roundButton(name: string, accent: Color3, badgeColor: Color3, drawIcon: (GuiObject, Color3, Color3) -> ()): (TextButton, (number) -> ())
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	button.BackgroundColor3 = Sci.Void
	button.BackgroundTransparency = 0.15
	button.AutoButtonColor = false
	button.Text = ""
	UIHelpers.corner(button, UDim.new(1, 0))
	UIHelpers.stroke(button, accent, 2).Transparency = 0.1
	drawIcon(Icons.holder(button, UDim2.fromOffset(26, 26), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)), accent, Sci.Void)

	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		UIHelpers.tween(scale, 0.12, { Scale = 1.08 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		UIHelpers.tween(scale, 0.12, { Scale = 1 })
	end)

	local badge = UIHelpers.label("Badge", "", 11, SCI_FONT)
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -6, 0, 6)
	badge.Size = UDim2.fromOffset(20, 20)
	badge.BackgroundColor3 = badgeColor
	badge.BackgroundTransparency = 0
	badge.TextColor3 = Sci.Void
	badge.ZIndex = 6
	badge.Visible = false
	UIHelpers.corner(badge, UDim.new(1, 0))
	badge.Parent = button

	local function setBadge(count: number)
		badge.Visible = count > 0
		badge.Text = if count > 9 then "9+" else tostring(count)
	end
	return button, setBadge
end

function CornerMenuController.start()
	if started then
		return
	end
	started = true
	SettingsController.start()
	TasksController.start()
	NotificationsController.start()

	local gui = UIHelpers.screenGui("CornerMenu", 5, player:WaitForChild("PlayerGui"))
	ResponsiveScale.apply(gui)

	local row = UIHelpers.frame("Buttons", UDim2.fromOffset(3 * BUTTON_SIZE + 2 * 10, BUTTON_SIZE), UDim2.new(1, -16, 0, 14), Vector2.new(1, 0))
	row.BackgroundTransparency = 1
	row.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = row

	local settings = roundButton("Settings", Sci.Cyan, Sci.Cyan, Icons.gear)
	settings.LayoutOrder = 1
	settings.Parent = row
	local tasks, setTasksBadge = roundButton("Tasks", Sci.Green, Sci.Green, Icons.calendar)
	tasks.LayoutOrder = 2
	tasks.Parent = row
	local bell, setBellBadge = roundButton("Notifications", Sci.Yellow, Sci.Red, Icons.bell)
	bell.LayoutOrder = 3
	bell.Parent = row

	settings.Activated:Connect(function()
		TasksController.hideTracker()
		NotificationsController.hide()
		SettingsController.toggle()
	end)
	tasks.Activated:Connect(function()
		NotificationsController.hide()
		TasksController.toggleTracker()
	end)
	bell.Activated:Connect(function()
		TasksController.hideTracker()
		NotificationsController.toggle()
	end)

	TasksController.onUnfinishedChanged(setTasksBadge)
	NotificationsController.onUnreadChanged(setBellBadge)

	-- Only in the lobby and the practice range (a match has its own screen).
	local function refresh()
		local status = player:GetAttribute(PATTR.Status)
		local visible = status == "Lobby" or status == "Queued" or status == "Practice"
		gui.Enabled = visible
		if not visible then
			TasksController.hideTracker()
			NotificationsController.hide()
		end
	end
	player:GetAttributeChangedSignal(PATTR.Status):Connect(refresh)
	refresh()
end

return CornerMenuController

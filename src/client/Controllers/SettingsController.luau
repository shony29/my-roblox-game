--!strict
--[[
	SettingsController: the Settings window (the gear button at the top
	right of the lobby).

	  GENERAL tab:
	  * SOUND              how loud all game sounds are
	  * MOUSE SENSITIVITY  how fast the camera turns
	  * FIELD OF VIEW      how wide you see in first person
	  CONTROLS tab: every key and button and what it does, for the device
	  you're playing on (keyboard and mouse, touch screen or game
	  controller; you can look at the others too).

	Changes apply right away and are saved with your other data, so they
	come back next time you play. The server keeps every number inside its
	allowed range (Data/PlayerDataSchema.SETTINGS) and sends the saved
	values back as the SettingVolume / SettingSensitivity /
	SettingFieldOfView attributes, which this script applies.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"):WaitForChild("Net"))
local GameContract = require(Shared:WaitForChild("Net"):WaitForChild("GameContract"))
local Schema = require(Shared:WaitForChild("Data"):WaitForChild("PlayerDataSchema"))
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIHelpers = require(UIFolder:WaitForChild("UIHelpers"))
local ResponsiveScale = require(UIFolder:WaitForChild("ResponsiveScale"))

type Row = { key: string, set: (number) -> () }

local player = Players.LocalPlayer
local ATTR = GameContract.PlayerAttributes
local Sci = Theme.SciFi
local SCI_FONT = Theme.SciFiFonts.Title
local BODY_FONT = Theme.SciFiFonts.Body
local SAVE_DELAY = 0.6 -- seconds after the last change before saving

local SettingsController = {}

local started = false
local isOpen = false
local gui: ScreenGui
local rows: { Row } = {}
local saveToken = 0
local showControlsForDevice: () -> () = function() end
local current = {
	volume = Schema.SETTINGS.volume.default,
	sensitivity = Schema.SETTINGS.sensitivity.default,
	fieldOfView = Schema.SETTINGS.fieldOfView.default,
}

-- Puts the settings into effect on this screen.
local function apply()
	player:SetAttribute("VolumeMaster", current.volume) -- read by every sound (FeedbackController, WeaponEffects)
	player:SetAttribute("AppliedFieldOfView", current.fieldOfView) -- read by MovementController
	UserInputService.MouseDeltaSensitivity = current.sensitivity
end

-- Saves a moment after the last change (dragging a slider sends one save).
local function saveSoon()
	saveToken += 1
	local myToken = saveToken
	task.delay(SAVE_DELAY, function()
		if myToken == saveToken then
			Net.event("SettingsSave"):FireServer(current.volume, current.sensitivity, current.fieldOfView)
		end
	end)
end

-- One setting: its name, value text and a slider you can drag or tap.
local function makeRow(parent: Frame, order: number, key: string, title: string, format: (number) -> string): Row
	local range = (Schema.SETTINGS :: any)[key]
	local row = UIHelpers.frame(key, UDim2.new(1, 0, 0, 66), UDim2.new(), nil)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local label = UIHelpers.label("Title", title, 14, SCI_FONT)
	label.Size = UDim2.new(0.7, 0, 0, 24)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Sci.Dim
	label.Parent = row
	local value = UIHelpers.label("Value", "", 17, BODY_FONT)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, 0, 0, 0)
	value.Size = UDim2.new(0.3, 0, 0, 24)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextColor3 = Sci.Cyan
	value.Parent = row

	local track = Instance.new("TextButton") -- a button, so taps and clicks land on it
	track.Name = "Track"
	track.AutoButtonColor = false
	track.Text = ""
	track.Position = UDim2.fromOffset(0, 34)
	track.Size = UDim2.new(1, 0, 0, 14)
	track.BackgroundColor3 = Sci.Inset
	UIHelpers.corner(track, UDim.new(1, 0))
	UIHelpers.stroke(track, Sci.Edge, 1)
	track.Parent = row
	local fill = UIHelpers.frame("Fill", UDim2.fromScale(0, 1), UDim2.new(), nil)
	fill.BackgroundColor3 = Sci.Cyan
	fill.BackgroundTransparency = 0
	UIHelpers.corner(fill, UDim.new(1, 0))
	fill.Parent = track
	local knob = UIHelpers.frame("Knob", UDim2.fromOffset(24, 24), UDim2.fromScale(0, 0.5), Vector2.new(0.5, 0.5))
	knob.BackgroundColor3 = Sci.Text
	knob.BackgroundTransparency = 0
	knob.ZIndex = 3
	UIHelpers.corner(knob, UDim.new(1, 0))
	UIHelpers.stroke(knob, Sci.Cyan, 2)
	knob.Parent = track

	local function show(number: number)
		local fraction = (number - range.min) / (range.max - range.min)
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		knob.Position = UDim2.fromScale(math.clamp(fraction, 0, 1), 0.5)
		value.Text = format(number)
	end

	local function setFromScreenX(x: number)
		local fraction = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local number = Schema.cleanSetting(key, range.min + fraction * (range.max - range.min))
		;(current :: any)[key] = number
		show(number)
		apply()
		saveSoon()
	end

	local dragging = false
	track.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromScreenX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromScreenX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return { key = key, set = show }
end

-- What every key does, per device. (Keep in step with MovementConfig's key
-- lists and the controllers that read input.)
type ControlRow = { action: string, keys: string }
local CONTROLS: { [string]: { ControlRow } } = {
	Keyboard = {
		{ action = "Move", keys = "W A S D" },
		{ action = "Look and aim", keys = "MOUSE" },
		{ action = "Shoot (hold for automatic guns)", keys = "LEFT CLICK" },
		{ action = "Reload", keys = "R" },
		{ action = "Switch gun", keys = "1 - 8 / WHEEL" },
		{ action = "Jump (again in the air: double jump)", keys = "SPACE" },
		{ action = "Sprint (hold)", keys = "SHIFT" },
		{ action = "Dash", keys = "Q" },
		{ action = "Slide (while running)", keys = "CTRL / C" },
		{ action = "Scoreboard (hold)", keys = "TAB" },
		{ action = "Shop", keys = "B" },
		{ action = "Tasks", keys = "T" },
		{ action = "Guns in the shop (lobby)", keys = "G" },
		{ action = "Leave the range / free for all", keys = "L" },
		{ action = "Use (doors, machines, counters)", keys = "E" },
	},
	Touch = {
		{ action = "Move", keys = "LEFT STICK" },
		{ action = "Look and aim", keys = "DRAG RIGHT SIDE" },
		{ action = "Shoot (hold)", keys = "FIRE" },
		{ action = "Reload", keys = "RELOAD" },
		{ action = "Switch gun", keys = "SWAP" },
		{ action = "Jump (again in the air: double jump)", keys = "JUMP" },
		{ action = "Dash", keys = "DASH" },
		{ action = "Slide (while running)", keys = "SLIDE" },
		{ action = "Shop, tasks, guns", keys = "LEFT BUTTONS" },
		{ action = "Settings, task list, messages", keys = "TOP RIGHT" },
		{ action = "Use (doors, machines, counters)", keys = "TAP PROMPT" },
	},
	Controller = {
		{ action = "Move", keys = "LEFT STICK" },
		{ action = "Look and aim", keys = "RIGHT STICK" },
		{ action = "Shoot (hold)", keys = "RT" },
		{ action = "Reload", keys = "RB" },
		{ action = "Switch gun", keys = "Y" },
		{ action = "Jump (again in the air: double jump)", keys = "A" },
		{ action = "Sprint", keys = "L3 (PRESS STICK)" },
		{ action = "Dash", keys = "X" },
		{ action = "Slide (while running)", keys = "B" },
		{ action = "Use (doors, machines, counters)", keys = "X (HOLD NEAR)" },
	},
}
local DEVICES = { "Keyboard", "Touch", "Controller" }

-- The device you're playing on right now.
local function currentDevice(): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif string.find(last.Name, "Gamepad") then
		return "Controller"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Controller"
	end
	return "Keyboard"
end

local function refreshRows()
	for _, row in rows do
		row.set((current :: any)[row.key])
	end
end

local function build()
	gui = UIHelpers.screenGui("Settings", 24, player:WaitForChild("PlayerGui"))
	gui.Enabled = false
	ResponsiveScale.apply(gui)

	-- Dark backdrop; Modal frees the mouse in first person. Clicking it closes.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Modal = true
	backdrop.Parent = gui
	backdrop.Activated:Connect(function()
		SettingsController.close()
	end)

	local panel = UIHelpers.frame("Panel", UDim2.fromOffset(560, 470), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	panel.BackgroundColor3 = Sci.Panel
	panel.BackgroundTransparency = 0
	panel.Active = true -- clicks on the window don't close it
	UIHelpers.corner(panel, UDim.new(0, 18))
	UIHelpers.stroke(panel, Sci.Cyan, 2)
	panel.Parent = backdrop

	local title = UIHelpers.label("Title", "SETTINGS", 26, SCI_FONT)
	title.Position = UDim2.fromOffset(24, 16)
	title.Size = UDim2.new(1, -100, 0, 40)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Sci.Green
	title.Parent = panel
	local line = UIHelpers.frame("NeonLine", UDim2.new(1, -48, 0, 2), UDim2.fromOffset(24, 62), nil)
	line.BackgroundColor3 = Sci.Cyan
	line.BackgroundTransparency = 0
	line.Parent = panel

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 14)
	close.Size = UDim2.fromOffset(42, 42)
	close.BackgroundColor3 = Sci.Red
	close.Font = SCI_FONT
	close.TextSize = 18
	close.TextColor3 = Sci.Void
	close.Text = "X"
	UIHelpers.corner(close, UDim.new(0, 10))
	close.Parent = panel
	close.Activated:Connect(function()
		SettingsController.close()
	end)

	-- Two tabs: GENERAL (the sliders) and CONTROLS (what every key does).
	local general = UIHelpers.frame("General", UDim2.new(1, 0, 1, -126), UDim2.fromOffset(0, 126), nil)
	general.BackgroundTransparency = 1
	general.Parent = panel
	local controls = UIHelpers.frame("Controls", UDim2.new(1, 0, 1, -126), UDim2.fromOffset(0, 126), nil)
	controls.BackgroundTransparency = 1
	controls.Visible = false
	controls.Parent = panel
	local tabButtons: { [string]: TextButton } = {}
	local function selectTab(name: string)
		general.Visible = name == "GENERAL"
		controls.Visible = name == "CONTROLS"
		for tabName, button in tabButtons do
			local active = tabName == name
			button.BackgroundColor3 = if active then Sci.Cyan else Sci.PanelLight
			button.TextColor3 = if active then Sci.Void else Sci.Dim
		end
	end
	for index, tabName in { "GENERAL", "CONTROLS" } do
		local tab = Instance.new("TextButton")
		tab.Name = tabName
		tab.Position = UDim2.fromOffset(24 + (index - 1) * 172, 76)
		tab.Size = UDim2.fromOffset(160, 38)
		tab.AutoButtonColor = false
		tab.Font = SCI_FONT
		tab.TextSize = 13
		tab.Text = tabName
		UIHelpers.corner(tab, UDim.new(0, 8))
		tab.Parent = panel
		tab.Activated:Connect(function()
			selectTab(tabName)
		end)
		tabButtons[tabName] = tab
	end

	-- CONTROLS: pick a device (yours is picked first), then the list.
	local deviceButtons: { [string]: TextButton } = {}
	local controlList = Instance.new("ScrollingFrame")
	controlList.Name = "List"
	controlList.Position = UDim2.fromOffset(24, 46)
	controlList.Size = UDim2.new(1, -40, 1, -60)
	controlList.BackgroundTransparency = 1
	controlList.BorderSizePixel = 0
	controlList.ScrollBarThickness = 6
	controlList.ScrollBarImageColor3 = Sci.Cyan
	controlList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	controlList.CanvasSize = UDim2.new()
	controlList.Parent = controls
	local controlLayout = Instance.new("UIListLayout")
	controlLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlLayout.Padding = UDim.new(0, 6)
	controlLayout.Parent = controlList
	local function showDevice(device: string)
		for name, button in deviceButtons do
			local active = name == device
			button.BackgroundColor3 = if active then Sci.Green else Sci.PanelLight
			button.TextColor3 = if active then Sci.Void else Sci.Dim
		end
		for _, child in controlList:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for order, entry in CONTROLS[device] do
			local row = UIHelpers.frame("Row", UDim2.new(1, -10, 0, 30), UDim2.new(), nil)
			row.BackgroundColor3 = Sci.PanelLight
			row.BackgroundTransparency = if order % 2 == 0 then 1 else 0.4
			row.LayoutOrder = order
			UIHelpers.corner(row, UDim.new(0, 6))
			row.Parent = controlList
			local action = UIHelpers.label("Action", entry.action, 14, BODY_FONT)
			action.Position = UDim2.fromOffset(10, 0)
			action.Size = UDim2.new(0.62, -10, 1, 0)
			action.TextXAlignment = Enum.TextXAlignment.Left
			action.TextColor3 = Sci.Text
			action.Parent = row
			-- The key, in a small glowing key cap.
			local key = UIHelpers.label("Key", entry.keys, 11, SCI_FONT)
			key.AnchorPoint = Vector2.new(1, 0.5)
			key.Position = UDim2.new(1, -6, 0.5, 0)
			key.Size = UDim2.new(0.38, -6, 0, 22)
			key.BackgroundColor3 = Sci.Inset
			key.BackgroundTransparency = 0
			key.TextColor3 = Sci.Cyan
			UIHelpers.corner(key, UDim.new(0, 6))
			UIHelpers.stroke(key, Sci.Cyan, 1).Transparency = 0.4
			key.Parent = row
		end
	end
	for index, device in DEVICES do
		local button = Instance.new("TextButton")
		button.Name = device
		button.Position = UDim2.fromOffset(24 + (index - 1) * 170, 4)
		button.Size = UDim2.fromOffset(160, 32)
		button.AutoButtonColor = false
		button.Font = SCI_FONT
		button.TextSize = 11
		button.Text = string.upper(device)
		UIHelpers.corner(button, UDim.new(0, 8))
		button.Parent = controls
		button.Activated:Connect(function()
			showDevice(device)
		end)
		deviceButtons[device] = button
	end
	-- Each time the window opens, the controls show your current device.
	showControlsForDevice = function()
		showDevice(currentDevice())
	end
	showDevice(currentDevice())
	selectTab("GENERAL")

	local list = UIHelpers.frame("Rows", UDim2.new(1, -48, 0, 226), UDim2.fromOffset(24, 6), nil)
	list.BackgroundTransparency = 1
	list.Parent = general
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = list

	table.insert(rows, makeRow(list, 1, "volume", "SOUND", function(number: number): string
		return `{math.floor(number * 100 + 0.5)}%`
	end))
	table.insert(rows, makeRow(list, 2, "sensitivity", "MOUSE SENSITIVITY", function(number: number): string
		return string.format("%.2fx", number)
	end))
	table.insert(rows, makeRow(list, 3, "fieldOfView", "FIELD OF VIEW", function(number: number): string
		return `{math.floor(number + 0.5)} deg`
	end))

	local reset = Instance.new("TextButton")
	reset.Name = "Reset"
	reset.AnchorPoint = Vector2.new(0.5, 1)
	reset.Position = UDim2.new(0.5, 0, 1, -18)
	reset.Size = UDim2.fromOffset(220, 44)
	reset.Parent = general
	reset.BackgroundColor3 = Sci.PanelLight
	reset.AutoButtonColor = false
	reset.Font = SCI_FONT
	reset.TextSize = 14
	reset.TextColor3 = Sci.Cyan
	reset.Text = "RESET TO DEFAULT"
	UIHelpers.corner(reset, UDim.new(0, 10))
	UIHelpers.stroke(reset, Sci.Cyan, 1.5)
	reset.Activated:Connect(function()
		current.volume = Schema.SETTINGS.volume.default
		current.sensitivity = Schema.SETTINGS.sensitivity.default
		current.fieldOfView = Schema.SETTINGS.fieldOfView.default
		refreshRows()
		apply()
		saveSoon()
	end)
	refreshRows()
end

function SettingsController.open()
	SettingsController.start()
	if isOpen then
		return
	end
	isOpen = true
	refreshRows()
	showControlsForDevice()
	gui.Enabled = true
end

function SettingsController.close()
	if not started or not isOpen then
		return
	end
	isOpen = false
	gui.Enabled = false
end

function SettingsController.toggle()
	if isOpen then
		SettingsController.close()
	else
		SettingsController.open()
	end
end

function SettingsController.start()
	if started then
		return
	end
	started = true
	build()

	-- The saved values from the server (when your data loads, and after saves).
	local function readSaved()
		for key, attribute in { volume = ATTR.SettingVolume, sensitivity = ATTR.SettingSensitivity, fieldOfView = ATTR.SettingFieldOfView } do
			local saved = player:GetAttribute(attribute)
			if typeof(saved) == "number" then
				(current :: any)[key] = Schema.cleanSetting(key, saved)
			end
		end
		refreshRows()
		apply()
	end
	for _, attribute in { ATTR.SettingVolume, ATTR.SettingSensitivity, ATTR.SettingFieldOfView } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if saveToken == 0 or not isOpen then -- don't jump while you're dragging
				readSaved()
			end
		end)
	end
	readSaved()
end

return SettingsController

--!strict
--[[
	FreeForAllController: your screen while you're in the drop-in FREE FOR
	ALL arena (server: FreeForAllService).

	  * Top: the time left in the round, your eliminations, the leader and
	    the target ("first to 20").
	  * Top right: LEAVE (or press L) takes you back to the lobby.
	Shown while your Player has the "FreeForAll" attribute.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"):WaitForChild("Net"))
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIHelpers = require(UIFolder:WaitForChild("UIHelpers"))
local ResponsiveScale = require(UIFolder:WaitForChild("ResponsiveScale"))

local player = Players.LocalPlayer
local Sci = Theme.SciFi
local SCI_FONT = Theme.SciFiFonts.Title
local BODY_FONT = Theme.SciFiFonts.Body

local FreeForAllController = {}
local started = false

function FreeForAllController.start()
	if started then
		return
	end
	started = true
	local state = ReplicatedStorage:WaitForChild("FreeForAllState", 30)

	local gui = UIHelpers.screenGui("FreeForAll", 4, player:WaitForChild("PlayerGui"))
	gui.Enabled = false
	ResponsiveScale.apply(gui)

	local panel = UIHelpers.frame("Top", UDim2.fromOffset(460, 74), UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0))
	panel.BackgroundColor3 = Sci.Panel
	panel.BackgroundTransparency = 0.1
	UIHelpers.corner(panel, UDim.new(0, 14))
	UIHelpers.stroke(panel, Color3.fromRGB(255, 80, 120), 2).Transparency = 0.1
	panel.Parent = gui
	local timer = UIHelpers.label("Timer", "5:00", 24, SCI_FONT)
	timer.Position = UDim2.fromOffset(0, 6)
	timer.Size = UDim2.new(1, 0, 0, 30)
	timer.TextColor3 = Sci.Text
	timer.Parent = panel
	local line = UIHelpers.label("Scores", "", 15, BODY_FONT)
	line.Position = UDim2.fromOffset(0, 40)
	line.Size = UDim2.new(1, 0, 0, 24)
	line.RichText = true
	line.TextColor3 = Sci.Dim
	line.Parent = panel

	local leave = Instance.new("TextButton")
	leave.Name = "Leave"
	leave.AnchorPoint = Vector2.new(1, 0)
	leave.Position = UDim2.new(1, -16, 0, 14)
	leave.Size = UDim2.fromOffset(170, 44)
	leave.BackgroundColor3 = Sci.Panel
	leave.BackgroundTransparency = 0.1
	leave.AutoButtonColor = false
	leave.Font = SCI_FONT
	leave.TextSize = 13
	leave.TextColor3 = Sci.Red
	leave.Text = "LEAVE  (L)"
	UIHelpers.corner(leave, UDim.new(0, 10))
	UIHelpers.stroke(leave, Sci.Red, 2)
	leave.Parent = gui
	local function requestLeave()
		Net.event("FreeForAllLeave"):FireServer()
	end
	leave.Activated:Connect(requestLeave)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.L and player:GetAttribute("FreeForAll") == true then
			requestLeave()
		end
	end)

	local function read(name: string): any
		return if state then state:GetAttribute(name) else nil
	end

	task.spawn(function()
		while gui.Parent do
			local inside = player:GetAttribute("FreeForAll") == true
			gui.Enabled = inside
			if inside then
				local endsAt = read("RoundEndsAt")
				local left = if typeof(endsAt) == "number" and endsAt > 0 then endsAt - Workspace:GetServerTimeNow() else 0
				timer.Text = if left > 0 then UIHelpers.formatTime(left) else "NEXT ROUND..."
				local mine = player:GetAttribute("FfaEliminations")
				local leader = read("LeaderName")
				local target = read("Target")
				local leaderText = if typeof(leader) == "string" and leader ~= ""
					then `  ·  LEADER <font color="#FFD65A">{leader} {read("LeaderScore") or 0}</font>`
					else ""
				line.Text = `YOU <font color="#E4ECFF">{if typeof(mine) == "number" then mine else 0}</font>{leaderText}  ·  FIRST TO {if typeof(target) == "number" then target else 20}`
			end
			task.wait(0.2)
		end
	end)
end

return FreeForAllController

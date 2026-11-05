--!strict
--[[
	PracticeController: your screen while you're at the practice range.

	  * A banner at the top ("PRACTICE RANGE · pop the targets!") and a
	    LEAVE RANGE button (key L, or walk onto the BACK TO LOBBY pad).
	  * When anyone pops a target, a puff of jelly sparkles where it was
	    (ToppingEffects, the same burst as the default Slime Splat).

	The server (PracticeService) decides everything; leaving just asks.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"):WaitForChild("Net"))
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIHelpers = require(UIFolder:WaitForChild("UIHelpers"))
local ResponsiveScale = require(UIFolder:WaitForChild("ResponsiveScale"))
local ToppingEffects = require(script.Parent.Parent:WaitForChild("Effects"):WaitForChild("ToppingEffects"))

local Colors = Theme.Colors
local player = Players.LocalPlayer

local PracticeController = {}
local started = false

function PracticeController.start()
	if started then
		return
	end
	started = true

	local gui = UIHelpers.screenGui("Practice", 4, player:WaitForChild("PlayerGui"))
	ResponsiveScale.apply(gui)
	gui.Enabled = false

	local banner = UIHelpers.label("Banner", "🎯 PRACTICE RANGE · pop the targets!", 26, Theme.Fonts.Title)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 12)
	banner.Size = UDim2.fromOffset(620, 40)
	banner.TextColor3 = Colors.White
	UIHelpers.textStroke(banner, 2)
	banner.Parent = gui

	local leave = Instance.new("TextButton")
	leave.Name = "Leave"
	leave.AnchorPoint = Vector2.new(1, 0)
	leave.Position = UDim2.new(1, -16, 0, 60)
	leave.Size = UDim2.fromOffset(190, 50)
	leave.BackgroundColor3 = Colors.Coral
	leave.Font = Theme.Fonts.Title
	leave.TextSize = 22
	leave.TextColor3 = Colors.White
	leave.Text = "LEAVE RANGE (L)"
	-- (No Modal here: it would free the mouse the whole time and stop you aiming.
	-- On a computer press L; on phones and tablets just tap it.)
	UIHelpers.corner(leave, UDim.new(0, 12))
	UIHelpers.stroke(leave, Colors.Ink, 3)
	UIHelpers.textStroke(leave)
	leave.Parent = gui
	leave.Activated:Connect(function()
		Net.event("PracticeLeave"):FireServer()
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.L and player:GetAttribute("MatchStatus") == "Practice" then
			Net.event("PracticeLeave"):FireServer()
		end
	end)

	local function refresh()
		gui.Enabled = player:GetAttribute("MatchStatus") == "Practice"
	end
	player:GetAttributeChangedSignal("MatchStatus"):Connect(refresh)
	refresh()

	Net.event("TargetPop").OnClientEvent:Connect(function(position: unknown, color: unknown)
		if typeof(position) == "Vector3" then
			local lowQuality = player:GetAttribute("GraphicsQuality") == "Low"
			ToppingEffects.play(position, nil, if typeof(color) == "Color3" then color else Colors.Coral, lowQuality)
		end
	end)
end

return PracticeController

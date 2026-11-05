--!strict
--[[
	UIController
	============
	The starting point for all UI. Runs once on each player's device:
	  1. Hides Roblox's built-in health bar and player list (we have our own).
	  2. Builds the main menu, HUD, kill feed and scoreboard.
	  3. Shows the menu first; the HUD appears after pressing Play.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local UIFolder = script.Parent
local ResponsiveScale = require(UIFolder:WaitForChild("ResponsiveScale"))
local UIHelpers = require(UIFolder:WaitForChild("UIHelpers"))
local Hud = require(UIFolder:WaitForChild("Hud"))
local KillFeed = require(UIFolder:WaitForChild("KillFeed"))
local Scoreboard = require(UIFolder:WaitForChild("Scoreboard"))
local MainMenu = require(UIFolder:WaitForChild("MainMenu"))

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- SetCoreGuiEnabled can fail if called too early, so try a few times.
local function hideCoreGui(coreGuiType: Enum.CoreGuiType)
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(coreGuiType, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end
task.spawn(hideCoreGui, Enum.CoreGuiType.Health)
task.spawn(hideCoreGui, Enum.CoreGuiType.PlayerList)

-- Separate ScreenGuis so each can be shown or hidden on its own.
-- Higher DisplayOrder draws on top.
local hudGui = UIHelpers.screenGui("HUD", 1, playerGui)
local scoreboardGui = UIHelpers.screenGui("Scoreboard", 5, playerGui)
local menuGui = UIHelpers.screenGui("MainMenu", 10, playerGui)

for _, gui in { hudGui, scoreboardGui, menuGui } do
	ResponsiveScale.apply(gui)
end

Hud.create(hudGui)
KillFeed.create(hudGui)
Scoreboard.create(scoreboardGui)

-- Start on the menu with the HUD hidden.
hudGui.Enabled = false
scoreboardGui.Enabled = false

MainMenu.create(menuGui, function()
	hudGui.Enabled = true
	scoreboardGui.Enabled = true
end)

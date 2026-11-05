--!strict
--[[
	GraphicsController: picks Low / Medium / High graphics automatically from
	the player's own Roblox graphics setting (Esc menu -> Graphics Quality),
	and updates live when they change it.

	  Low     no bloom or sun rays; blob jiggle only up close; small bursts
	  Medium  bloom on, no sun rays (default, also used for "Automatic")
	  High    everything on

	Only cosmetic effects change. Nothing that matters for playing (enemy
	visibility, hit areas, UI) is ever reduced. Other scripts read the
	choice from the player's "GraphicsQuality" attribute (this device only).
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local GraphicsController = {}
local started = false

local function currentQuality(): string
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if not ok or level == Enum.SavedQualitySetting.Automatic then
		return "Medium"
	end
	local number = tonumber(string.match(tostring(level), "%d+")) or 5
	return if number <= 3 then "Low" elseif number <= 7 then "Medium" else "High"
end

local function apply()
	local quality = currentQuality()
	Players.LocalPlayer:SetAttribute("GraphicsQuality", quality)
	-- These changes only affect this player's screen.
	for _, effect in Lighting:GetChildren() do
		if effect:IsA("BloomEffect") then
			effect.Enabled = quality ~= "Low"
		elseif effect:IsA("SunRaysEffect") then
			effect.Enabled = quality == "High"
		end
	end
end

function GraphicsController.start()
	if started then
		return
	end
	started = true
	apply()
	pcall(function()
		UserSettings():GetService("UserGameSettings"):GetPropertyChangedSignal("SavedQualityLevel"):Connect(apply)
	end)
end

return GraphicsController

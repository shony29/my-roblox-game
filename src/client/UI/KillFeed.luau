--!strict
--[[
	KillFeed
	========
	A small list in the top right corner: "PlayerA eliminated PlayerB".
	New lines slide in at the top and fade out after a few seconds.
	Lines that involve you get a yellow outline.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIHelpers = require(script.Parent:WaitForChild("UIHelpers"))
local GameContract = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("GameContract"))

local Colors = Theme.Colors
local MAX_ENTRIES = 5
local ENTRY_LIFETIME = 5 -- seconds
local ENTRY_HEIGHT = 30
local MAX_NAME_LENGTH = 20

local KillFeed = {}

-- Escapes characters that have special meaning in RichText.
local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

local function cleanName(value: unknown): string?
	if typeof(value) ~= "string" then
		return nil
	end
	if #value > MAX_NAME_LENGTH then
		return value:sub(1, MAX_NAME_LENGTH) .. "…"
	end
	return value
end

local function colorHex(color: Color3): string
	return "#" .. color:ToHex()
end

function KillFeed.create(gui: ScreenGui)
	local localName = Players.LocalPlayer.DisplayName

	local list = Instance.new("Frame")
	list.Name = "KillFeed"
	list.AnchorPoint = Vector2.new(1, 0)
	list.Position = UDim2.new(1, -Theme.Margin, 0, 14)
	list.Size = UDim2.fromOffset(340, (ENTRY_HEIGHT + 6) * MAX_ENTRIES)
	list.BackgroundTransparency = 1
	list.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	local order = 0

	local function addEntry(killerName: string?, victimName: string)
		order -= 1 -- newest entries get the smallest number, so they sit on top

		local involvesMe = killerName == localName or victimName == localName
		local text
		if killerName then
			text = string.format(
				'<font color="%s">%s</font> eliminated <font color="%s">%s</font>',
				colorHex(Colors.Yolk),
				escape(killerName),
				colorHex(Colors.Sky),
				escape(victimName)
			)
		else
			text = string.format('<font color="%s">%s</font> was eliminated', colorHex(Colors.Sky), escape(victimName))
		end

		local entry = UIHelpers.frame("Entry", UDim2.fromOffset(0, ENTRY_HEIGHT), UDim2.new())
		entry.AutomaticSize = Enum.AutomaticSize.X
		entry.LayoutOrder = order
		UIHelpers.corner(entry, UDim.new(0, 8))
		local outline = UIHelpers.stroke(entry, if involvesMe then Colors.Yolk else Colors.Ink, 2)

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.Parent = entry

		local label = UIHelpers.label("Text", text, 16)
		label.RichText = true
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromScale(0, 1)
		label.TextColor3 = Colors.Shell
		label.Parent = entry

		entry.Parent = list

		-- Keep only the newest few lines.
		local entries = {}
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				table.insert(entries, child)
			end
		end
		table.sort(entries, function(a: Frame, b: Frame)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = MAX_ENTRIES + 1, #entries do
			entries[i]:Destroy()
		end

		-- Fade out, then remove.
		task.delay(ENTRY_LIFETIME, function()
			if entry.Parent == nil then
				return
			end
			UIHelpers.tween(entry, 0.4, { BackgroundTransparency = 1 })
			UIHelpers.tween(label, 0.4, { TextTransparency = 1 })
			UIHelpers.tween(outline, 0.4, { Transparency = 1 })
			task.delay(0.45, function()
				entry:Destroy()
			end)
		end)
	end

	local remote = GameContract.getRemote(GameContract.RemoteNames.KillFeed)
	remote.OnClientEvent:Connect(function(killer: unknown, victim: unknown)
		local victimName = cleanName(victim)
		if victimName == nil then
			return
		end
		addEntry(cleanName(killer), victimName)
	end)
end

return KillFeed

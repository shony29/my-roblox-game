--!strict
--[[
	UIHelpers
	=========
	Small building blocks so the screen modules stay short and readable.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))

local UIHelpers = {}

function UIHelpers.corner(parent: GuiObject, radius: UDim?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or Theme.CornerRadius
	c.Parent = parent
	return c
end

function UIHelpers.stroke(parent: GuiObject, color: Color3?, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Theme.Colors.Ink
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- A text outline (helps text stay readable over bright scenery).
function UIHelpers.textStroke(label: TextLabel | TextButton, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = Theme.Colors.Ink
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = label
end

function UIHelpers.padding(parent: GuiObject, pixels: number)
	local p = Instance.new("UIPadding")
	local u = UDim.new(0, pixels)
	p.PaddingTop = u
	p.PaddingBottom = u
	p.PaddingLeft = u
	p.PaddingRight = u
	p.Parent = parent
end

function UIHelpers.frame(name: string, size: UDim2, position: UDim2, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.AnchorPoint = anchor or Vector2.zero
	f.BackgroundColor3 = Theme.Colors.Panel
	f.BackgroundTransparency = Theme.PanelTransparency
	f.BorderSizePixel = 0
	return f
end

function UIHelpers.label(name: string, text: string, textSize: number, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Text = text
	l.TextSize = textSize
	l.Font = font or Theme.Fonts.Body
	l.TextColor3 = Theme.Colors.White
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Size = UDim2.fromScale(1, 1)
	return l
end

function UIHelpers.tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?): Tween
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end

-- Makes a ScreenGui with the usual settings.
function UIHelpers.screenGui(name: string, displayOrder: number, parent: Instance): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false -- keep the UI when the character respawns
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder
	gui.Parent = parent
	return gui
end

-- Turns 125 into "2:05".
-- True when Roblox's graphics quality is on Automatic or turned down, which
-- makes 3D pictures (the shop) and the world look blocky and jagged.
function UIHelpers.graphicsAreLow(): boolean
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if not ok then
		return false
	end
	if level == Enum.SavedQualitySetting.Automatic then
		return true
	end
	return (tonumber(string.match(tostring(level), "%d+")) or 10) < 8
end

--[[
	A small yellow tip that tells players how to get smoother graphics. It
	only shows while their graphics quality is low (and hides itself as soon
	as they turn it up). The game can't change this setting for them.
]]
function UIHelpers.qualityTip(parent: Instance, position: UDim2, anchor: Vector2, width: number): TextLabel
	local tip = Instance.new("TextLabel")
	tip.Name = "QualityTip"
	tip.AnchorPoint = anchor
	tip.Position = position
	tip.Size = UDim2.fromOffset(width, 36)
	tip.BackgroundTransparency = 1
	tip.Font = Enum.Font.GothamBold
	tip.TextSize = 14
	tip.TextWrapped = true
	tip.TextColor3 = Color3.fromRGB(255, 214, 90)
	tip.Text = "⚠ For smoother graphics: press Esc → Settings → turn Graphics Quality up"
	tip.Parent = parent
	local function update()
		tip.Visible = UIHelpers.graphicsAreLow()
	end
	pcall(function()
		UserSettings():GetService("UserGameSettings"):GetPropertyChangedSignal("SavedQualityLevel"):Connect(update)
	end)
	update()
	return tip
end

function UIHelpers.formatTime(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- Reads a number attribute, using 0 when it's missing.
function UIHelpers.numberAttribute(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

return UIHelpers

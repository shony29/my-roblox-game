--!strict
--[[
	Hud: the weapon display on screen.
	  - Hitmarker: a small "X" that pops up where you aimed when a hit is confirmed.
	    White = normal hit, orange = headshot, red = kill.
	  - A "Reloading..." message in the bottom-right corner. (The ammo number
	    itself is shown by the game's main HUD, which reads the Ammo and
	    MaxAmmo attributes the server puts on your character.)
	  - Three slots (1, 2, 3) at the bottom, with the held weapon lit up.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Weapons"):WaitForChild("WeaponConfig"))

local COLOR_HIT = Color3.fromRGB(255, 255, 255)
local COLOR_HEADSHOT = Color3.fromRGB(255, 190, 60)
local COLOR_KILL = Color3.fromRGB(255, 70, 70)
local COLOR_SLOT = Color3.fromRGB(30, 30, 40)
local COLOR_SLOT_ACTIVE = Color3.fromRGB(255, 205, 60)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "WeaponHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local function addCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

-- Hitmarker: four short bars arranged as an X around the aim point.
local hitmarker = Instance.new("Frame")
hitmarker.Name = "Hitmarker"
hitmarker.AnchorPoint = Vector2.new(0.5, 0.5)
hitmarker.Size = UDim2.fromOffset(34, 34)
hitmarker.BackgroundTransparency = 1
hitmarker.Visible = false
hitmarker.Parent = gui

local hitmarkerBars: { Frame } = {}
for i = 0, 3 do
	local angle = 45 + i * 90
	local rad = math.rad(angle)
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Size = UDim2.fromOffset(10, 3)
	bar.Position = UDim2.new(0.5, math.cos(rad) * 10, 0.5, math.sin(rad) * 10)
	bar.Rotation = angle
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = COLOR_HIT
	bar.Parent = hitmarker
	table.insert(hitmarkerBars, bar)
end
local hitmarkerScale = Instance.new("UIScale")
hitmarkerScale.Parent = hitmarker

-- Reload message.
local ammoLabel = Instance.new("TextLabel")
ammoLabel.Name = "Ammo"
ammoLabel.AnchorPoint = Vector2.new(1, 1)
ammoLabel.Position = UDim2.new(1, -24, 1, -24)
ammoLabel.Size = UDim2.fromOffset(260, 60)
ammoLabel.BackgroundTransparency = 1
ammoLabel.Font = Enum.Font.FredokaOne
ammoLabel.TextSize = 34
ammoLabel.TextXAlignment = Enum.TextXAlignment.Right
ammoLabel.TextColor3 = Color3.new(1, 1, 1)
ammoLabel.TextStrokeTransparency = 0.5
ammoLabel.Text = ""
ammoLabel.Parent = gui

-- Weapon slots 1, 2, 3.
local slotBar = Instance.new("Frame")
slotBar.Name = "Slots"
slotBar.AnchorPoint = Vector2.new(0.5, 1)
slotBar.Position = UDim2.new(0.5, 0, 1, -20)
slotBar.Size = UDim2.fromOffset(3 * 130 + 2 * 8, 44)
slotBar.BackgroundTransparency = 1
slotBar.Parent = gui

local slotLayout = Instance.new("UIListLayout")
slotLayout.FillDirection = Enum.FillDirection.Horizontal
slotLayout.Padding = UDim.new(0, 8)
slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
slotLayout.Parent = slotBar

local slotFrames: { [string]: TextLabel } = {}
for index, weaponId in WeaponConfig.Order do
	local stats = WeaponConfig.get(weaponId)
	local slot = Instance.new("TextLabel")
	slot.Name = weaponId
	slot.LayoutOrder = index
	slot.Size = UDim2.fromOffset(130, 44)
	slot.BackgroundColor3 = COLOR_SLOT
	slot.BackgroundTransparency = 0.35
	slot.Font = Enum.Font.FredokaOne
	slot.TextSize = 18
	slot.TextColor3 = Color3.new(1, 1, 1)
	slot.Text = `{index}  {if stats then stats.DisplayName else weaponId}`
	slot.Parent = slotBar
	addCorner(slot, 10)
	slotFrames[weaponId] = slot
end

local hitmarkerTweens: { Tween } = {}

local Hud = {}

function Hud.setAmmo(weaponId: string, ammo: number, reloading: boolean)
	local stats = WeaponConfig.get(weaponId)
	if not stats then
		return
	end
	if reloading then
		ammoLabel.Text = "Reloading..."
		ammoLabel.TextColor3 = Color3.new(1, 1, 1)
	elseif ammo == 0 then
		ammoLabel.Text = "Press R to reload"
		ammoLabel.TextColor3 = COLOR_KILL
	else
		ammoLabel.Text = ""
	end
end

function Hud.setEquipped(weaponId: string)
	for id, slot in slotFrames do
		local active = id == weaponId
		slot.BackgroundColor3 = if active then COLOR_SLOT_ACTIVE else COLOR_SLOT
		slot.TextColor3 = if active then Color3.fromRGB(30, 30, 40) else Color3.new(1, 1, 1)
		slot.BackgroundTransparency = if active then 0.05 else 0.35
	end
end

-- Pops the hitmarker at a screen position (in pixels).
function Hud.showHitmarker(screenPosition: Vector2, killed: boolean, headshot: boolean)
	local color = if killed then COLOR_KILL elseif headshot then COLOR_HEADSHOT else COLOR_HIT
	for _, bar in hitmarkerBars do
		bar.BackgroundColor3 = color
		bar.BackgroundTransparency = 0
	end
	hitmarker.Position = UDim2.fromOffset(screenPosition.X, screenPosition.Y)
	hitmarker.Visible = true
	hitmarkerScale.Scale = if killed then 1.6 else 1.3

	-- Stop the previous pop so quick hits restart the animation cleanly.
	for _, old in hitmarkerTweens do
		old:Cancel()
	end
	table.clear(hitmarkerTweens)

	local pop = TweenService:Create(hitmarkerScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	table.insert(hitmarkerTweens, pop)
	pop:Play()

	local fadeInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.12)
	for _, bar in hitmarkerBars do
		local fade = TweenService:Create(bar, fadeInfo, { BackgroundTransparency = 1 })
		table.insert(hitmarkerTweens, fade)
		fade:Play()
	end
end

return Hud

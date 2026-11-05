--!strict
--[[
	Hud
	===
	The in-game heads-up display:
	  * Health bar (bottom left)  - reads the character's Humanoid
	  * Ammo counter (bottom right) - reads Ammo / MaxAmmo attributes
	  * Crosshair (center)
	  * Round timer (top center) - reads the RoundEndsAt attribute
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIHelpers = require(script.Parent:WaitForChild("UIHelpers"))
local GameContract = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("GameContract"))

local player = Players.LocalPlayer
local Colors = Theme.Colors
local M = Theme.Margin

local LOW_AMMO_FRACTION = 0.25
local TIMER_WARNING_SECONDS = 10
local UPDATE_INTERVAL = 0.1 -- seconds between ammo/timer refreshes

local Hud = {}

-- Health ------------------------------------------------------------------

local function healthColor(fraction: number): Color3
	if fraction > 0.5 then
		return Colors.Mint
	elseif fraction > 0.25 then
		return Colors.Yolk
	end
	return Colors.Coral
end

local function buildHealthBar(parent: Instance): (number, number) -> ()
	local container = UIHelpers.frame("Health", UDim2.fromOffset(300, 44), UDim2.new(0, M, 1, -M), Vector2.new(0, 1))
	UIHelpers.corner(container, UDim.new(1, 0))
	UIHelpers.stroke(container, Colors.Ink, 3)
	container.Parent = parent

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 52, 0.5, 0)
	track.Size = UDim2.new(1, -64, 0, 20)
	track.BackgroundColor3 = Colors.Ink
	track.BorderSizePixel = 0
	UIHelpers.corner(track, UDim.new(1, 0))
	track.Parent = container

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Colors.Mint
	fill.BorderSizePixel = 0
	UIHelpers.corner(fill, UDim.new(1, 0))
	fill.Parent = track

	local number = UIHelpers.label("Value", "100", 20, Theme.Fonts.Title)
	number.AnchorPoint = Vector2.new(0, 0.5)
	number.Position = UDim2.new(0, 8, 0.5, 0)
	number.Size = UDim2.fromOffset(40, 30)
	UIHelpers.textStroke(number)
	number.Parent = container

	return function(health: number, maxHealth: number)
		local fraction = if maxHealth > 0 then math.clamp(health / maxHealth, 0, 1) else 0
		number.Text = tostring(math.ceil(math.max(health, 0)))
		UIHelpers.tween(fill, 0.2, {
			Size = UDim2.fromScale(fraction, 1),
			BackgroundColor3 = healthColor(fraction),
		})
		-- Fully hide the fill at 0 so the rounded corners don't leave a dot
		fill.Visible = fraction > 0
	end
end

-- Ammo --------------------------------------------------------------------

local function buildAmmo(parent: Instance): (number?, number?) -> ()
	local container = UIHelpers.frame("Ammo", UDim2.fromOffset(190, 70), UDim2.new(1, -M, 1, -M), Vector2.new(1, 1))
	UIHelpers.corner(container)
	UIHelpers.stroke(container, Colors.Ink, 3)
	container.Parent = parent

	-- On phones, lift the ammo counter above the jump button.
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		container.Position = UDim2.new(1, -M, 1, -190)
	end

	local current = UIHelpers.label("Current", "--", 44, Theme.Fonts.Title)
	current.TextXAlignment = Enum.TextXAlignment.Right
	current.Size = UDim2.new(0.55, 0, 1, 0)
	current.TextColor3 = Colors.Yolk
	UIHelpers.textStroke(current)
	current.Parent = container

	local max = UIHelpers.label("Max", "/ --", 22, Theme.Fonts.Title)
	max.TextXAlignment = Enum.TextXAlignment.Left
	max.Position = UDim2.new(0.58, 0, 0, 6)
	max.Size = UDim2.new(0.42, 0, 1, 0)
	max.TextColor3 = Colors.Shell
	max.Parent = container

	local lastText = ""
	return function(ammo: number?, maxAmmo: number?)
		container.Visible = ammo ~= nil
		if ammo == nil then
			return
		end
		local text = tostring(math.floor(ammo)) .. "|" .. tostring(maxAmmo)
		if text == lastText then
			return
		end
		lastText = text
		current.Text = tostring(math.floor(ammo))
		max.Text = if maxAmmo then "/ " .. tostring(math.floor(maxAmmo)) else ""
		local low = maxAmmo ~= nil and maxAmmo > 0 and ammo / maxAmmo <= LOW_AMMO_FRACTION
		current.TextColor3 = if low then Colors.Coral else Colors.Yolk
	end
end

-- Looks for Ammo on the equipped Tool first, then on the character.
local function readAmmo(character: Model?): (number?, number?)
	if character == nil then
		return nil, nil
	end
	local sources: { Instance } = {}
	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		table.insert(sources, tool)
	end
	table.insert(sources, character)

	for _, source in sources do
		local ammo = source:GetAttribute(GameContract.WeaponAttributes.Ammo)
		if typeof(ammo) == "number" then
			local maxAmmo = source:GetAttribute(GameContract.WeaponAttributes.MaxAmmo)
			return ammo, if typeof(maxAmmo) == "number" then maxAmmo else nil
		end
	end
	return nil, nil
end

-- Crosshair ---------------------------------------------------------------

local function buildCrosshair(parent: Instance)
	local holder = Instance.new("Frame")
	holder.Name = "Crosshair"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(36, 36)
	holder.BackgroundTransparency = 1
	holder.Parent = parent

	local function piece(name: string, size: UDim2, position: UDim2)
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = size
		f.Position = position
		f.BackgroundColor3 = Colors.White
		f.BorderSizePixel = 0
		UIHelpers.corner(f, UDim.new(1, 0))
		UIHelpers.stroke(f, Colors.Ink, 1.5)
		f.Parent = holder
	end

	-- A dot in the middle and four short lines with a gap around it.
	piece("Dot", UDim2.fromOffset(5, 5), UDim2.fromScale(0.5, 0.5))
	piece("Top", UDim2.fromOffset(3, 10), UDim2.new(0.5, 0, 0.5, -12))
	piece("Bottom", UDim2.fromOffset(3, 10), UDim2.new(0.5, 0, 0.5, 12))
	piece("Left", UDim2.fromOffset(10, 3), UDim2.new(0.5, -12, 0.5, 0))
	piece("Right", UDim2.fromOffset(10, 3), UDim2.new(0.5, 12, 0.5, 0))
end

-- Round timer -------------------------------------------------------------

local function buildTimer(parent: Instance): (number?) -> ()
	local container = UIHelpers.frame("RoundTimer", UDim2.fromOffset(150, 52), UDim2.new(0.5, 0, 0, 14), Vector2.new(0.5, 0))
	UIHelpers.corner(container, UDim.new(1, 0))
	UIHelpers.stroke(container, Colors.Ink, 3)
	container.Parent = parent

	local text = UIHelpers.label("Time", "0:00", 32, Theme.Fonts.Title)
	UIHelpers.textStroke(text)
	text.Parent = container

	local lastShown = ""
	return function(secondsLeft: number?)
		container.Visible = secondsLeft ~= nil
		if secondsLeft == nil then
			return
		end
		local shown = UIHelpers.formatTime(secondsLeft)
		if shown == lastShown then
			return
		end
		lastShown = shown
		text.Text = shown
		local warning = secondsLeft <= TIMER_WARNING_SECONDS
		text.TextColor3 = if warning then Colors.Coral else Colors.White
		if warning and secondsLeft > 0 then
			-- A small "pop" each second near the end of the round.
			text.TextSize = 40
			UIHelpers.tween(text, 0.3, { TextSize = 32 }, Enum.EasingStyle.Back)
		end
	end
end

-- Putting it together -----------------------------------------------------

function Hud.create(gui: ScreenGui)
	local setHealth = buildHealthBar(gui)
	local setAmmo = buildAmmo(gui)
	local setTimer = buildTimer(gui)
	buildCrosshair(gui)

	-- Health follows whichever character the player currently has.
	local healthConnection: RBXScriptConnection? = nil
	local function onCharacter(character: Model)
		if healthConnection then
			healthConnection:Disconnect()
			healthConnection = nil
		end
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid == nil or not humanoid:IsA("Humanoid") then
			return
		end
		local h = humanoid :: Humanoid
		setHealth(h.Health, h.MaxHealth)
		healthConnection = h.HealthChanged:Connect(function(health: number)
			setHealth(health, h.MaxHealth)
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	-- Ammo and timer are cheap to check, so refresh them a few times a second.
	task.spawn(function()
		while gui.Parent do
			if gui.Enabled then
				setAmmo(readAmmo(player.Character))
				setTimer(GameContract.getRoundTimeRemaining())
			end
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

return Hud

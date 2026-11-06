--!strict
--[[
	DashIndicator
	=============
	A small round sci-fi badge at the bottom of the screen that says "DASH"
	(bottom right in the lobby).
	After you dash it empties, then fills back up from the bottom while
	the cooldown runs, showing the seconds left. When it's full it gives
	a tiny "pop" so you know the dash is ready again.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

export type DashIndicator = {
	-- progress: 0 = just used, 1 = ready. secondsLeft: time until ready.
	update: (progress: number, secondsLeft: number) -> (),
	destroy: () -> (),
}

local Theme = require(script.Parent:WaitForChild("Theme"))
local Sci = Theme.SciFi

local READY_COLOR = Sci.Cyan
local FILL_COLOR = Sci.Cyan
local BACKGROUND_COLOR = Sci.Void
local SIZE = 64

local DashIndicator = {}

local function round(frame: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0) -- fully round
	corner.Parent = frame
end

function DashIndicator.new(parent: Instance): DashIndicator
	local gui = Instance.new("ScreenGui")
	gui.Name = "MovementHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	-- A dark round badge. (Everything inside is round too: no square corners.)
	local badge = Instance.new("Frame")
	badge.Name = "DashBadge"
	badge.AnchorPoint = Vector2.new(0.5, 1)
	-- Above the weapon slot bar (Weapons/Hud.luau), which sits at the very bottom.
	badge.Position = UDim2.new(0.5, 0, 1, -76)
	badge.Size = UDim2.fromOffset(SIZE, SIZE)
	badge.BackgroundColor3 = BACKGROUND_COLOR
	badge.BackgroundTransparency = 0.2
	round(badge)
	badge.Parent = gui

	-- The cooldown fills the circle from the bottom up. A gradient does the
	-- cut-off, so the fill stays a perfect circle at every height.
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = FILL_COLOR
	fill.BackgroundTransparency = 0
	round(fill)
	fill.Parent = badge
	local cut = Instance.new("UIGradient")
	cut.Rotation = -90 -- 0 = bottom, 1 = top
	cut.Parent = fill

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.SciFiFonts.Title
	label.TextSize = 13
	label.TextColor3 = Sci.Text
	label.TextStrokeTransparency = 0.4
	label.Text = "DASH"
	label.ZIndex = 2
	label.Parent = badge

	-- The neon ring around the badge (it "pops" when the dash is ready).
	local ringHolder = Instance.new("Frame")
	ringHolder.Name = "Ring"
	ringHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	ringHolder.Position = UDim2.fromScale(0.5, 0.5)
	ringHolder.Size = UDim2.fromScale(1, 1)
	ringHolder.BackgroundTransparency = 1
	ringHolder.ZIndex = 3
	round(ringHolder)
	ringHolder.Parent = badge

	local ring = Instance.new("UIStroke")
	ring.Thickness = 3
	ring.Color = READY_COLOR
	ring.Parent = ringHolder

	gui.Parent = parent

	local wasReady = true

	local matchPosition = badge.Position
	local function setFill(amount: number)
		-- See-through above `amount`, filled below it (a sharp edge).
		local edge = math.clamp(amount, 0, 1)
		if edge <= 0 then
			cut.Transparency = NumberSequence.new(1)
		elseif edge >= 1 then
			cut.Transparency = NumberSequence.new(0.35)
		else
			cut.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(edge, 0.35),
				NumberSequenceKeypoint.new(math.min(edge + 0.001, 1), 1),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
	end

	local function update(progress: number, secondsLeft: number)
		-- In the lobby the bottom middle holds the PLAY button, so sit in the corner.
		local status = Players.LocalPlayer:GetAttribute("MatchStatus")
		local wanted = if status == "Lobby" or status == "Queued" then UDim2.new(1, -24, 1, -24) else matchPosition
		if badge.Position ~= wanted then
			badge.Position = wanted
			badge.AnchorPoint = if wanted == matchPosition then Vector2.new(0.5, 1) else Vector2.new(1, 1)
		end
		local clamped = math.clamp(progress, 0, 1)
		setFill(clamped)
		local ready = clamped >= 1

		if ready then
			label.Text = "DASH"
			ring.Transparency = 0
		else
			label.Text = string.format("%.1f", math.max(secondsLeft, 0))
			ring.Transparency = 0.6
		end

		-- A quick "pop" when the dash becomes ready.
		if ready and not wasReady then
			ringHolder.Size = UDim2.fromScale(1.2, 1.2)
			TweenService:Create(ringHolder, TweenInfo.new(0.2, Enum.EasingStyle.Back), {
				Size = UDim2.fromScale(1, 1),
			}):Play()
		end
		wasReady = ready
	end

	local function destroy()
		gui:Destroy()
	end

	return {
		update = update,
		destroy = destroy,
	}
end

return DashIndicator

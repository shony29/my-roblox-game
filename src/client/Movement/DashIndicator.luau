--!strict
--[[
	DashIndicator
	=============
	A small round badge at the bottom of the screen that says "DASH".
	After you dash it empties, then fills back up from the bottom while
	the cooldown runs, showing the seconds left. When it's full it gives
	a tiny "pop" so you know the dash is ready again.
]]

local TweenService = game:GetService("TweenService")

export type DashIndicator = {
	-- progress: 0 = just used, 1 = ready. secondsLeft: time until ready.
	update: (progress: number, secondsLeft: number) -> (),
	destroy: () -> (),
}

local READY_COLOR = Color3.fromRGB(255, 255, 255)
local FILL_COLOR = Color3.fromRGB(120, 230, 255)
local BACKGROUND_COLOR = Color3.fromRGB(25, 30, 45)

local DashIndicator = {}

function DashIndicator.new(parent: Instance): DashIndicator
	local gui = Instance.new("ScreenGui")
	gui.Name = "MovementHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	-- A CanvasGroup clips its children to its rounded corners.
	local badge = Instance.new("CanvasGroup")
	badge.Name = "DashBadge"
	badge.AnchorPoint = Vector2.new(0.5, 1)
	badge.Position = UDim2.new(0.5, 0, 1, -24)
	badge.Size = UDim2.fromOffset(64, 64)
	badge.BackgroundColor3 = BACKGROUND_COLOR
	badge.BackgroundTransparency = 0.25
	badge.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0) -- fully round
	corner.Parent = badge

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = FILL_COLOR
	fill.BackgroundTransparency = 0.2
	fill.Parent = badge

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 18
	label.TextColor3 = READY_COLOR
	label.TextStrokeTransparency = 0.5
	label.Text = "DASH"
	label.ZIndex = 2
	label.Parent = badge

	-- The ring sits outside the CanvasGroup so it is not clipped.
	local ringHolder = Instance.new("Frame")
	ringHolder.AnchorPoint = badge.AnchorPoint
	ringHolder.Position = badge.Position
	ringHolder.Size = badge.Size
	ringHolder.BackgroundTransparency = 1
	ringHolder.Parent = gui

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ringHolder

	local ring = Instance.new("UIStroke")
	ring.Thickness = 3
	ring.Color = READY_COLOR
	ring.Parent = ringHolder

	gui.Parent = parent

	local wasReady = true

	local function update(progress: number, secondsLeft: number)
		local clamped = math.clamp(progress, 0, 1)
		fill.Size = UDim2.fromScale(1, clamped)
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
			ringHolder.Size = UDim2.fromOffset(76, 76)
			TweenService:Create(ringHolder, TweenInfo.new(0.2, Enum.EasingStyle.Back), {
				Size = UDim2.fromOffset(64, 64),
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

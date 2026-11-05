--!strict
--[[
	ResponsiveScale
	===============
	Everything is designed for a 1280x720 screen. This adds a UIScale to a
	ScreenGui that grows or shrinks it to fit the real screen, so the HUD is
	readable on a big monitor and still fits on a small phone.
]]

local Theme = require(script.Parent:WaitForChild("Theme"))

local MIN_SCALE = 0.5
local MAX_SCALE = 1.5

local ResponsiveScale = {}

function ResponsiveScale.getScale(): number
	local camera = workspace.CurrentCamera
	if camera == nil then
		return 1
	end
	local viewport = camera.ViewportSize
	local design = Theme.DesignResolution
	local scale = math.min(viewport.X / design.X, viewport.Y / design.Y)
	return math.clamp(scale, MIN_SCALE, MAX_SCALE)
end

function ResponsiveScale.apply(gui: ScreenGui)
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui

	local cameraConnection: RBXScriptConnection? = nil

	local function update()
		uiScale.Scale = ResponsiveScale.getScale()
	end

	local function watchCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
		update()
	end

	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
end

return ResponsiveScale

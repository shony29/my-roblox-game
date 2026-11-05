--!strict
--[[
	PracticeDummy: a target for the lobby's training range.

	It has a Humanoid (so bullets, hitmarkers and headshots work exactly like
	on players) and an always-visible health bar. When knocked out it pops
	back up a moment later. It never moves and never fights back.
]]

local DUMMY_HEALTH = 150
local RESPAWN_DELAY = 1.5

local PracticeDummy = {}

local function part(model: Model, name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- Builds one dummy standing at `base` (a point on the floor), facing `lookAt`.
function PracticeDummy.build(parent: Instance, base: Vector3, lookAt: Vector3, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "PracticeDummy"
	local facing = CFrame.lookAt(base, Vector3.new(lookAt.X, base.Y, lookAt.Z))

	-- A wooden post, a round jelly body and a head (headshots count).
	part(model, "Post", Enum.PartType.Block, Vector3.new(0.6, 2, 0.6), facing * CFrame.new(0, 1, 0), Color3.fromRGB(150, 105, 70))
	local body = part(model, "Body", Enum.PartType.Ball, Vector3.new(3.6, 3.6, 3.6), facing * CFrame.new(0, 3.4, 0), color)
	body.Material = Enum.Material.Glass
	body.Transparency = 0.15
	part(model, "Head", Enum.PartType.Ball, Vector3.new(1.8, 1.8, 1.8), facing * CFrame.new(0, 5.8, 0), color:Lerp(Color3.new(1, 1, 1), 0.3))

	local root = part(model, "HumanoidRootPart", Enum.PartType.Block, Vector3.new(2, 2, 1), facing * CFrame.new(0, 3.4, 0), color)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	model.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = DUMMY_HEALTH
	humanoid.Health = DUMMY_HEALTH
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayName = "Practice Dummy"
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.Parent = model

	model.Parent = parent

	-- Knocked out: pop back up after a moment.
	humanoid.Died:Once(function()
		task.delay(RESPAWN_DELAY, function()
			if model.Parent then
				model:Destroy()
				PracticeDummy.build(parent, base, lookAt, color)
			end
		end)
	end)
	return model
end

return PracticeDummy

--!strict
--[[
	ToppingEffects: what a slime bursts into when it's eliminated.

	The server tags the eliminated slime with the eliminator's equipped
	topping (the "BurstTopping" attribute). Each player's screen then plays
	that topping here. Purely visual, on this screen only:
	  Slime      a puff of jelly in the slime's own colour (the default)
	  Sprinkles  colourful sprinkles that fly out and drop to the floor
	  Foam       soft foam balls
	  Glitter    tiny glittering flakes with a sparkle shimmer
	  Charms     little 3D charms (a strawberry, a cupcake, a pumpkin...)
	             from charm packets, built by Cosmetics/CharmBuilder
	Every burst starts with a pop: a bright flash, a glowing ring racing
	across the floor and a jelly splat left behind for a moment.
	Pieces never collide or block bullets, and are cleaned up after ~2 s.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ShopConfig"))
local CharmBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Cosmetics"):WaitForChild("CharmBuilder"))

local LIFETIME = 2
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

local ToppingEffects = {}

local random = Random.new()
local folder: Folder? = nil

local function fxFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "ToppingFx"
	newFolder.Parent = Workspace
	folder = newFolder
	return newFolder
end

local function piece(size: Vector3, color: Color3, shape: Enum.PartType, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Shape = shape
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- Throws a piece up and out from `from`, lets it fall to the floor, then fades
-- it. `owner` (the piece itself, or the charm model it moves) is cleaned up.
local function fling(part: BasePart, from: Vector3, fade: (number) -> (), owner: Instance?)
	local holder: Instance = owner or part
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = random:NextNumber(3.5, 9)
	local flat = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local spin = CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), random:NextNumber(0, 6))
	holder.Parent = fxFolder() -- first, so a welded charm moves as one piece
	part.CFrame = CFrame.new(from) * spin
	local peak = from + flat * distance * 0.55 + Vector3.new(0, random:NextNumber(3, 6.5), 0)
	local land = from + flat * distance + Vector3.new(0, -1.8, 0) -- about floor level under a slime
	TweenService:Create(part, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(peak) * spin }):Play()
	task.delay(0.28, function()
		if part.Parent then
			TweenService:Create(part, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(land) * spin }):Play()
		end
	end)
	task.delay(LIFETIME - 0.4, function()
		fade(0.4)
		task.delay(0.45, function()
			holder:Destroy()
		end)
	end)
end

local function fadePart(part: BasePart): (number) -> ()
	return function(seconds: number)
		if part.Parent then
			TweenService:Create(part, TweenInfo.new(seconds), { Transparency = 1 }):Play()
		end
	end
end

local function sparkleBurst(position: Vector3, color: Color3, amount: number)
	local holder = Instance.new("Attachment")
	holder.Position = position -- Terrain sits at the world origin
	holder.Parent = Workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLES
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.4
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.45, 0.8)
	emitter.Speed = NumberRange.new(10, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -45, 0)
	emitter.Enabled = false
	emitter.Parent = holder
	emitter:Emit(amount)
	task.delay(1.5, function()
		holder:Destroy()
	end)
end

-- The "pop" every burst starts with: a bright flash, a glowing ring that
-- races across the floor, and a jelly splat left on the ground.
local function pop(position: Vector3, color: Color3, lowQuality: boolean)
	local bright = color:Lerp(Color3.new(1, 1, 1), 0.45)
	local flash = piece(Vector3.one * 0.8, bright, Enum.PartType.Ball, Enum.Material.Neon)
	flash.Transparency = 0.15
	flash.CFrame = CFrame.new(position)
	flash.Parent = fxFolder()
	TweenService:Create(flash, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 5, Transparency = 1 }):Play()
	task.delay(0.3, function()
		flash:Destroy()
	end)
	if lowQuality then
		return
	end

	local floor = position + Vector3.new(0, -1.75, 0)
	local flat = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder lying flat
	local ring = piece(Vector3.new(0.08, 1.2, 1.2), color, Enum.PartType.Cylinder, Enum.Material.Neon)
	ring.Transparency = 0.25
	ring.CFrame = CFrame.new(floor + Vector3.new(0, 0.06, 0)) * flat
	ring.Parent = fxFolder()
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.08, 10, 10), Transparency = 1 }):Play()
	task.delay(0.5, function()
		ring:Destroy()
	end)

	local splat = piece(Vector3.new(0.1, 3.4, 3.4), color, Enum.PartType.Cylinder, Enum.Material.SmoothPlastic)
	splat.Reflectance = 0.15
	splat.CFrame = CFrame.new(floor + Vector3.new(0, 0.04, 0)) * flat
	splat.Parent = fxFolder()
	task.delay(1.6, function()
		TweenService:Create(splat, TweenInfo.new(0.7), { Transparency = 1, Size = Vector3.new(0.1, 4.2, 4.2) }):Play()
		task.delay(0.75, function()
			splat:Destroy()
		end)
	end)
end

--[[
	Plays the burst for `toppingId` at `position`. `slimeColor` colours the
	default Slime Splat. `lowQuality` uses fewer pieces (Low graphics).
]]
function ToppingEffects.play(position: Vector3, toppingId: string?, slimeColor: Color3, lowQuality: boolean)
	local topping = ShopConfig.getTopping(toppingId)
	local scale = if lowQuality then 0.5 else 1
	local colors = topping.Colors
	local function color(i: number): Color3
		return colors[(i % #colors) + 1]
	end
	pop(position, if topping.Style == "Slime" then slimeColor else colors[1], lowQuality)

	if topping.Style == "Slime" then
		sparkleBurst(position, slimeColor, math.floor(28 * scale))
	elseif topping.Style == "Sprinkles" then
		for i = 1, math.floor(26 * scale) do
			local part = piece(Vector3.new(0.14, 0.14, 0.55), color(i), Enum.PartType.Block)
			fling(part, position, fadePart(part))
		end
	elseif topping.Style == "Foam" then
		for i = 1, math.floor(16 * scale) do
			local d = random:NextNumber(0.35, 0.7)
			local part = piece(Vector3.new(d, d, d), color(i), Enum.PartType.Ball)
			fling(part, position, fadePart(part))
		end
	elseif topping.Style == "Glitter" then
		for i = 1, math.floor(30 * scale) do
			local part = piece(Vector3.new(0.22, 0.22, 0.04), color(i), Enum.PartType.Block, Enum.Material.Neon)
			fling(part, position, fadePart(part))
		end
		sparkleBurst(position, color(0), math.floor(14 * scale))
	else -- Charms: little 3D charms tumbling out
		local charms = topping.Charms or { "Star" }
		for i = 1, math.floor(8 * scale) do
			local charm = CharmBuilder.build(charms[(i % #charms) + 1], { scale = 0.85, welded = true })
			charm:PivotTo(CFrame.new(position))
			local root = charm.PrimaryPart
			if root then
				fling(root, position, function(seconds: number)
					for _, child in charm:GetChildren() do
						if child:IsA("BasePart") and child ~= root then
							TweenService:Create(child, TweenInfo.new(seconds), { Transparency = 1 }):Play()
						end
					end
				end, charm)
			else
				charm:Destroy()
			end
		end
		sparkleBurst(position, color(0), math.floor(10 * scale))
	end
end

return ToppingEffects

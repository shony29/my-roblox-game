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
	The slime vanishes at once and explodes into the topping (with chunks
	of its own jelly). Your topping also flies out of your gun with every
	shot (ToppingEffects.shot, called by WeaponController).
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
-- `power` makes the throw further and higher (1 = normal).
local function fling(part: BasePart, from: Vector3, fade: (number) -> (), owner: Instance?, power: number?)
	local holder: Instance = owner or part
	local strength = power or 1
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = random:NextNumber(4, 11) * strength
	local flat = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local spin = CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), random:NextNumber(0, 6))
	holder.Parent = fxFolder() -- first, so a welded charm moves as one piece
	part.CFrame = CFrame.new(from) * spin
	local peak = from + flat * distance * 0.55 + Vector3.new(0, random:NextNumber(3.5, 8) * strength, 0)
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

-- One small piece of a topping (for bursts and shots).
local function toppingPiece(style: string, color: Color3, size: number): Part
	if style == "Sprinkles" then
		return piece(Vector3.new(0.14, 0.14, 0.55) * size, color, Enum.PartType.Block)
	elseif style == "Foam" then
		local d = random:NextNumber(0.35, 0.65) * size
		return piece(Vector3.new(d, d, d), color, Enum.PartType.Ball)
	elseif style == "Glitter" then
		return piece(Vector3.new(0.24, 0.24, 0.04) * size, color, Enum.PartType.Block, Enum.Material.Neon)
	elseif style == "Charms" then
		local bead = piece(Vector3.new(0.3, 0.3, 0.3) * size, color, Enum.PartType.Ball)
		bead.Reflectance = 0.15
		return bead
	end
	-- Slime: a glossy jelly droplet.
	local drop = piece(Vector3.new(0.4, 0.4, 0.55) * size, color, Enum.PartType.Block)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = drop
	drop.Reflectance = 0.12
	return drop
end

--[[
	Plays the burst for `toppingId` at `position`: the eliminated slime
	pops and explodes into the topping. `slimeColor` is the slime's own
	colour (its jelly chunks, and the default Slime Splat). `lowQuality`
	uses fewer pieces (Low graphics).
]]
function ToppingEffects.play(position: Vector3, toppingId: string?, slimeColor: Color3, lowQuality: boolean)
	local topping = ShopConfig.getTopping(toppingId)
	local scale = if lowQuality then 0.5 else 1
	local colors = topping.Colors
	local function color(i: number): Color3
		return colors[(i % #colors) + 1]
	end
	pop(position, if topping.Style == "Slime" then slimeColor else colors[1], lowQuality)

	-- Chunks of the slime itself always fly out: it really bursts.
	for _ = 1, math.floor(10 * scale) do
		local chunk = toppingPiece("Slime", slimeColor, random:NextNumber(1.2, 2))
		chunk.Transparency = 0.1
		fling(chunk, position, fadePart(chunk), nil, 0.85)
	end

	if topping.Style == "Slime" then
		for i = 1, math.floor(18 * scale) do
			local drop = toppingPiece("Slime", slimeColor:Lerp(Color3.new(1, 1, 1), (i % 3) * 0.15), 1)
			fling(drop, position, fadePart(drop), nil, 1.1)
		end
		sparkleBurst(position, slimeColor, math.floor(30 * scale))
	elseif topping.Style == "Charms" then
		-- Little 3D charms tumbling out, with beads in the packet's colours.
		local charms = topping.Charms or { "Star" }
		for i = 1, math.floor(10 * scale) do
			local charm = CharmBuilder.build(charms[(i % #charms) + 1], { scale = 0.9, welded = true })
			charm:PivotTo(CFrame.new(position))
			local root = charm.PrimaryPart
			if root then
				fling(root, position, function(seconds: number)
					for _, child in charm:GetChildren() do
						if child:IsA("BasePart") and child ~= root then
							TweenService:Create(child, TweenInfo.new(seconds), { Transparency = 1 }):Play()
						end
					end
				end, charm, 1.1)
			else
				charm:Destroy()
			end
		end
		for i = 1, math.floor(12 * scale) do
			local bead = toppingPiece("Charms", color(i), 1)
			fling(bead, position, fadePart(bead))
		end
		sparkleBurst(position, color(0), math.floor(16 * scale))
	else
		local amount = if topping.Style == "Foam" then 26 else 42
		for i = 1, math.floor(amount * scale) do
			local part = toppingPiece(topping.Style, color(i), 1)
			fling(part, position, fadePart(part), nil, 1.15)
		end
		if topping.Style == "Glitter" then
			sparkleBurst(position, color(0), math.floor(20 * scale))
		end
	end
end

--[[
	A few pieces of the shooter's topping fly out of the gun with each shot,
	along the bullet's path from `from` (the gun's tip) to `to`, then vanish.
	`slimeColor` colours the default Slime Splat (the shooter's own slime).
]]
function ToppingEffects.shot(from: Vector3, to: Vector3, toppingId: string?, slimeColor: Color3, count: number)
	local offset = to - from
	local distance = offset.Magnitude
	if distance < 1 or count <= 0 then
		return
	end
	local topping = ShopConfig.getTopping(toppingId)
	local colors = topping.Colors
	local direction = offset.Unit
	local side = direction:Cross(Vector3.yAxis)
	if side.Magnitude < 0.01 then
		side = Vector3.xAxis
	end
	side = side.Unit
	local up = side:Cross(direction).Unit
	for i = 1, count do
		local color = if topping.Style == "Slime" then slimeColor else colors[random:NextInteger(1, #colors)]
		local part = toppingPiece(topping.Style, color, 0.75)
		-- Each piece leaves a moment after the last, slightly off the line.
		local wobble = side * random:NextNumber(-0.35, 0.35) + up * random:NextNumber(-0.35, 0.35)
		local finish = to + wobble * math.min(distance / 20, 2)
		local travel = math.clamp(distance / 170, 0.05, 0.4)
		local spin = CFrame.Angles(0, 0, random:NextNumber(0, 6))
		part.CFrame = CFrame.lookAt(from, finish) * spin
		part.Parent = fxFolder()
		local delay = (i - 1) * 0.025
		task.delay(delay, function()
			if not part.Parent then
				return
			end
			local flight = TweenService:Create(part, TweenInfo.new(travel, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(finish, finish + direction) * spin })
			flight.Completed:Once(function()
				TweenService:Create(part, TweenInfo.new(0.12), { Transparency = 1, Size = part.Size * 0.4 }):Play()
				task.delay(0.15, function()
					part:Destroy()
				end)
			end)
			flight:Play()
		end)
	end
end

return ToppingEffects

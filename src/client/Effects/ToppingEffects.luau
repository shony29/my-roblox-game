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
	  Charms     little charms (emoji) such as 🎄 🍪 🎅 from charm packets
	Pieces never collide or block bullets, and are cleaned up after ~2 s.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ShopConfig"))

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

-- Throws a piece up and out from `from`, lets it fall to the floor, then fades it.
local function fling(part: BasePart, from: Vector3, fade: (number) -> ())
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = random:NextNumber(3.5, 9)
	local flat = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local spin = CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), random:NextNumber(0, 6))
	part.CFrame = CFrame.new(from) * spin
	part.Parent = fxFolder()
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
			part:Destroy()
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
	else -- Charms
		local charms = topping.Charms or { "⭐" }
		for i = 1, math.floor(10 * scale) do
			local part = piece(Vector3.new(0.2, 0.2, 0.2), Color3.new(1, 1, 1), Enum.PartType.Block)
			part.Transparency = 1
			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.fromScale(1.8, 1.8)
			billboard.LightInfluence = 0
			billboard.Parent = part
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.TextScaled = true
			label.Text = charms[(i % #charms) + 1]
			label.Parent = billboard
			fling(part, position, function(seconds: number)
				TweenService:Create(label, TweenInfo.new(seconds), { TextTransparency = 1 }):Play()
			end)
		end
	end
end

return ToppingEffects

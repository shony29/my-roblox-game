--!strict
--[[
	BlobCharacter
	=============
	Turns a normal Roblox character into a cute round blob.

	How it works:
	  1. The normal Roblox body stays (it handles walking, jumping and physics),
	     but every part of it is made invisible.
	  2. We build a blob out of simple ball shapes: a body, two eyes (white
	     plus a black pupil) and a smile made of little dots.
	  3. The blob parts are glued ("welded") to the character's root part,
	     so the blob moves wherever the invisible body goes.

	This runs on the server, so every player sees everyone's blob.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Shared.Movement.MovementConfig)
local HitGroups = require(ReplicatedStorage.Shared.Combat.HitGroups)

local BLOB_ATTRIBUTE = "IsBlobPart"
local BLOB_MODEL_NAME = "Blob"

local BlobCharacter = {}

-- Picks a random bright color (random hue, high saturation and brightness).
function BlobCharacter.randomColor(): Color3
	return Color3.fromHSV(math.random(), MovementConfig.BlobColorSaturation, MovementConfig.BlobColorBrightness)
end

-- How far the bottom of the feet is below the center of the root part.
function BlobCharacter.groundOffset(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return root.Size.Y / 2 + humanoid.HipHeight
	end
	-- R6 characters have 2-stud-tall legs and no hip height.
	return root.Size.Y / 2 + 2
end

-- Makes one piece of the original Roblox body invisible.
local function hide(instance: Instance)
	if instance:GetAttribute(BLOB_ATTRIBUTE) then
		return
	end
	if instance:IsA("Accessory") then
		instance:Destroy() -- hats and hair would float around the blob
	elseif instance:IsA("BasePart") then
		instance.Transparency = 1
		-- Bullets ignore the hidden body and hit the visible blob instead.
		instance.CollisionGroup = HitGroups.HIDDEN_BODY
	elseif instance:IsA("Decal") then
		instance.Transparency = 1 -- the default face
	end
end

-- Makes one ball-shaped, non-colliding, weightless part.
local function makeBall(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
	part:SetAttribute(BLOB_ATTRIBUTE, true)
	return part
end

-- Finds a point on the front of the blob's (squashed ball) surface.
-- x = left/right, y = up/down from the body's center. Front is -Z.
local function frontSurfacePoint(x: number, y: number, pushOut: number): Vector3
	local size = MovementConfig.BlobBodySize
	local a, b, c = size.X / 2, size.Y / 2, size.Z / 2
	local inside = 1 - (x / a) ^ 2 - (y / b) ^ 2
	local z = -c * math.sqrt(math.max(inside, 0))
	return Vector3.new(x, y, z - pushOut)
end

-- Builds the blob and glues it to the character.
function BlobCharacter.apply(character: Model, color: Color3)
	HitGroups.setup()
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		warn(`BlobCharacter: {character.Name} has no Humanoid or HumanoidRootPart`)
		return
	end

	-- Remove an old blob if this somehow runs twice.
	local old = character:FindFirstChild(BLOB_MODEL_NAME)
	if old then
		old:Destroy()
	end

	-- 1. Hide the normal body, now and for anything that loads in later.
	for _, descendant in character:GetDescendants() do
		hide(descendant)
	end
	character.DescendantAdded:Connect(function(descendant: Instance)
		-- Wait a moment so the new item finishes setting itself up first.
		task.defer(hide, descendant)
	end)

	-- 2. Build the blob.
	local model = Instance.new("Model")
	model.Name = BLOB_MODEL_NAME
	model:SetAttribute(BLOB_ATTRIBUTE, true)

	local bodySize = MovementConfig.BlobBodySize
	-- Sit the blob's bottom on the ground.
	local bodyCenter = root.CFrame * CFrame.new(0, -BlobCharacter.groundOffset(humanoid, root) + bodySize.Y / 2, 0)

	local parts: { BasePart } = {}

	-- A sphere-shaped mesh lets the body be slightly squashed (wider than tall).
	local body = makeBall("Body", bodySize, color)
	body.Shape = Enum.PartType.Block
	body.Size = bodySize -- set again: ball shapes force all sides to be equal
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	body.CFrame = bodyCenter
	-- The blob body is the hitbox that bullets hit (see Shared/Combat/HitGroups).
	body.CanQuery = true
	table.insert(parts, body)

	-- Eyes: a white ball with a black pupil in front of it.
	local eyeSize = MovementConfig.BlobEyeSize
	local pupilSize = MovementConfig.BlobPupilSize
	for _, side in { -1, 1 } do
		local eyeOffset = frontSurfacePoint(side * 0.75, 0.45, -eyeSize * 0.15)
		local eye = makeBall("Eye", Vector3.one * eyeSize, Color3.new(1, 1, 1))
		eye.CFrame = bodyCenter * CFrame.new(eyeOffset)
		table.insert(parts, eye)

		local pupil = makeBall("Pupil", Vector3.one * pupilSize, Color3.fromRGB(25, 25, 35))
		pupil.CFrame = bodyCenter * CFrame.new(eyeOffset + Vector3.new(0, -0.05, -(eyeSize - pupilSize) / 2 - 0.05))
		table.insert(parts, pupil)
	end

	-- Smile: little dots along a curved "U" shape below the eyes.
	local dotCount = MovementConfig.BlobSmileDots
	local dotSize = MovementConfig.BlobSmileDotSize
	local smileRadius = 0.55
	local smileCenterY = -0.05
	for i = 1, dotCount do
		local t = (i - 1) / math.max(dotCount - 1, 1) -- 0 .. 1
		local angle = math.rad(-55 + 110 * t)
		local x = smileRadius * math.sin(angle)
		local y = smileCenterY - smileRadius * math.cos(angle)
		local dot = makeBall("Smile", Vector3.one * dotSize, Color3.fromRGB(25, 25, 35))
		dot.CFrame = bodyCenter * CFrame.new(frontSurfacePoint(x, y, -dotSize * 0.2))
		table.insert(parts, dot)
	end

	-- 3. Glue every blob part to the root so it follows the character.
	for _, part in parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
	end

	model.Parent = character
end

return BlobCharacter

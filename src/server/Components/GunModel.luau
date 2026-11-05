--!strict
--[[
	GunModel: builds a simple low-poly gun out of blocks and welds it to the
	character's right hand, so everyone can see what you're holding.

	It has an Attachment called "Muzzle" at the tip. The client uses it as
	the spot where the muzzle flash and tracers start.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("WeaponConfig"))

type WeaponStats = WeaponConfig.WeaponStats

local GUN_NAME = "EquippedGun"

-- The Movement system turns players into blobs and hides every other part
-- added to the character, unless it carries this attribute. We set it so
-- the gun stays visible.
local KEEP_VISIBLE_ATTRIBUTE = "IsBlobPart"

local function makePart(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	-- CanQuery = false makes bullets fly through guns instead of hitting them.
	part.CanQuery = false
	part.CastShadow = false
	part:SetAttribute(KEEP_VISIBLE_ATTRIBUTE, true)
	return part
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

local GunModel = {}

GunModel.NAME = GUN_NAME

-- Removes any gun the character is holding.
function GunModel.remove(character: Model)
	local old = character:FindFirstChild(GUN_NAME)
	if old then
		old:Destroy()
	end
end

-- Puts the gun for `stats` into the character's right hand.
function GunModel.attach(character: Model, stats: WeaponStats)
	GunModel.remove(character)

	-- R15 characters have a "RightHand", R6 characters have a "Right Arm".
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end

	local model = Instance.new("Model")
	model.Name = GUN_NAME
	model:SetAttribute(KEEP_VISIBLE_ATTRIBUTE, true)

	local length = stats.GunLength
	local body = makePart("Body", Vector3.new(0.35, 0.45, length), stats.GunColor)
	local grip = makePart("Grip", Vector3.new(0.3, 0.6, 0.35), Color3.fromRGB(45, 45, 55))
	local barrel = makePart("Barrel", Vector3.new(0.2, 0.2, 0.5), Color3.fromRGB(45, 45, 55))

	-- Line the gun up with the hand, pointing forward (-Z is "forward" in Roblox).
	local handBottom = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, 0)
	body.CFrame = handBottom * CFrame.new(0, 0, -length / 2 + 0.3)
	grip.CFrame = handBottom * CFrame.new(0, -0.35, 0.05)
	barrel.CFrame = body.CFrame * CFrame.new(0, 0.05, -length / 2 - 0.25)

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -0.25)
	muzzle.Parent = barrel

	for _, part in { body, grip, barrel } do
		part.Parent = model
	end
	weld(hand, body)
	weld(body, grip)
	weld(body, barrel)

	model.PrimaryPart = body
	model.Parent = character
end

--[[
	A bigger copy of a gun for showing off (the lobby's weapons room). Not
	held by anyone: anchored at `cframe`, pointing along its -Z.
]]
function GunModel.display(stats: WeaponStats, cframe: CFrame, scale: number): Model
	local model = Instance.new("Model")
	model.Name = "Display_" .. stats.Id
	local length = stats.GunLength * scale
	local dark = Color3.fromRGB(45, 45, 55)
	local body = makePart("Body", Vector3.new(0.35, 0.45, stats.GunLength) * scale, stats.GunColor)
	local grip = makePart("Grip", Vector3.new(0.3, 0.6, 0.35) * scale, dark)
	local barrel = makePart("Barrel", Vector3.new(0.2, 0.2, 0.5) * scale, dark)
	body.CFrame = cframe
	grip.CFrame = cframe * CFrame.new(0, -0.35 * scale, length / 2 - 0.25 * scale)
	barrel.CFrame = cframe * CFrame.new(0, 0.05 * scale, -length / 2 - 0.25 * scale)
	for _, part in { body, grip, barrel } do
		part.Anchored = true
		part.CastShadow = true
		part.Parent = model
	end
	model.PrimaryPart = body
	return model
end

return GunModel

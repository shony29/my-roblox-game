--!strict
--[[
	GunModel: puts a gun in a slime's right hand, so everyone can see what
	you're holding (and the first-person view copies it).

	The gun itself comes from Shared/Cosmetics/GunBuilder: a chunky toy-like
	model with its own design for every weapon. It has an Attachment called
	"Muzzle" at the tip, where the muzzle flash and tracers start.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared:WaitForChild("Config"):WaitForChild("WeaponConfig"))
local GunBuilder = require(Shared:WaitForChild("Cosmetics"):WaitForChild("GunBuilder"))

type WeaponStats = WeaponConfig.WeaponStats

local GUN_NAME = "EquippedGun"

-- The Movement system turns players into blobs and hides every other part
-- added to the character, unless it carries this attribute. We set it so
-- the gun stays visible.
local KEEP_VISIBLE_ATTRIBUTE = "IsBlobPart"

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

	-- The grip sits where the hand is, pointing forward (-Z is "forward" in Roblox).
	local handBottom = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, 0)
	local model = GunBuilder.build(stats, handBottom, nil)
	model.Name = GUN_NAME
	model:SetAttribute(KEEP_VISIBLE_ATTRIBUTE, true)
	local body = model.PrimaryPart
	if body == nil then
		model:Destroy()
		return
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= body then
			weld(body, part)
		end
	end
	weld(hand, body)
	model.Parent = character
end

--[[
	A bigger copy of a gun for showing off (the lobby's weapons room). Not
	held by anyone: anchored with its grip at `cframe`, pointing along -Z.
]]
function GunModel.display(stats: WeaponStats, cframe: CFrame, scale: number): Model
	local model = GunBuilder.build(stats, cframe, { anchored = true, shadows = true, scale = scale })
	model.Name = "Display_" .. stats.Id
	return model
end

return GunModel

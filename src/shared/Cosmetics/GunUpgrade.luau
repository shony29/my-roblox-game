--!strict
--[[
	GunUpgrade: shows a gun's upgrade level. The gun's body takes the level's
	colour (red, orange, yellow, green, blue, purple) and, from level 4, a
	glowing stripe runs along the top. Applied after the weapon skin, so the
	upgrade colour wins on the body while skin patterns stay.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("UpgradeConfig"))

local GLOW_NAME = "UpgradeGlow"
local LEVEL_ATTRIBUTE = "UpgradeLevel"

local GunUpgrade = {}

GunUpgrade.LEVEL_ATTRIBUTE = LEVEL_ATTRIBUTE

function GunUpgrade.apply(gun: Model, level: number)
	if gun:GetAttribute(LEVEL_ATTRIBUTE) == level then
		return
	end
	gun:SetAttribute(LEVEL_ATTRIBUTE, level)
	local oldGlow = gun:FindFirstChild(GLOW_NAME)
	if oldGlow then
		oldGlow:Destroy()
	end
	local tier = UpgradeConfig.tier(level)
	local body = gun:FindFirstChild("Body")
	if not tier or not body or not body:IsA("BasePart") then
		return -- level 0: the skin's own colours
	end
	body.Color = tier.Color
	if level >= UpgradeConfig.GLOW_FROM_LEVEL then
		local glow = Instance.new("Part")
		glow.Name = GLOW_NAME
		glow.Size = Vector3.new(body.Size.X * 0.5, 0.08, body.Size.Z * 0.92)
		glow.CFrame = body.CFrame * CFrame.new(0, body.Size.Y / 2 + 0.03, 0)
		glow.Color = tier.Color:Lerp(Color3.new(1, 1, 1), 0.25)
		glow.Material = Enum.Material.Neon
		glow.CanCollide = false
		glow.CanQuery = false
		glow.CanTouch = false
		glow.Massless = true
		glow.CastShadow = false
		glow:SetAttribute("IsBlobPart", true) -- stay visible on blob characters
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = glow
		weld.Parent = glow
		glow.Parent = gun
	end
end

return GunUpgrade

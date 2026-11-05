--!strict
--[[
	SlimeRig: the one body every player gets.

	Normally each player spawns with their own Roblox avatar, and avatars
	come in different heights and widths. That would make some slimes bigger
	(easier to hit, harder to fit through doors) than others. So instead we
	build one small, invisible rig and put it in StarterPlayer as
	"StarterCharacter". Roblox then spawns EVERY player as a copy of it.

	The rig (all sizes in studs; the floor is 0):
	  HumanoidRootPart  3 x 2 x 3 box, centre 2 studs up. The only part that
	                    collides, so movement and collision are identical for all.
	  Head              eye height for the camera and the weapon's shot origin.
	  RightHand         where the gun is held (front right of the blob).
	  Humanoid          walking, jumping and health (100).

	The visible jelly blob is added on top by Components/BlobCharacter, and
	the fixed hitbox bullets hit is part of that blob.
]]

local StarterPlayer = game:GetService("StarterPlayer")

local RIG_NAME = "StarterCharacter"
local ROOT_SIZE = Vector3.new(3, 2, 3)
local HIP_HEIGHT = 1 -- gap between the floor and the bottom of the root box
local HEAD_OFFSET = Vector3.new(0, 1.3, -0.3) -- from the root's centre
local HAND_OFFSET = Vector3.new(1.6, 0.2, -1.2)

local SlimeRig = {}

local function makePart(name: string, size: Vector3, collide: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Transparency = 1
	part.CanCollide = collide
	part.CanTouch = collide
	part.CanQuery = collide
	part.CastShadow = false
	part.Massless = not collide
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function attach(part: BasePart, root: BasePart, offset: Vector3)
	part.CFrame = root.CFrame * CFrame.new(offset)
	local weld = Instance.new("Weld")
	weld.Name = "RootWeld"
	weld.Part0 = root
	weld.Part1 = part
	weld.C0 = CFrame.new(offset)
	weld.Parent = part
end

-- Builds the rig model (not yet placed anywhere).
function SlimeRig.build(): Model
	local model = Instance.new("Model")
	model.Name = RIG_NAME

	local root = makePart("HumanoidRootPart", ROOT_SIZE, true)
	root.CFrame = CFrame.new(0, HIP_HEIGHT + ROOT_SIZE.Y / 2, 0)
	root.Parent = model
	model.PrimaryPart = root

	local head = makePart("Head", Vector3.new(1.2, 1.2, 1.2), false)
	attach(head, root, HEAD_OFFSET)
	head.Parent = model

	local hand = makePart("RightHand", Vector3.new(0.6, 0.6, 0.6), false)
	attach(hand, root, HAND_OFFSET)
	hand.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15 -- R15 so HipHeight is used
	humanoid.HipHeight = HIP_HEIGHT
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	-- There is no neck joint in this rig; without this the slime would die instantly.
	humanoid.RequiresNeck = false
	-- Keep the blob in one piece when eliminated (the death effect is done separately).
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model

	return model
end

-- Installs the rig as StarterPlayer.StarterCharacter. Call before anyone spawns.
function SlimeRig.install()
	local existing = StarterPlayer:FindFirstChild(RIG_NAME)
	if existing then
		existing:Destroy()
	end
	SlimeRig.build().Parent = StarterPlayer

	-- An empty script named "Animate" replaces Roblox's default walking
	-- animations, which need arms and legs our rig doesn't have.
	local characterScripts = StarterPlayer:FindFirstChildOfClass("StarterCharacterScripts")
	if characterScripts and not characterScripts:FindFirstChild("Animate") then
		local blank = Instance.new("LocalScript")
		blank.Name = "Animate"
		blank.Parent = characterScripts
	end
end

return SlimeRig

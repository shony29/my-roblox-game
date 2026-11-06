--!strict
--[[
	BlobCharacter
	=============
	Turns a normal Roblox character into a soft, squishy jelly blob.

	How it works:
	  1. The normal Roblox body stays (it handles walking, jumping and physics),
	     but every part of it is made invisible.
	  2. We build the blob out of a few rounded pieces that overlap, so it
	     looks like one lumpy, melty shape instead of a perfect ball:
	       * Base     - a wide puddle that spreads over the floor
	       * Dome     - the main body
	       * Shell    - a see-through glossy layer over the dome (the "jelly" look)
	       * Lobes    - melty bulges at the bottom and a dollop on top
	       * Shine    - a soft white highlight
	       * Face     - eyes, cheeks and a little smile, drawn with a SurfaceGui
	       * Body     - an invisible box that bullets hit (the hitbox)
	  3. Each piece is attached to the character's root with a Weld. The
	     client script Movement/BlobAnimator moves those welds every frame to
	     make the blob breathe, stretch, squish and wobble. That is purely
	     visual, so it can't affect fairness.

	This runs on the server, so every player sees everyone's blob.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)
local Progression = require(ReplicatedStorage.Shared.Data.Progression)
local HitGroups = require(ReplicatedStorage.Shared.Combat.HitGroups)

local BLOB_ATTRIBUTE = "IsBlobPart"
local BLOB_MODEL_NAME = "Blob"

-- Shared with the client animator (client/Movement/BlobAnimator.luau).
local BLOB_TAG = "Blob"
local VISUAL_ATTRIBUTE = "BlobVisual" -- this piece should be animated
local WOBBLE_ATTRIBUTE = "Wobble" -- how much this piece jiggles on its own (0 = none)
local GROUND_ATTRIBUTE = "GroundY" -- where the floor is, relative to the root
local HEIGHT_ATTRIBUTE = "BlobHeight"

-- Overall height of the blob, in studs.
local BLOB_HEIGHT = 3.9

local BlobCharacter = {}

BlobCharacter.TAG = BLOB_TAG

-- Picks a random soft candy colour (random hue).
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
		-- Bullets ignore the hidden body and hit the blob's hitbox instead.
		instance.CollisionGroup = HitGroups.HIDDEN_BODY
	elseif instance:IsA("Decal") then
		instance.Transparency = 1 -- the default face
	end
end

-- Colour helpers --------------------------------------------------------------

local function shade(color: Color3, saturationScale: number, valueScale: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.clamp(s * saturationScale, 0, 1), math.clamp(v * valueScale, 0, 1))
end

type Shade = "Deep" | "Mid" | "Main" | "Light" | "Gloss"

-- Which shade each visible piece uses: darker at the bottom, lighter on top.
local SHADE_BY_NAME: { [string]: Shade } = {
	Base = "Deep",
	Drip = "Deep",
	LobeLeft = "Mid",
	LobeRight = "Mid",
	LobeBack = "Mid",
	Dome = "Main",
	Dollop = "Light",
	DollopSmall = "Light",
	Shell = "Gloss",
}

-- The five shades of one blob colour.
function BlobCharacter.palette(color: Color3): { [Shade]: Color3 }
	local deep = shade(color, 1.2, 0.78)
	return {
		Deep = deep,
		Mid = color:Lerp(deep, 0.45),
		Main = color,
		Light = shade(color, 0.75, 1.08),
		Gloss = shade(color, 0.45, 1.1),
	}
end

--[[
	Recolours an existing blob (used by the shop when you equip a colour).
	`material` and `reflectance` come from the shop item; the glossy shell
	always stays glass so the blob keeps its jelly look.
]]
function BlobCharacter.setColor(blob: Instance, color: Color3, material: Enum.Material?, reflectance: number?)
	local colors = BlobCharacter.palette(color)
	for _, descendant in blob:GetDescendants() do
		if descendant:IsA("BasePart") then
			local role = SHADE_BY_NAME[descendant.Name]
			if role then
				descendant.Color = colors[role]
				if role ~= "Gloss" then
					descendant.Material = material or Enum.Material.SmoothPlastic
					descendant.Reflectance = if role == "Main" then math.max(reflectance or 0, 0.05) else (reflectance or 0)
				end
			end
		end
	end
end

-- Building pieces ---------------------------------------------------------------

type PieceOptions = {
	name: string,
	size: Vector3,
	offset: Vector3, -- position relative to the root part
	color: Color3,
	wobble: number?,
	transparency: number?,
	material: Enum.Material?,
	shadow: boolean?,
}

local function weldToRoot(part: BasePart, root: BasePart, offset: Vector3)
	-- A Motor6D (not a Weld): the client animator moves each piece every
	-- frame through Motor6D.Transform, which Roblox made for exactly that.
	-- (Changing a Weld's C0 every frame makes Roblox rebuild the whole
	-- character each frame, which made moving slimes look choppy.)
	local motor = Instance.new("Motor6D")
	motor.Name = "BlobJoint"
	motor.Part0 = root
	motor.Part1 = part
	motor.C0 = CFrame.new(offset)
	motor.Parent = part
end

-- A soft rounded piece. A Block part with a Sphere mesh can be any oval
-- shape, and the animator can stretch it by changing the mesh's Scale.
local function makePiece(model: Model, root: BasePart, options: PieceOptions): Part
	local part = Instance.new("Part")
	part.Name = options.name
	part.Shape = Enum.PartType.Block
	part.Size = options.size
	part.Color = options.color
	part.Material = options.material or Enum.Material.SmoothPlastic
	part.Transparency = options.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = options.shadow == true
	part:SetAttribute(BLOB_ATTRIBUTE, true)
	part:SetAttribute(VISUAL_ATTRIBUTE, true)
	part:SetAttribute(WOBBLE_ATTRIBUTE, options.wobble or 0)

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part

	part.CFrame = root.CFrame * CFrame.new(options.offset)
	weldToRoot(part, root, options.offset)
	part.Parent = model
	return part
end

-- Helper for UI pieces on the face.
local function roundFrame(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0) -- fully rounded, so it's an oval
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

--[[
	The face is drawn on a thin invisible card at the front of the blob:
	two glossy oval eyes with a white sparkle, rosy cheeks and a small,
	gentle smile. The client animator makes the eyes blink.
]]
local FACE_SIZE = Vector2.new(2.6, 1.6) -- studs
local INK = Color3.fromRGB(45, 32, 58)

local function buildFace(model: Model, root: BasePart, offset: Vector3)
	local card = Instance.new("Part")
	card.Name = "Face"
	card.Size = Vector3.new(FACE_SIZE.X, FACE_SIZE.Y, 0.05)
	card.Transparency = 1
	card.CanCollide = false
	card.CanQuery = false
	card.CanTouch = false
	card.Massless = true
	card.CastShadow = false
	card:SetAttribute(BLOB_ATTRIBUTE, true)
	card:SetAttribute(VISUAL_ATTRIBUTE, true)
	card:SetAttribute(WOBBLE_ATTRIBUTE, 0)
	card.CFrame = root.CFrame * CFrame.new(offset)
	weldToRoot(card, root, offset)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "FaceGui"
	gui.Face = Enum.NormalId.Front -- the front of the blob
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0.6 -- a little shading so it sits in the world, but stays readable
	gui.Parent = card

	-- Eyes: tall glossy ovals with a white sparkle near the top.
	for _, side in { { name = "EyeL", x = 0.36 }, { name = "EyeR", x = 0.64 } } do
		local eye = roundFrame(gui, side.name, UDim2.fromScale(0.11, 0.3), UDim2.fromScale(side.x, 0.42), INK)
		roundFrame(eye, "Sparkle", UDim2.fromScale(0.42, 0.28), UDim2.fromScale(0.62, 0.3), Color3.new(1, 1, 1))
		roundFrame(eye, "Glint", UDim2.fromScale(0.2, 0.13), UDim2.fromScale(0.35, 0.68), Color3.new(1, 1, 1))
	end

	-- Rosy cheeks.
	for _, x in { 0.22, 0.78 } do
		local cheek = roundFrame(gui, "Cheek", UDim2.fromScale(0.13, 0.1), UDim2.fromScale(x, 0.62), Color3.fromRGB(255, 130, 165))
		cheek.BackgroundTransparency = 0.45
	end

	-- A small, gentle smile: the bottom of a ring, shown through a clipping window.
	local mouthWindow = Instance.new("Frame")
	mouthWindow.Name = "Mouth"
	mouthWindow.AnchorPoint = Vector2.new(0.5, 0)
	mouthWindow.Position = UDim2.fromScale(0.5, 0.6)
	mouthWindow.Size = UDim2.fromOffset(42, 15)
	mouthWindow.BackgroundTransparency = 1
	mouthWindow.ClipsDescendants = true
	mouthWindow.Parent = gui

	local ring = Instance.new("Frame")
	ring.Name = "Smile"
	ring.AnchorPoint = Vector2.new(0.5, 1)
	-- 4 pixels up from the bottom, because the outline is drawn outside the
	-- ring and would otherwise be cut off by the window.
	ring.Position = UDim2.new(0.5, 0, 1, -4)
	ring.Size = UDim2.fromOffset(32, 32)
	ring.BackgroundTransparency = 1
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring
	ring.Parent = mouthWindow

	card.Parent = model
end

-- Finds a point on the front of an oval (ellipsoid) surface.
-- `center` is the oval's center, `size` its full size; x/y are offsets from
-- the center. Front is -Z.
local function frontOf(center: Vector3, size: Vector3, x: number, y: number, pushOut: number): Vector3
	local a, b, c = size.X / 2, size.Y / 2, size.Z / 2
	local inside = 1 - (x / a) ^ 2 - (y / b) ^ 2
	local z = -c * math.sqrt(math.max(inside, 0))
	return center + Vector3.new(x, y, z - pushOut)
end

-- Builds the blob and attaches it to the character.
function BlobCharacter.apply(character: Model, color: Color3)
	HitGroups.setup()

	local foundHumanoid = character:WaitForChild("Humanoid", 10)
	local foundRoot = character:WaitForChild("HumanoidRootPart", 10)
	if not foundHumanoid or not foundHumanoid:IsA("Humanoid") or not foundRoot or not foundRoot:IsA("BasePart") then
		warn(`BlobCharacter: {character.Name} has no Humanoid or HumanoidRootPart`)
		return
	end
	local humanoid = foundHumanoid :: Humanoid
	local root = foundRoot :: BasePart

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

	-- 2. Build the blob. All positions are relative to the root part;
	-- `g` is the floor height under the character.
	local model = Instance.new("Model")
	model.Name = BLOB_MODEL_NAME
	model:SetAttribute(BLOB_ATTRIBUTE, true)

	local g = -BlobCharacter.groundOffset(humanoid, root)
	model:SetAttribute(GROUND_ATTRIBUTE, g)
	model:SetAttribute(HEIGHT_ATTRIBUTE, BLOB_HEIGHT)

	-- A darker, richer bottom fading to a lighter top, like real jelly.
	local deep = shade(color, 1.2, 0.78)
	local mid = color:Lerp(deep, 0.45)
	local light = shade(color, 0.75, 1.08)
	local gloss = shade(color, 0.45, 1.1)

	-- Base puddle: wide and flat, sinking a little into the floor.
	makePiece(model, root, {
		name = "Base",
		size = Vector3.new(5.3, 1.5, 5.1),
		offset = Vector3.new(0, g + 0.62, 0),
		color = deep,
		wobble = 0.5,
		shadow = true,
	})

	-- Main dome.
	local domeSize = Vector3.new(4.3, 3.5, 4.1)
	local domeCenter = Vector3.new(0, g + 1.95, 0)
	local dome = makePiece(model, root, {
		name = "Dome",
		size = domeSize,
		offset = domeCenter,
		color = color,
		shadow = true,
	})
	dome.Reflectance = 0.05

	-- Melty bulges around the bottom, so the outline is lumpy, not round.
	makePiece(model, root, {
		name = "LobeLeft",
		size = Vector3.new(2.0, 1.8, 2.1),
		offset = Vector3.new(-2.0, g + 0.95, 0.35),
		color = mid,
		wobble = 1,
	})
	makePiece(model, root, {
		name = "LobeRight",
		size = Vector3.new(1.8, 1.6, 1.9),
		offset = Vector3.new(2.05, g + 0.85, -0.3),
		color = mid,
		wobble = 1.2,
	})
	makePiece(model, root, {
		name = "LobeBack",
		size = Vector3.new(2.6, 1.7, 2.0),
		offset = Vector3.new(0.3, g + 0.9, 1.9),
		color = mid,
		wobble = 0.8,
	})
	makePiece(model, root, {
		name = "Drip",
		size = Vector3.new(1.3, 0.75, 1.3),
		offset = Vector3.new(-1.35, g + 0.3, -2.05),
		color = deep,
		wobble = 1.4,
	})

	-- A soft off-centre dollop on top, plus a smaller one beside it.
	makePiece(model, root, {
		name = "Dollop",
		size = Vector3.new(1.9, 1.4, 1.8),
		offset = Vector3.new(0.6, g + 3.45, 0.25),
		color = light,
		wobble = 1.6,
	})
	makePiece(model, root, {
		name = "DollopSmall",
		size = Vector3.new(1.2, 0.95, 1.15),
		offset = Vector3.new(-0.75, g + 3.35, 0.45),
		color = light,
		wobble = 2,
	})

	-- See-through glossy layer over the dome: this is what makes it look like jelly.
	local shellSize = domeSize * 1.06
	makePiece(model, root, {
		name = "Shell",
		size = shellSize,
		offset = domeCenter,
		color = gloss,
		transparency = 0.6,
		material = Enum.Material.Glass,
	})

	-- A soft white shine on the upper left of the dome.
	makePiece(model, root, {
		name = "Shine",
		size = Vector3.new(0.95, 0.55, 0.35),
		offset = frontOf(domeCenter, shellSize, -1.05, 0.95, -0.05),
		color = Color3.new(1, 1, 1),
		transparency = 0.35,
		wobble = 0.3,
	})

	-- The face sits just in front of the glossy shell.
	buildFace(model, root, frontOf(domeCenter, shellSize, 0, 0.3, 0.04))

	-- The hitbox bullets hit (see Shared/Combat/HitGroups). Invisible and
	-- not animated, so hits are fair no matter how much the blob wobbles.
	-- It's named "Body" so WeaponService can spot headshots on the top of it.
	local hitboxSize = MovementConfig.BlobHitboxSize
	local hitbox = Instance.new("Part")
	hitbox.Name = "Body"
	hitbox.Size = hitboxSize
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.CanQuery = true
	hitbox.CanTouch = false
	hitbox.Massless = true
	hitbox.CastShadow = false
	hitbox:SetAttribute(BLOB_ATTRIBUTE, true)
	local hitboxOffset = Vector3.new(0, g + hitboxSize.Y / 2, 0)
	hitbox.CFrame = root.CFrame * CFrame.new(hitboxOffset)
	local hitboxWeld = Instance.new("WeldConstraint")
	hitboxWeld.Part0 = root
	hitboxWeld.Part1 = hitbox
	hitboxWeld.Parent = hitbox
	hitbox.Parent = model

	-- A small name tag above the blob: the name, then the player's LEVEL and
	-- WIN STREAK (matches won in a row). It's sized in studs, so it shrinks
	-- with distance like a real object (Roblox's own name tag, which stays
	-- the same size on screen, is switched off in SlimeRig). You see your
	-- own tag in the lobby, but not in first person (matches, practice).
	local owner = Players:GetPlayerFromCharacter(character)
	local nameTag = Instance.new("BillboardGui")
	nameTag.Name = "NameTag"
	nameTag.Size = UDim2.fromScale(5, 1.65)
	nameTag.StudsOffset = Vector3.new(0, hitboxSize.Y / 2 + 1.35, 0)
	nameTag.MaxDistance = 60
	nameTag.LightInfluence = 0
	nameTag.PlayerToHideFrom = owner
	nameTag.Parent = hitbox
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.fromScale(1, 0.52)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text = if owner then owner.DisplayName elseif humanoid.DisplayName ~= "" then humanoid.DisplayName else character.Name
	nameLabel.Parent = nameTag

	-- The badges under the name (sci-fi pills).
	local badges = Instance.new("Frame")
	badges.Name = "Badges"
	badges.BackgroundTransparency = 1
	badges.Position = UDim2.fromScale(0, 0.58)
	badges.Size = UDim2.fromScale(1, 0.4)
	badges.Parent = nameTag
	local badgeLayout = Instance.new("UIListLayout")
	badgeLayout.FillDirection = Enum.FillDirection.Horizontal
	badgeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	badgeLayout.Padding = UDim.new(0.03, 0)
	badgeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	badgeLayout.Parent = badges
	local function pill(name: string, order: number, width: number, color: Color3): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.LayoutOrder = order
		label.Size = UDim2.fromScale(width, 1)
		label.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
		label.BackgroundTransparency = 0.2
		label.Font = Enum.Font.Michroma
		label.TextScaled = true
		label.TextColor3 = color
		label.Parent = badges
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = label
		local edge = Instance.new("UIStroke")
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Color = color
		edge.Thickness = 1.5
		edge.Parent = label
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0.14, 0)
		padding.PaddingBottom = UDim.new(0.14, 0)
		padding.PaddingLeft = UDim.new(0.06, 0)
		padding.PaddingRight = UDim.new(0.06, 0)
		padding.Parent = label
		return label
	end
	local levelPill = pill("Level", 1, 0.3, Color3.fromRGB(90, 220, 255))
	local streakPill = pill("Streak", 2, 0.52, Color3.fromRGB(255, 170, 60))

	if owner then
		local function refreshBadges()
			local xp = owner:GetAttribute("XP")
			local level = Progression.levelFromXp(if typeof(xp) == "number" then xp else 0)
			levelPill.Text = `LV {level}`
			local streak = owner:GetAttribute("WinStreak")
			local wins = if typeof(streak) == "number" then streak else 0
			streakPill.Text = `{wins} WIN STREAK`
			-- A streak glows brighter the longer it gets.
			streakPill.TextColor3 = if wins >= 3 then Color3.fromRGB(255, 120, 60)
				elseif wins >= 1 then Color3.fromRGB(255, 190, 70)
				else Color3.fromRGB(150, 160, 190)
		end
		local function refreshOwnView()
			-- Seen by yourself in the lobby (third person), hidden in first person.
			local status = owner:GetAttribute("MatchStatus")
			nameTag.PlayerToHideFrom = if status == "InMatch" or status == "Practice" then owner else nil
		end
		local connections = {
			owner:GetAttributeChangedSignal("XP"):Connect(refreshBadges),
			owner:GetAttributeChangedSignal("WinStreak"):Connect(refreshBadges),
			owner:GetAttributeChangedSignal("MatchStatus"):Connect(refreshOwnView),
		}
		-- Stop listening once this character is gone (respawning destroys it).
		nameTag.Destroying:Connect(function()
			for _, connection in connections do
				connection:Disconnect()
			end
		end)
		refreshBadges()
		refreshOwnView()
	else
		-- Practice bots.
		levelPill.Text = "BOT"
		levelPill.TextColor3 = Color3.fromRGB(150, 160, 190)
		streakPill.Visible = false
	end

	model.Parent = character
	-- The client animator finds blobs by this tag.
	CollectionService:AddTag(model, BLOB_TAG)
end

return BlobCharacter

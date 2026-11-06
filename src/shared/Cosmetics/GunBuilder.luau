--!strict
--[[
	GunBuilder: builds the chunky, toy-like gun models (one design per
	weapon). Used everywhere a gun appears: in a slime's hand and in first
	person (server/Components/GunModel), the weapons room displays, and the
	shop's 3D pictures. So a gun always looks the same.

	Every gun is built from colour-blocked pieces with a role:
	  Body    the main colour (receiver, handguard, stock)
	  Trim    the second colour (grip, magazine, sights, caps)
	  Accent  small bright details (stripes, panels, shells, lens)
	  Metal   dark parts (barrel, rails, trigger guard)
	Weapon skins (Cosmetics/WeaponSkins) repaint the pieces by role, and the
	upgrade colour (Cosmetics/GunUpgrade) paints the part called "Body".

	Designs are drawn with the hand at the origin (the top of the grip),
	pointing along -Z, then scaled so each gun's length matches
	WeaponConfig's GunLength. Each gun has a "Muzzle" attachment at the tip,
	where shots and tracers start.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("WeaponConfig"))

type WeaponStats = WeaponConfig.WeaponStats
export type Role = "Body" | "Trim" | "Accent" | "Metal"
type Shape = "Block" | "CylZ" | "CylY" | "CylX" | "Ball"
type Spec = {
	name: string,
	role: Role,
	shape: Shape,
	size: Vector3, -- for cylinders: (length, diameter, diameter)
	pos: Vector3,
	tilt: number?, -- degrees around X (grips lean back, magazines lean forward)
	muzzle: boolean?,
}

export type Options = {
	anchored: boolean?, -- true for displays and pictures
	shadows: boolean?,
	scale: number?, -- extra size on top of the usual one
}

local KEEP_VISIBLE_ATTRIBUTE = "IsBlobPart" -- the blob hides other parts added to a character
local ROLE_ATTRIBUTE = "GunRole"
local DEFAULT_COLOR_ATTRIBUTE = "DefaultColor"
local METAL = Color3.fromRGB(58, 62, 76)

-- Each gun's own colours (its body colour comes from WeaponConfig.GunColor).
local PALETTES: { [string]: { trim: Color3, accent: Color3 } } = {
	Rifle = { trim = Color3.fromRGB(255, 150, 60), accent = Color3.fromRGB(255, 215, 70) },
	SMG = { trim = Color3.fromRGB(90, 225, 230), accent = Color3.fromRGB(255, 120, 170) },
	Shotgun = { trim = Color3.fromRGB(90, 170, 255), accent = Color3.fromRGB(255, 215, 70) },
	Sniper = { trim = Color3.fromRGB(255, 160, 60), accent = Color3.fromRGB(180, 110, 255) },
	Pistol = { trim = Color3.fromRGB(90, 150, 255), accent = Color3.fromRGB(255, 120, 170) },
	Marksman = { trim = Color3.fromRGB(255, 200, 80), accent = Color3.fromRGB(90, 200, 230) },
	Burst = { trim = Color3.fromRGB(110, 110, 255), accent = Color3.fromRGB(180, 240, 80) },
	Launcher = { trim = Color3.fromRGB(255, 140, 40), accent = Color3.fromRGB(190, 255, 110) },
}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function block(name: string, role: Role, size: Vector3, pos: Vector3, tilt: number?): Spec
	return { name = name, role = role, shape = "Block", size = size, pos = pos, tilt = tilt }
end

-- A cylinder lying along the gun (front to back).
local function tube(name: string, role: Role, diameter: number, length: number, pos: Vector3, muzzle: boolean?): Spec
	return { name = name, role = role, shape = "CylZ", size = v(length, diameter, diameter), pos = pos, muzzle = muzzle }
end

-- Shared pieces most guns have.
local function gripAndTrigger(specs: { Spec }, gripZ: number, guardZ: number)
	table.insert(specs, block("Grip", "Trim", v(0.28, 0.56, 0.32), v(0, -0.28, gripZ), -18))
	table.insert(specs, block("TriggerGuard", "Metal", v(0.08, 0.06, 0.42), v(0, -0.19, guardZ)))
	table.insert(specs, block("Trigger", "Metal", v(0.06, 0.14, 0.06), v(0, -0.09, guardZ + 0.02)))
end

local DESIGNS: { [string]: () -> { Spec } } = {}

DESIGNS.Rifle = function()
	local specs = {
		block("Body", "Body", v(0.42, 0.5, 1.2), v(0, 0.18, -0.35)),
		block("Handguard", "Body", v(0.38, 0.38, 0.95), v(0, 0.14, -1.42)),
		block("HandguardBand", "Accent", v(0.4, 0.1, 0.95), v(0, 0, -1.42)),
		tube("Barrel", "Metal", 0.15, 0.6, v(0, 0.18, -2.17)),
		tube("Muzzle", "Trim", 0.24, 0.24, v(0, 0.18, -2.55), true),
		block("Rail", "Metal", v(0.16, 0.07, 1.6), v(0, 0.465, -0.75)),
		block("RearSight", "Trim", v(0.14, 0.2, 0.2), v(0, 0.6, -0.05)),
		block("FrontSight", "Trim", v(0.1, 0.24, 0.12), v(0, 0.43, -1.75)),
		block("Magazine", "Trim", v(0.26, 0.62, 0.34), v(0, -0.33, -0.62), 12),
		block("Stock", "Body", v(0.34, 0.4, 0.75), v(0, 0.1, 0.62)),
		block("StockPad", "Trim", v(0.36, 0.5, 0.14), v(0, 0.06, 1.04)),
		block("SidePanel", "Accent", v(0.44, 0.14, 0.4), v(0, 0.26, -0.45)),
	}
	gripAndTrigger(specs, 0.18, -0.12)
	return specs
end

DESIGNS.SMG = function()
	local specs = {
		block("Body", "Body", v(0.42, 0.52, 1.0), v(0, 0.16, -0.25)),
		tube("Shroud", "Body", 0.32, 0.5, v(0, 0.14, -0.98)),
		tube("ShroudRing", "Accent", 0.36, 0.1, v(0, 0.14, -0.8)),
		tube("Barrel", "Metal", 0.14, 0.36, v(0, 0.14, -1.4)),
		tube("Muzzle", "Trim", 0.22, 0.18, v(0, 0.14, -1.66), true),
		block("Magazine", "Trim", v(0.24, 0.85, 0.28), v(0, -0.5, -0.45)),
		block("Foregrip", "Trim", v(0.2, 0.45, 0.22), v(0, -0.2, -0.88)),
		block("Rail", "Metal", v(0.16, 0.07, 0.9), v(0, 0.455, -0.3)),
		block("Sight", "Accent", v(0.22, 0.2, 0.26), v(0, 0.58, -0.2)),
		block("StockArm", "Metal", v(0.08, 0.08, 0.7), v(0.17, 0.12, 0.55)),
		block("StockArmLow", "Metal", v(0.08, 0.08, 0.7), v(0.17, -0.06, 0.55)),
		block("StockPad", "Trim", v(0.1, 0.42, 0.12), v(0.17, 0.03, 0.92)),
		block("SidePanel", "Accent", v(0.44, 0.1, 0.55), v(0, 0.3, -0.25)),
	}
	gripAndTrigger(specs, 0.16, -0.1)
	return specs
end

DESIGNS.Shotgun = function()
	local specs = {
		block("Body", "Body", v(0.44, 0.52, 1.0), v(0, 0.16, -0.2)),
		tube("Barrel", "Metal", 0.2, 1.6, v(0, 0.3, -1.5)),
		tube("Tube", "Metal", 0.17, 1.2, v(0, 0.06, -1.3)),
		block("Pump", "Trim", v(0.34, 0.32, 0.62), v(0, 0.06, -1.25)),
		block("PumpRing", "Accent", v(0.36, 0.34, 0.07), v(0, 0.06, -1.05)),
		block("PumpRing", "Accent", v(0.36, 0.34, 0.07), v(0, 0.06, -1.45)),
		tube("Muzzle", "Trim", 0.28, 0.18, v(0, 0.3, -2.32), true),
		{ name = "Bead", role = "Accent", shape = "Ball", size = v(0.09, 0.09, 0.09), pos = v(0, 0.43, -2.28) } :: Spec,
		block("Stock", "Body", v(0.36, 0.46, 0.9), v(0, 0.06, 0.72), -5),
		block("StockPad", "Trim", v(0.38, 0.56, 0.14), v(0, 0.03, 1.2)),
	}
	for index, z in { -0.45, -0.3, -0.15 } do
		table.insert(specs, { name = `Shell{index}`, role = "Accent", shape = "CylY", size = v(0.3, 0.12, 0.12), pos = v(0.25, 0.16, z) } :: Spec)
	end
	gripAndTrigger(specs, 0.2, -0.05)
	return specs
end

DESIGNS.Sniper = function()
	local specs = {
		block("Body", "Body", v(0.4, 0.46, 1.2), v(0, 0.16, -0.3)),
		tube("Barrel", "Metal", 0.16, 1.9, v(0, 0.16, -1.85)),
		{ name = "Muzzle", role = "Trim", shape = "Block", size = v(0.3, 0.22, 0.32), pos = v(0, 0.16, -2.9), muzzle = true } :: Spec,
		tube("Scope", "Metal", 0.26, 1.0, v(0, 0.62, -0.4)),
		tube("ScopeFront", "Trim", 0.34, 0.18, v(0, 0.62, -0.95)),
		tube("ScopeBack", "Trim", 0.32, 0.16, v(0, 0.62, 0.14)),
		tube("Lens", "Accent", 0.25, 0.03, v(0, 0.62, -1.05)),
		block("Mount", "Metal", v(0.1, 0.2, 0.1), v(0, 0.42, -0.7)),
		block("Mount", "Metal", v(0.1, 0.2, 0.1), v(0, 0.42, -0.1)),
		{ name = "Bolt", role = "Metal", shape = "CylX", size = v(0.32, 0.08, 0.08), pos = v(0.3, 0.24, 0.05) } :: Spec,
		{ name = "BoltKnob", role = "Trim", shape = "Ball", size = v(0.15, 0.15, 0.15), pos = v(0.47, 0.24, 0.05) } :: Spec,
		block("Magazine", "Trim", v(0.22, 0.32, 0.36), v(0, -0.18, -0.55)),
		block("Stock", "Body", v(0.32, 0.5, 1.0), v(0, 0.02, 0.82)),
		block("CheekRest", "Accent", v(0.3, 0.12, 0.5), v(0, 0.3, 0.82)),
		block("StockPad", "Trim", v(0.34, 0.58, 0.14), v(0, 0, 1.36)),
	}
	gripAndTrigger(specs, 0.2, -0.05)
	return specs
end

DESIGNS.Pistol = function()
	return {
		block("Body", "Body", v(0.3, 0.32, 1.0), v(0, 0.24, -0.4)),
		block("Frame", "Trim", v(0.28, 0.16, 0.8), v(0, 0.03, -0.35)),
		block("SlideRidge", "Accent", v(0.32, 0.26, 0.04), v(0, 0.24, 0)),
		block("SlideRidge", "Accent", v(0.32, 0.26, 0.04), v(0, 0.24, -0.08)),
		tube("Muzzle", "Metal", 0.13, 0.12, v(0, 0.26, -0.95), true),
		block("FrontSight", "Metal", v(0.06, 0.08, 0.06), v(0, 0.43, -0.82)),
		block("RearSight", "Metal", v(0.14, 0.08, 0.06), v(0, 0.43, 0.04)),
		block("Grip", "Trim", v(0.28, 0.62, 0.34), v(0, -0.28, 0.02), -14),
		block("GripPanel", "Accent", v(0.3, 0.4, 0.22), v(0, -0.26, 0.03), -14),
		block("TriggerGuard", "Metal", v(0.07, 0.06, 0.32), v(0, -0.12, -0.25)),
		block("Trigger", "Metal", v(0.05, 0.12, 0.05), v(0, -0.04, -0.2)),
	}
end

DESIGNS.Marksman = function()
	local specs = {
		block("Body", "Body", v(0.4, 0.48, 1.25), v(0, 0.17, -0.35)),
		block("Handguard", "Body", v(0.34, 0.34, 1.0), v(0, 0.14, -1.5)),
		tube("Barrel", "Metal", 0.14, 0.8, v(0, 0.16, -2.4)),
		tube("Muzzle", "Trim", 0.22, 0.22, v(0, 0.16, -2.9), true),
		tube("Scope", "Metal", 0.22, 0.7, v(0, 0.58, -0.4)),
		tube("ScopeFront", "Trim", 0.28, 0.12, v(0, 0.58, -0.78)),
		tube("ScopeBack", "Trim", 0.26, 0.1, v(0, 0.58, -0.02)),
		tube("Lens", "Accent", 0.2, 0.03, v(0, 0.58, -0.85)),
		block("Mount", "Metal", v(0.08, 0.16, 0.08), v(0, 0.42, -0.6)),
		block("Mount", "Metal", v(0.08, 0.16, 0.08), v(0, 0.42, -0.2)),
		block("Magazine", "Trim", v(0.24, 0.48, 0.32), v(0, -0.3, -0.6), 8),
		block("Stock", "Body", v(0.32, 0.44, 0.85), v(0, 0.08, 0.7)),
		block("StockPad", "Trim", v(0.34, 0.52, 0.14), v(0, 0.05, 1.18)),
	}
	for _, z in { -1.25, -1.5, -1.75 } do
		table.insert(specs, block("Vent", "Accent", v(0.36, 0.08, 0.14), v(0, 0.14, z)))
	end
	gripAndTrigger(specs, 0.18, -0.12)
	return specs
end

DESIGNS.Burst = function()
	-- A bullpup: the magazine sits behind the grip.
	local specs = {
		block("Body", "Body", v(0.42, 0.55, 1.6), v(0, 0.15, 0.15)),
		block("Handle", "Trim", v(0.14, 0.12, 0.8), v(0, 0.66, 0.15)),
		block("HandlePost", "Trim", v(0.12, 0.2, 0.1), v(0, 0.52, -0.2)),
		block("HandlePost", "Trim", v(0.12, 0.2, 0.1), v(0, 0.52, 0.5)),
		tube("Barrel", "Metal", 0.15, 0.6, v(0, 0.2, -0.95)),
		tube("Muzzle", "Trim", 0.24, 0.2, v(0, 0.2, -1.35), true),
		block("Magazine", "Trim", v(0.26, 0.55, 0.34), v(0, -0.33, 0.7)),
		block("ButtPad", "Trim", v(0.44, 0.6, 0.1), v(0, 0.12, 1.0)),
		block("Stripe", "Accent", v(0.44, 0.09, 0.45), v(0, 0.02, -0.35)),
		block("Stripe", "Accent", v(0.44, 0.09, 0.4), v(0, 0.3, 0.55)),
	}
	gripAndTrigger(specs, 0.15, -0.12)
	return specs
end

DESIGNS.Launcher = function()
	-- A chunky toy launcher: boxy body, big caps and a slime canister.
	local specs = {
		block("Body", "Body", v(0.62, 0.66, 1.7), v(0, 0.38, -0.55)),
		block("FrontCap", "Trim", v(0.74, 0.78, 0.3), v(0, 0.38, -1.5)),
		tube("Muzzle", "Metal", 0.46, 0.06, v(0, 0.38, -1.67), true),
		block("RearCap", "Trim", v(0.72, 0.76, 0.26), v(0, 0.38, 0.38)),
		block("Band", "Accent", v(0.66, 0.7, 0.16), v(0, 0.38, -0.55)),
		block("Foregrip", "Trim", v(0.24, 0.45, 0.26), v(0, -0.1, -0.95)),
		block("Sight", "Metal", v(0.12, 0.32, 0.12), v(0, 0.86, -0.95)),
		tube("SightRing", "Accent", 0.26, 0.05, v(0, 0.98, -0.95)),
		{ name = "Canister", role = "Accent", shape = "Ball", size = v(0.42, 0.42, 0.42), pos = v(0.4, 0.38, -0.2) } :: Spec,
	}
	gripAndTrigger(specs, 0.02, -0.2)
	return specs
end

-- How long a design is from back to front (for scaling to GunLength).
local function lengthOf(specs: { Spec }): number
	local front, back = 0, 0
	for _, spec in specs do
		local half = if spec.shape == "CylZ" then spec.size.X / 2 else spec.size.Z / 2
		front = math.min(front, spec.pos.Z - half)
		back = math.max(back, spec.pos.Z + half)
	end
	return back - front
end

local function orientation(shape: Shape): CFrame
	if shape == "CylZ" then
		return CFrame.Angles(0, math.rad(90), 0) -- the cylinder's axis (X) points forward (-Z)
	elseif shape == "CylY" then
		return CFrame.Angles(0, 0, math.rad(90))
	end
	return CFrame.new()
end

--[[
	Builds the gun for `stats`, with the hand (the top of the grip) at
	`origin`, pointing along origin's -Z. Returns the model; its
	PrimaryPart is the part called "Body".
]]
local function build(stats: WeaponStats, origin: CFrame, options: Options?): Model
	local design = DESIGNS[stats.Id] or DESIGNS.Rifle
	local specs = design()
	local palette = PALETTES[stats.Id] or PALETTES.Rifle
	local scale = math.clamp((stats.GunLength + 0.5) / lengthOf(specs), 0.7, 1.4) * (if options and options.scale then options.scale else 1)
	local anchored = options ~= nil and options.anchored == true
	local shadows = options ~= nil and options.shadows == true

	local model = Instance.new("Model")
	model.Name = "Gun"
	for _, spec in specs do
		local part = Instance.new("Part")
		part.Name = spec.name
		if spec.shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif spec.shape ~= "Block" then
			part.Shape = Enum.PartType.Cylinder
		end
		part.Size = spec.size * scale
		local color = if spec.role == "Body"
			then stats.GunColor
			elseif spec.role == "Trim" then palette.trim
			elseif spec.role == "Accent" then palette.accent
			else METAL
		part.Color = color
		part.Material = if spec.role == "Metal" then Enum.Material.Metal else Enum.Material.SmoothPlastic
		part.Reflectance = if spec.role == "Metal" then 0.05 else 0.04
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = anchored
		part.CanCollide = false
		part.CanQuery = false -- bullets fly through guns
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = shadows
		part:SetAttribute(KEEP_VISIBLE_ATTRIBUTE, true)
		part:SetAttribute(ROLE_ATTRIBUTE, spec.role)
		part:SetAttribute(DEFAULT_COLOR_ATTRIBUTE, color)
		local tilt = CFrame.Angles(math.rad(spec.tilt or 0), 0, 0)
		part.CFrame = origin * CFrame.new(spec.pos * scale) * tilt * orientation(spec.shape)
		if spec.muzzle then
			-- Where shots and tracers start: the very front of this piece.
			local muzzle = Instance.new("Attachment")
			muzzle.Name = "Muzzle"
			muzzle.Position = if spec.shape == "CylZ" then Vector3.new(part.Size.X / 2, 0, 0) else Vector3.new(0, 0, -part.Size.Z / 2)
			muzzle.Parent = part
		end
		part.Parent = model
	end
	model.PrimaryPart = model:FindFirstChild("Body") :: BasePart
	return model
end

local GunBuilder = {}
GunBuilder.ROLE_ATTRIBUTE = ROLE_ATTRIBUTE
GunBuilder.DEFAULT_COLOR_ATTRIBUTE = DEFAULT_COLOR_ATTRIBUTE
GunBuilder.build = build

return GunBuilder

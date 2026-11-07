--!strict
--[[
	ShopProps: the treasure pieces of the lobby's ROBUX SHOP room
	(LobbyBuilder puts them together). Everything is made of plain parts:

	  giantCoin     a huge gold coin with a slime face on both sides
	  dais          a round stand with a glowing ring and a soft beam of light
	  vaultDoor     a big round bank-vault door with a wheel, bolts and hinges
	  coinPile      a heap of gold with loose coins on top
	  goldBars      a little pyramid of gold bars
	  chest         an open treasure chest full of gold
	  giftBox       a wrapped present with a bow
	  pouch, jar, bucket, safe   the four coin packs, smallest to biggest
	  displayStand  a pedestal with a lit glass case and a price tag

	Decorations never collide (only pedestals and big furniture do), so a
	crowd can always walk around them.

	See-through pieces (the glass cases, the jar) are see-through plastic,
	not Roblox's Glass material: Glass hides everything see-through behind
	it (sparkles, the jar's glass...). `base` CFrames sit on the floor and
	an item's front looks along the base's LookVector.
]]

local MapKit = require(script.Parent.MapKit)
local LobbyProps = require(script.Parent.LobbyProps)

local ShopProps = {}

local GOLD = Color3.fromRGB(255, 196, 52)
local GOLD_DARK = Color3.fromRGB(214, 146, 30)
local GOLD_LIGHT = Color3.fromRGB(255, 230, 128)
local STEEL = Color3.fromRGB(150, 156, 168)
local STEEL_DARK = Color3.fromRGB(70, 74, 86)
local FACE_INK = Color3.fromRGB(125, 72, 12) -- the coin face's dark gold lines
local GLASS = Color3.fromRGB(205, 235, 255)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local PRICE_GREEN = Color3.fromRGB(40, 190, 100)

ShopProps.GOLD = GOLD
ShopProps.GOLD_DARK = GOLD_DARK
ShopProps.GOLD_LIGHT = GOLD_LIGHT

-- Roblox's built-in sparkle picture (always available, nothing to upload).
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

-- A decoration: anchored, no collisions, no shadow; bullets and clicks pass through.
local function deco(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	return MapKit.part(parent, name, size, cframe, color, { material = material or Enum.Material.SmoothPlastic, collide = false, shadow = false })
end

-- A cylinder whose round faces look along `cframe`'s X axis.
local function disc(parent: Instance, name: string, thickness: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = deco(parent, name, Vector3.new(thickness, diameter, diameter), cframe, color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- An upright cylinder standing on `bottom`.
local function column(parent: Instance, name: string, height: number, diameter: number, bottom: CFrame, color: Color3, material: Enum.Material?): Part
	return disc(parent, name, height, diameter, bottom * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), color, material)
end

-- A squashed ball (an ellipsoid): a block with a sphere mesh.
local function blob(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = deco(parent, name, size, cframe, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Little twinkles drifting off a part.
local function sparkles(part: BasePart, color: Color3, rate: number, size: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(0.4, 1.4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Parent = part
end
ShopProps.sparkles = sparkles

-- One loose gold coin, lying (almost) flat and tipped by up to `maxTilt` degrees.
local function looseCoin(parent: Instance, position: Vector3, diameter: number, random: Random, maxTilt: number)
	local tilt = CFrame.Angles(math.rad(random:NextNumber(-maxTilt, maxTilt)), random:NextNumber(0, math.pi * 2), math.rad(random:NextNumber(-maxTilt, maxTilt)))
	disc(parent, "Coin", diameter * 0.14, diameter, CFrame.new(position) * tilt * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal)
end

--[[
	A giant gold coin standing up at `center` (its faces look along the
	centre's LookVector and back), with a glowing rim, a raised middle, a
	slime face on both sides, sparkles and a warm light. Its pivot is the
	middle, standing straight up, so the lobby can spin it.
]]
function ShopProps.giantCoin(parent: Instance, center: CFrame, diameter: number): Model
	local model = Instance.new("Model")
	model.Name = "GiantCoin"
	local d = diameter
	local thick = d * 0.11
	-- A cylinder's round faces look along its X axis: turn X onto the look direction.
	local facing = center * CFrame.Angles(0, math.rad(90), 0)
	local body = disc(model, "Coin", thick, d, facing, GOLD, Enum.Material.Metal)
	body.Reflectance = 0.08
	disc(model, "CoinRim", thick * 0.7, d * 1.06, facing, GOLD_LIGHT, Enum.Material.Neon)
	disc(model, "CoinRing", thick * 1.1, d * 0.8, facing, GOLD_DARK, Enum.Material.Metal)
	local faceThickness = thick * 1.18
	disc(model, "CoinFace", faceThickness, d * 0.7, facing, GOLD, Enum.Material.Metal).Reflectance = 0.08
	-- A happy slime face on both sides.
	for _, side in { -1, 1 } do
		local x = side * faceThickness / 2
		for _, across in { -1, 1 } do
			blob(model, "CoinEye", Vector3.new(0.05, 0.14, 0.09) * d, facing * CFrame.new(x, 0.07 * d, across * 0.12 * d), FACE_INK, Enum.Material.Metal)
			blob(model, "CoinEyeShine", Vector3.new(0.06, 0.04, 0.03) * d, facing * CFrame.new(x + side * 0.004 * d, 0.1 * d, across * 0.12 * d + 0.015 * d), GOLD_LIGHT, Enum.Material.Neon)
			blob(model, "CoinCheek", Vector3.new(0.03, 0.05, 0.1) * d, facing * CFrame.new(x, -0.03 * d, across * 0.23 * d), Color3.fromRGB(255, 150, 90), Enum.Material.SmoothPlastic).Transparency = 0.25
		end
		for i = 0, 4 do
			local angle = math.rad(205 + i * 32.5)
			local y = -0.06 * d + math.sin(angle) * 0.09 * d
			local z = math.cos(angle) * 0.09 * d
			blob(model, "CoinSmile", Vector3.new(0.05, 0.045, 0.045) * d, facing * CFrame.new(x, y, z), FACE_INK, Enum.Material.Metal)
		end
	end
	LobbyProps.light(body, GOLD_LIGHT, 20, 2)
	sparkles(body, GOLD_LIGHT, 10, d * 0.06)
	model.WorldPivot = CFrame.new(center.Position)
	model.Parent = parent
	return model
end

--[[
	A round stand on the floor at `base`: a dark step with a glowing gold
	ring, a top that lights up and a soft beam of light rising from it.
	Returns the height of its top and the step (for a prompt).
]]
function ShopProps.dais(parent: Instance, base: Vector3, diameter: number, beamHeight: number): (number, BasePart)
	local bottom = CFrame.new(base)
	local step = column(parent, "Dais", 1.2, diameter, bottom, LobbyProps.METAL_DARK, Enum.Material.DiamondPlate)
	step.CanCollide = true
	step.CanQuery = true
	column(parent, "DaisRing", 0.3, diameter + 0.4, bottom * CFrame.new(0, 0.45, 0), GOLD, Enum.Material.Neon)
	local top = column(parent, "DaisTop", 0.6, diameter * 0.72, bottom * CFrame.new(0, 1.2, 0), LobbyProps.METAL_DARK, Enum.Material.DiamondPlate)
	top.CanCollide = true
	top.CanQuery = true
	column(parent, "DaisRing", 0.2, diameter * 0.72 + 0.3, bottom * CFrame.new(0, 1.45, 0), GOLD, Enum.Material.Neon)
	column(parent, "DaisGlow", 0.08, diameter * 0.6, bottom * CFrame.new(0, 1.8, 0), GOLD_LIGHT, Enum.Material.Neon)
	local beam = column(parent, "DaisBeam", beamHeight, diameter * 0.45, bottom * CFrame.new(0, 1.88, 0), GOLD_LIGHT, Enum.Material.Neon)
	beam.Transparency = 0.9
	LobbyProps.light(top, GOLD, 24, 1.6)
	return 1.88, step
end

--[[
	A round bank-vault door set into a wall. `center` sits on the wall's
	surface in the middle of the door, looking out into the room.
]]
function ShopProps.vaultDoor(parent: Instance, center: CFrame, diameter: number): Model
	local model = Instance.new("Model")
	model.Name = "VaultDoor"
	local d = diameter
	-- Here X points out of the wall, Y up and Z along the wall.
	local axis = center * CFrame.Angles(0, math.rad(90), 0)
	local function out(depth: number): CFrame
		return axis * CFrame.new(depth, 0, 0)
	end

	-- A square steel frame on the wall with glowing gold edges.
	deco(model, "VaultFrame", Vector3.new(0.6, d + 4, d + 4), out(0.3), STEEL_DARK, Enum.Material.DiamondPlate)
	for _, sign in { -1, 1 } do
		deco(model, "VaultFrameGlow", Vector3.new(0.7, 0.35, d + 4.4), out(0.35) * CFrame.new(0, sign * (d / 2 + 2.05), 0), GOLD, Enum.Material.Neon)
		deco(model, "VaultFrameGlow", Vector3.new(0.7, d + 4.4, 0.35), out(0.35) * CFrame.new(0, 0, sign * (d / 2 + 2.05)), GOLD, Enum.Material.Neon)
	end
	-- The ring, the glowing seam and the door itself (each a step further out).
	disc(model, "VaultRing", 1.2, d + 2, out(1.2), STEEL, Enum.Material.Metal)
	local seam = disc(model, "VaultSeam", 1.5, d + 0.8, out(1.35), GOLD, Enum.Material.Neon)
	disc(model, "VaultDoor", 2, d, out(1.6), STEEL_DARK, Enum.Material.Metal)
	disc(model, "VaultDoorPlate", 2.2, d * 0.8, out(1.7), STEEL, Enum.Material.DiamondPlate)
	-- Bolts all round the edge.
	for i = 0, 15 do
		local angle = i * math.pi / 8
		disc(model, "VaultBolt", 0.5, d * 0.05, out(2.85) * CFrame.new(0, math.sin(angle) * d * 0.45, math.cos(angle) * d * 0.45), GOLD_LIGHT, Enum.Material.Metal)
	end
	-- The wheel: a hub, three bars across and a round rim.
	disc(model, "VaultHub", 1.4, d * 0.16, out(3.4), GOLD, Enum.Material.Metal)
	local wheelRadius = d * 0.26
	for i = 0, 2 do
		deco(model, "VaultSpoke", Vector3.new(0.4, wheelRadius * 2 + 0.6, 0.4), out(3.7) * CFrame.Angles(math.rad(i * 60), 0, 0), GOLD, Enum.Material.Metal)
	end
	local segments = 16
	local segmentLength = 2 * math.pi * wheelRadius / segments * 1.08
	for i = 0, segments - 1 do
		local angle = (i + 0.5) * 2 * math.pi / segments
		deco(model, "VaultWheel", Vector3.new(0.5, 0.5, segmentLength), out(3.7) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, wheelRadius, 0), GOLD, Enum.Material.Metal)
	end
	-- Hinges on one side, locking bars on the other.
	for _, sign in { -1, 1 } do
		disc(model, "VaultHinge", d * 0.18, 1.4, out(1.4) * CFrame.new(0, sign * d * 0.28, -(d / 2 + 1.1)) * CFrame.Angles(0, 0, math.rad(90)), STEEL, Enum.Material.Metal)
	end
	for _, y in { -0.25, 0, 0.25 } do
		deco(model, "VaultLock", Vector3.new(0.6, 0.6, 2.2), out(2.2) * CFrame.new(0, y * d, d / 2 + 0.3), GOLD_LIGHT, Enum.Material.Metal)
	end
	LobbyProps.light(seam, GOLD, 22, 2)
	model.Parent = parent
	return model
end

--[[
	A heap of gold on the floor at `base`, about `size` studs across, with
	loose coins on top and a few that rolled away. `random` makes every heap
	different (but the same each time the lobby is built).
]]
function ShopProps.coinPile(parent: Instance, base: Vector3, size: number, random: Random)
	local radius = size / 2
	local height = size * 0.42
	blob(parent, "GoldHeap", Vector3.new(size, height * 2, size * 0.9), CFrame.new(base) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0), GOLD, Enum.Material.Metal)
	for _ = 1, math.floor(size * 4) do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = math.sqrt(random:NextNumber()) * radius * 0.85
		local t = distance / radius
		local y = height * math.sqrt(math.max(1 - t * t, 0))
		looseCoin(parent, base + Vector3.new(math.cos(angle) * distance, y, math.sin(angle) * distance * 0.9), random:NextNumber(0.8, 1.1), random, 35)
	end
	for _ = 1, math.floor(size) do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = radius * random:NextNumber(1.05, 1.5)
		looseCoin(parent, base + Vector3.new(math.cos(angle) * distance, 0.08, math.sin(angle) * distance), random:NextNumber(0.8, 1), random, 6)
	end
end

-- A little pyramid of gold bars (`rows` bars wide at the bottom) on `base`.
function ShopProps.goldBars(parent: Instance, base: CFrame, rows: number, scale: number?)
	local s = scale or 1
	local barSize = Vector3.new(1.9, 0.62, 0.95) * s
	for layer = 0, rows - 1 do
		local count = rows - layer
		for i = 0, count - 1 do
			local z = (i - (count - 1) / 2) * barSize.Z * 1.06
			local y = barSize.Y / 2 + layer * barSize.Y
			deco(parent, "GoldBar", barSize, base * CFrame.new(0, y, z), GOLD, Enum.Material.Metal).Reflectance = 0.08
			deco(parent, "GoldBarTop", Vector3.new(barSize.X * 0.86, 0.06 * s, barSize.Z * 0.78), base * CFrame.new(0, y + barSize.Y / 2, z), GOLD_LIGHT, Enum.Material.Metal)
		end
	end
end

--[[
	An open treasure chest heaped with gold, with coins spilling over the
	front (the COIN RUSH bundle). About 3 studs wide at scale 1.
]]
function ShopProps.chest(parent: Instance, base: CFrame, scale: number, random: Random): Model
	local model = Instance.new("Model")
	model.Name = "TreasureChest"
	local s = scale
	local wood = Color3.fromRGB(125, 78, 45)
	local woodDark = Color3.fromRGB(92, 56, 32)
	local w, h, depth = 3 * s, 1.7 * s, 2 * s
	deco(model, "ChestBody", Vector3.new(w, h, depth), base * CFrame.new(0, h / 2, 0), wood, Enum.Material.Wood)
	for _, x in { -1, 1 } do
		deco(model, "ChestBand", Vector3.new(0.28 * s, h + 0.04, depth + 0.06), base * CFrame.new(x * w * 0.3, h / 2, 0), GOLD, Enum.Material.Metal)
	end
	deco(model, "ChestTrim", Vector3.new(w + 0.06, 0.22 * s, depth + 0.06), base * CFrame.new(0, h - 0.11 * s, 0), GOLD_DARK, Enum.Material.Metal)
	deco(model, "ChestFoot", Vector3.new(w + 0.1, 0.22 * s, depth + 0.1), base * CFrame.new(0, 0.11 * s, 0), woodDark, Enum.Material.Wood)
	deco(model, "ChestLock", Vector3.new(0.5 * s, 0.6 * s, 0.15 * s), base * CFrame.new(0, h - 0.35 * s, -depth / 2 - 0.06 * s), GOLD_LIGHT, Enum.Material.Metal)
	-- The lid, swung open on its back edge.
	local lid = base * CFrame.new(0, h, depth / 2) * CFrame.Angles(math.rad(105), 0, 0) * CFrame.new(0, 0.2 * s, -depth / 2)
	deco(model, "ChestLid", Vector3.new(w, 0.4 * s, depth), lid, woodDark, Enum.Material.Wood)
	for _, x in { -1, 1 } do
		deco(model, "ChestLidBand", Vector3.new(0.28 * s, 0.44 * s, depth + 0.04), lid * CFrame.new(x * w * 0.3, 0, 0), GOLD, Enum.Material.Metal)
	end
	-- Gold heaped up inside and coins on top.
	local gold = blob(model, "ChestGold", Vector3.new(w * 0.94, 1.1 * s, depth * 0.9), base * CFrame.new(0, h, 0), GOLD, Enum.Material.Metal)
	sparkles(gold, GOLD_LIGHT, 4, 0.35 * s)
	for _ = 1, 10 do
		local x = random:NextNumber(-0.42, 0.42) * w
		local z = random:NextNumber(-0.38, 0.38) * depth
		local t = math.min(math.sqrt((x / (w * 0.47)) ^ 2 + (z / (depth * 0.45)) ^ 2), 1)
		looseCoin(model, (base * CFrame.new(x, h + 0.55 * s * math.sqrt(1 - t * t), z)).Position, 0.75 * s, random, 40)
	end
	for _ = 1, 4 do
		local position = base * CFrame.new(random:NextNumber(-0.45, 0.45) * w, 0.08, -depth / 2 - random:NextNumber(0.3, 0.9) * s)
		looseCoin(model, position.Position, 0.7 * s, random, 8)
	end
	model.Parent = parent
	return model
end

-- A wrapped present with a ribbon and a bow (the MONTHLY bundle).
function ShopProps.giftBox(parent: Instance, base: CFrame, size: number, boxColor: Color3, ribbonColor: Color3): Model
	local model = Instance.new("Model")
	model.Name = "GiftBox"
	local s = size
	deco(model, "Gift", Vector3.new(s, s * 0.85, s), base * CFrame.new(0, s * 0.425, 0), boxColor)
	deco(model, "GiftLid", Vector3.new(s * 1.08, s * 0.2, s * 1.08), base * CFrame.new(0, s * 0.9, 0), boxColor:Lerp(WHITE, 0.15))
	deco(model, "GiftRibbon", Vector3.new(s * 0.16, s * 1.02, s * 1.1), base * CFrame.new(0, s * 0.5, 0), ribbonColor)
	deco(model, "GiftRibbon", Vector3.new(s * 1.1, s * 1.02, s * 0.16), base * CFrame.new(0, s * 0.5, 0), ribbonColor)
	for _, side in { -1, 1 } do
		blob(model, "GiftBow", Vector3.new(s * 0.5, s * 0.32, s * 0.2), base * CFrame.new(side * s * 0.2, s * 1.1, 0) * CFrame.Angles(0, 0, math.rad(side * -28)), ribbonColor)
		blob(model, "GiftBowTail", Vector3.new(s * 0.14, s * 0.35, s * 0.08), base * CFrame.new(side * s * 0.12, s * 0.92, -s * 0.56) * CFrame.Angles(0, 0, math.rad(side * 20)), ribbonColor)
	end
	blob(model, "GiftKnot", Vector3.one * s * 0.2, base * CFrame.new(0, s * 1.06, 0), ribbonColor:Lerp(BLACK, 0.1))
	model.Parent = parent
	return model
end

-- A velvet pouch tied with gold, coins spilling out (the smallest pack).
function ShopProps.pouch(parent: Instance, base: CFrame, s: number, random: Random): Model
	local model = Instance.new("Model")
	model.Name = "CoinPouch"
	local cloth = Color3.fromRGB(130, 60, 170)
	blob(model, "Pouch", Vector3.new(2.2, 2, 2.1) * s, base * CFrame.new(0, 1 * s, 0), cloth, Enum.Material.Fabric)
	column(model, "PouchNeck", 0.55 * s, 0.85 * s, base * CFrame.new(0, 1.8 * s, 0), cloth:Lerp(BLACK, 0.15), Enum.Material.Fabric)
	column(model, "PouchTie", 0.18 * s, 1.0 * s, base * CFrame.new(0, 1.95 * s, 0), GOLD, Enum.Material.Metal)
	blob(model, "PouchTop", Vector3.new(1.3, 0.6, 1.3) * s, base * CFrame.new(0, 2.45 * s, 0), cloth, Enum.Material.Fabric)
	disc(model, "PouchBadge", 0.08 * s, 0.85 * s, base * CFrame.new(0, 1.05 * s, -1.03 * s) * CFrame.Angles(0, math.rad(90), 0), GOLD, Enum.Material.Metal)
	for _ = 1, 4 do
		local position = base * CFrame.new(random:NextNumber(-1, 1) * s, 0.06, random:NextNumber(-1.5, -1.05) * s)
		looseCoin(model, position.Position, 0.6 * s, random, 8)
	end
	model.Parent = parent
	return model
end

-- A glass jar packed with coins, with a red lid.
function ShopProps.jar(parent: Instance, base: CFrame, s: number, random: Random): Model
	local model = Instance.new("Model")
	model.Name = "CoinJar"
	column(model, "JarCoins", 2 * s, 1.84 * s, base * CFrame.new(0, 0.05 * s, 0), GOLD, Enum.Material.Metal)
	for _ = 1, 6 do
		local position = base * CFrame.new(random:NextNumber(-0.5, 0.5) * s, 2.15 * s + random:NextNumber(0, 0.2) * s, random:NextNumber(-0.5, 0.5) * s)
		looseCoin(model, position.Position, 0.55 * s, random, 40)
	end
	column(model, "JarGlass", 2.6 * s, 2 * s, base, GLASS).Transparency = 0.6
	column(model, "JarNeck", 0.2 * s, 1.7 * s, base * CFrame.new(0, 2.6 * s, 0), GLASS).Transparency = 0.5
	column(model, "JarLid", 0.4 * s, 1.9 * s, base * CFrame.new(0, 2.8 * s, 0), Color3.fromRGB(225, 60, 80))
	column(model, "JarLidTop", 0.1 * s, 1.5 * s, base * CFrame.new(0, 3.2 * s, 0), Color3.fromRGB(245, 95, 110))
	model.Parent = parent
	return model
end

-- A steel bucket heaped with gold.
function ShopProps.bucket(parent: Instance, base: CFrame, s: number, random: Random): Model
	local model = Instance.new("Model")
	model.Name = "CoinBucket"
	local height = 1.9 * s
	for i = 0, 3 do
		column(model, "Bucket", height / 4, (1.7 + i * 0.18) * s, base * CFrame.new(0, i * height / 4, 0), STEEL, Enum.Material.Metal)
	end
	column(model, "BucketRim", 0.16 * s, 2.45 * s, base * CFrame.new(0, height - 0.08 * s, 0), STEEL:Lerp(WHITE, 0.25), Enum.Material.Metal)
	blob(model, "BucketGold", Vector3.new(2.25, 1.3, 2.25) * s, base * CFrame.new(0, height, 0), GOLD, Enum.Material.Metal)
	for _ = 1, 9 do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = math.sqrt(random:NextNumber()) * 0.95 * s
		local t = math.min(distance / (1.12 * s), 1)
		looseCoin(model, (base * CFrame.new(math.cos(angle) * distance, height + 0.65 * s * math.sqrt(1 - t * t), math.sin(angle) * distance)).Position, 0.55 * s, random, 40)
	end
	-- The handle: a thin arc over the top.
	local pieces = 9
	for i = 0, pieces - 1 do
		local a0, a1 = math.pi * i / pieces, math.pi * (i + 1) / pieces
		local p0 = Vector3.new(math.cos(a0) * 1.2 * s, height + math.sin(a0) * 1.4 * s, 0)
		local p1 = Vector3.new(math.cos(a1) * 1.2 * s, height + math.sin(a1) * 1.4 * s, 0)
		deco(model, "BucketHandle", Vector3.new(0.1 * s, 0.1 * s, (p1 - p0).Magnitude + 0.04), base * CFrame.lookAt((p0 + p1) / 2, p1), STEEL_DARK, Enum.Material.Metal)
	end
	model.Parent = parent
	return model
end

-- A little steel safe with gold bars stacked on top (the biggest pack).
function ShopProps.safe(parent: Instance, base: CFrame, s: number): Model
	local model = Instance.new("Model")
	model.Name = "CoinSafe"
	local w, h, depth = 2.4 * s, 2.2 * s, 2 * s
	deco(model, "Safe", Vector3.new(w, h, depth), base * CFrame.new(0, h / 2, 0), STEEL_DARK, Enum.Material.Metal)
	deco(model, "SafeDoor", Vector3.new(w * 0.82, h * 0.82, 0.12 * s), base * CFrame.new(0, h / 2, -depth / 2 - 0.05 * s), STEEL, Enum.Material.Metal)
	disc(model, "SafeDial", 0.16 * s, 0.75 * s, base * CFrame.new(0.35 * s, h * 0.6, -depth / 2 - 0.15 * s) * CFrame.Angles(0, math.rad(90), 0), GOLD, Enum.Material.Metal)
	disc(model, "SafeDialMark", 0.2 * s, 0.12 * s, base * CFrame.new(0.35 * s, h * 0.6 + 0.24 * s, -depth / 2 - 0.16 * s) * CFrame.Angles(0, math.rad(90), 0), STEEL_DARK)
	for i = 0, 2 do
		deco(model, "SafeHandle", Vector3.new(0.1 * s, 0.7 * s, 0.1 * s), base * CFrame.new(-0.45 * s, h * 0.42, -depth / 2 - 0.2 * s) * CFrame.Angles(0, 0, math.rad(i * 60)), GOLD_LIGHT, Enum.Material.Metal)
	end
	ShopProps.goldBars(model, base * CFrame.new(0, h, 0), 3, 0.62 * s)
	model.Parent = parent
	return model
end

export type Tag = {
	title: string, -- e.g. "Jar of Coins"
	detail: string, -- e.g. "+600 COINS"
	price: string, -- e.g. "R$ 99"
	badge: string?, -- a small ribbon, e.g. "+20% BONUS"
	badgeColor: Color3?,
}

--[[
	A display pedestal at `base`: a dark plinth with gold trim, a glass case
	lit from inside and a price tag floating above. `width` sizes it.
	Returns the plinth (for a prompt) and the CFrame of the plinth's top,
	where the item goes.
]]
function ShopProps.displayStand(parent: Instance, base: CFrame, width: number, tag: Tag): (BasePart, CFrame)
	local plinthHeight = 3
	local plinth = MapKit.part(parent, "Plinth", Vector3.new(width, plinthHeight, width), base * CFrame.new(0, plinthHeight / 2, 0), LobbyProps.METAL_DARK, { material = Enum.Material.DiamondPlate })
	deco(parent, "PlinthTrim", Vector3.new(width + 0.2, 0.2, width + 0.2), base * CFrame.new(0, plinthHeight + 0.05, 0), GOLD, Enum.Material.Neon)
	deco(parent, "PlinthFoot", Vector3.new(width + 0.3, 0.3, width + 0.3), base * CFrame.new(0, 0.15, 0), GOLD_DARK, Enum.Material.Metal)
	local caseHeight = width * 1.05
	local glass = deco(parent, "DisplayGlass", Vector3.new(width - 0.3, caseHeight, width - 0.3), base * CFrame.new(0, plinthHeight + 0.15 + caseHeight / 2, 0), GLASS)
	glass.Transparency = 0.85
	glass.Reflectance = 0.12
	glass.CanCollide = true -- nobody can climb inside the case
	local cap = deco(parent, "DisplayCap", Vector3.new(width, 0.3, width), base * CFrame.new(0, plinthHeight + 0.3 + caseHeight, 0), GOLD, Enum.Material.Metal)
	LobbyProps.light(cap, Color3.fromRGB(255, 236, 190), width * 2.2, 1.5)

	-- The price tag, floating above the case.
	local anchor = deco(parent, "PriceTag", Vector3.one * 0.4, base * CFrame.new(0, plinthHeight + caseHeight + 2.8, 0), GOLD)
	anchor.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PriceTag"
	billboard.Size = UDim2.fromScale(6, 3.3) -- in studs, so it shrinks with distance
	billboard.LightInfluence = 0
	billboard.MaxDistance = 55
	billboard.Parent = anchor
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.02, 0)
	layout.Parent = billboard
	local function label(order: number, text: string, height: number, width: number, color: Color3, background: Color3?): TextLabel
		local line = Instance.new("TextLabel")
		line.LayoutOrder = order
		line.Size = UDim2.fromScale(width, height)
		line.BackgroundColor3 = background or BLACK
		line.BackgroundTransparency = if background then 0 else 1
		line.Font = Enum.Font.FredokaOne
		line.TextScaled = true
		line.TextColor3 = color
		line.TextStrokeTransparency = if background then 1 else 0.3
		line.Text = text
		if background then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.45, 0)
			corner.Parent = line
			local padding = Instance.new("UIPadding")
			padding.PaddingTop = UDim.new(0.12, 0)
			padding.PaddingBottom = UDim.new(0.12, 0)
			padding.Parent = line
		end
		line.Parent = billboard
		return line
	end
	if tag.badge then
		label(1, tag.badge, 0.17, 0.6, WHITE, tag.badgeColor or Color3.fromRGB(255, 90, 140))
	end
	label(2, tag.title, 0.28, 1, WHITE)
	label(3, tag.detail, 0.2, 1, GOLD_LIGHT)
	label(4, tag.price, 0.22, 0.46, WHITE, PRICE_GREEN)
	return plinth, base * CFrame.new(0, plinthHeight + 0.15, 0)
end

return ShopProps

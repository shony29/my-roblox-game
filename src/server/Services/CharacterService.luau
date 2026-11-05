--!strict
--[[
	CharacterService
	Turns every player into a cute low-poly jelly cube with googly eyes,
	sets their speed and health, and makes respawning instant.

	How the jelly look works: the normal Roblox body is still there (it
	does the walking and physics), but we make it invisible and weld a
	simple jelly-cube model on top. Only the jelly parts can be hit by
	shots, so the hitbox matches exactly what players see.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage.Shared.Config)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local PlayerData = require(script.Parent.PlayerData)

local BODY_NAME = "JellyBody"
local BODY_SIZE = Vector3.new(3.6, 4.4, 3.6)
local BODY_OFFSET = CFrame.new(0, -0.6, 0) -- relative to the HumanoidRootPart
local FALLBACK_COLOR = Color3.fromRGB(140, 230, 90)

local CharacterService = {}

local function getEquippedColor(player: Player): Color3
	local data = PlayerData.get(player)
	local item = ShopCatalog.find(if data then data.EquippedColor else ShopCatalog.DefaultColorId)
	return if item then item.Color else FALLBACK_COLOR
end

-- Creates one cosmetic part, welded to `attachTo` at `cframe`.
local function addPart(
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	cframe: CFrame,
	attachTo: BasePart,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = cframe
	part.CanCollide = false -- the invisible Roblox body handles collisions
	part.CanTouch = false
	part.CanQuery = true -- so bullets can hit it
	part.Massless = true -- so it doesn't slow the player down
	part.Parent = parent

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachTo
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function dressAsJelly(character: Model, color: Color3)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not root or not root:IsA("BasePart") then
		return
	end

	-- Hide the normal body and stop it from being hit.
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanQuery = false
		elseif descendant:IsA("Decal") then
			descendant:Destroy() -- the face
		end
	end

	local bodyCFrame = root.CFrame * BODY_OFFSET
	local body = addPart(BODY_NAME, Enum.PartType.Block, BODY_SIZE, color, bodyCFrame, root, character)
	body.Transparency = 0.05
	body.Reflectance = 0.08

	-- Googly eyes on the front (-Z is "forward" in Roblox).
	local white = Color3.new(1, 1, 1)
	local black = Color3.fromRGB(25, 25, 35)
	for _, side in { -1, 1 } do
		local eyeCFrame = bodyCFrame * CFrame.new(0.75 * side, 1.2, -BODY_SIZE.Z / 2)
		addPart("Eye", Enum.PartType.Ball, Vector3.one * 1, white, eyeCFrame, body, body)
		addPart("Pupil", Enum.PartType.Ball, Vector3.one * 0.5, black, eyeCFrame * CFrame.new(0, 0, -0.35), body, body)
	end

	-- A chunky little blaster so other players can see you're armed.
	local blasterCFrame = bodyCFrame * CFrame.new(BODY_SIZE.X / 2 + 0.3, 0, -1)
	local blaster = addPart("Blaster", Enum.PartType.Block, Vector3.new(0.6, 0.7, 2), black, blasterCFrame, body, body)
	local tip = addPart(
		"Tip",
		Enum.PartType.Block,
		Vector3.new(0.4, 0.4, 0.3),
		color,
		blasterCFrame * CFrame.new(0, 0, -1.1),
		blaster,
		body
	)
	tip.Material = Enum.Material.Neon
end

local function recolor(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local body = character:FindFirstChild(BODY_NAME)
	if body and body:IsA("BasePart") then
		local color = getEquippedColor(player)
		body.Color = color
		local tip = body:FindFirstChild("Tip")
		if tip and tip:IsA("BasePart") then
			tip.Color = color
		end
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Config.Movement.WalkSpeed
		humanoid.UseJumpPower = true
		humanoid.JumpPower = Config.Movement.JumpPower
		humanoid.MaxHealth = Config.Player.MaxHealth
		humanoid.Health = Config.Player.MaxHealth
	end
	dressAsJelly(character, getEquippedColor(player))
end

local function onPlayerAdded(player: Player)
	player.CameraMode = Enum.CameraMode.LockFirstPerson -- it's a first-person shooter
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

function CharacterService.start()
	-- Instant respawn: the moment you're splatted, you're back.
	Players.RespawnTime = Config.Player.RespawnTime
	-- Skip loading avatar clothes/accessories; we're jellies anyway, and it's faster.
	StarterPlayer.LoadCharacterAppearance = false
	StarterPlayer.CameraMode = Enum.CameraMode.LockFirstPerson

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- When a player buys/equips a color (or their data finishes loading), recolor them.
	PlayerData.onChanged(function(player)
		recolor(player)
	end)
end

return CharacterService

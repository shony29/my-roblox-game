--!strict
--[[
	LobbyBuilder: builds the lobby, a floating grassy island far away from
	the arena, where players hang out between matches.

	  * A stone plaza in the middle where you appear.
	  * A big sign with the game's name.
	  * A training range of practice dummies (shoot them to warm up).
	  * Soft jelly gumdrops for decoration, a fence and invisible walls at the
	    edge so nobody falls off by accident.
]]

local Workspace = game:GetService("Workspace")

local PracticeDummy = require(script.Parent.Parent.Components.PracticeDummy)

export type Lobby = {
	model: Model,
	spawnCFrame: CFrame,
	origin: Vector3,
}

local ORIGIN = Vector3.new(0, 300, 700) -- centre of the island's top surface
local RADIUS = 55

local LobbyBuilder = {}

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A flat disc (an upright cylinder), `top` = height of its top face.
local function disc(parent: Instance, name: string, diameter: number, thickness: number, top: number, color: Color3, material: Enum.Material): Part
	local p = block(parent, name, Vector3.new(thickness, diameter, diameter), CFrame.new(ORIGIN.X, top - thickness / 2, ORIGIN.Z) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function sign(parent: Instance, name: string, size: Vector3, cframe: CFrame, title: string, subtitle: string)
	local board = block(parent, name, size, cframe, Color3.fromRGB(255, 250, 240))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board
	local function text(content: string, y: number, height: number, color: Color3)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, height)
		label.Position = UDim2.fromScale(0, y)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = content
		label.Parent = gui
	end
	text(title, 0.08, 0.55, Color3.fromRGB(120, 90, 220))
	text(subtitle, 0.66, 0.24, Color3.fromRGB(60, 60, 90))
end

function LobbyBuilder.build(): Lobby
	local old = Workspace:FindFirstChild("Lobby")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Lobby"

	-- The island: grass on top, layers of rock underneath.
	disc(model, "Grass", RADIUS * 2, 6, ORIGIN.Y, Color3.fromRGB(118, 205, 105), Enum.Material.Grass)
	disc(model, "Rock1", 96, 14, ORIGIN.Y - 6, Color3.fromRGB(150, 128, 110), Enum.Material.Rock)
	disc(model, "Rock2", 66, 16, ORIGIN.Y - 20, Color3.fromRGB(135, 115, 100), Enum.Material.Rock)
	disc(model, "Rock3", 30, 18, ORIGIN.Y - 36, Color3.fromRGB(120, 102, 90), Enum.Material.Rock)
	disc(model, "Plaza", 24, 0.4, ORIGIN.Y + 0.4, Color3.fromRGB(220, 214, 204), Enum.Material.Slate)

	-- Fence posts and invisible walls around the edge.
	for i = 0, 29 do
		local angle = math.rad(i * 12)
		local position = ORIGIN + Vector3.new(math.cos(angle) * (RADIUS - 3), 1.5, math.sin(angle) * (RADIUS - 3))
		block(model, "FencePost", Vector3.new(1, 3, 1), CFrame.new(position), Color3.fromRGB(165, 115, 75), Enum.Material.Wood)
	end
	for i = 0, 23 do
		local angle = math.rad(i * 15)
		local position = ORIGIN + Vector3.new(math.cos(angle) * (RADIUS - 1), 15, math.sin(angle) * (RADIUS - 1))
		local wall = block(model, "EdgeWall", Vector3.new(16, 30, 2), CFrame.lookAt(position, Vector3.new(ORIGIN.X, position.Y, ORIGIN.Z)), Color3.new(1, 1, 1))
		wall.Transparency = 1
	end

	-- Jelly gumdrops on the far side (the training range is on the +X side).
	local gumdropColors = {
		Color3.fromRGB(255, 140, 190),
		Color3.fromRGB(140, 200, 255),
		Color3.fromRGB(170, 240, 150),
		Color3.fromRGB(255, 210, 120),
		Color3.fromRGB(200, 160, 255),
	}
	for i = 0, 6 do
		local angle = math.rad(110 + i * 23)
		local size = 5 + (i % 3) * 2
		local position = ORIGIN + Vector3.new(math.cos(angle) * 40, size * 0.35, math.sin(angle) * 40)
		local gumdrop = block(model, "Gumdrop", Vector3.one * size, CFrame.new(position), gumdropColors[(i % #gumdropColors) + 1], Enum.Material.Glass)
		gumdrop.Shape = Enum.PartType.Ball
		gumdrop.Transparency = 0.2
	end

	-- Big welcome sign facing the plaza.
	local signPosition = ORIGIN + Vector3.new(0, 7, -40)
	sign(model, "WelcomeSign", Vector3.new(30, 8, 1), CFrame.lookAt(signPosition, ORIGIN + Vector3.new(0, 7, 0)), "SLIME SHOWDOWN", "Pick a mode and press FIND MATCH")

	-- Training range: three dummies facing the plaza, with a small sign.
	local range = Instance.new("Folder")
	range.Name = "TrainingRange"
	range.Parent = model
	local dummyColors = { Color3.fromRGB(255, 170, 120), Color3.fromRGB(150, 220, 255), Color3.fromRGB(190, 255, 170) }
	for index, z in { -14, 0, 14 } do
		PracticeDummy.build(range, ORIGIN + Vector3.new(38, 0, z), ORIGIN, dummyColors[index])
	end
	local rangeSign = ORIGIN + Vector3.new(26, 4, -22)
	sign(model, "RangeSign", Vector3.new(12, 4, 0.6), CFrame.lookAt(rangeSign, ORIGIN + Vector3.new(0, 4, 0)), "TRAINING", "Shoot the dummies to warm up")

	model.Parent = Workspace
	return {
		model = model,
		spawnCFrame = CFrame.lookAt(ORIGIN + Vector3.new(0, 4, 10), ORIGIN + Vector3.new(0, 4, -40)),
		origin = ORIGIN,
	}
end

return LobbyBuilder

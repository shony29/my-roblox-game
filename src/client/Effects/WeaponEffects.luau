--!strict
--[[
	Effects: the "juice" — muzzle flashes, bullet tracers, impact puffs and sounds.
	Everything here is purely visual and lives only on this player's screen.
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local TRACER_TIME = 0.12
local FLASH_TIME = 0.05

-- All local effect parts go in one folder, so our own raycasts can ignore them.
local fxFolder = Instance.new("Folder")
fxFolder.Name = "WeaponFx"
fxFolder.Parent = workspace

local function makeFxPart(size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	return part
end

local function fadeAndDestroy(part: BasePart, duration: number, endSize: Vector3?)
	local goal: { [string]: any } = { Transparency = 1 }
	if endSize then
		goal.Size = endSize
	end
	local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tween.Completed:Once(function()
		part:Destroy()
	end)
	tween:Play()
end

local soundCache: { [string]: Sound } = {}

local Effects = {}

Effects.folder = fxFolder

-- A quick bright pop at the gun's tip.
function Effects.muzzleFlash(position: Vector3, color: Color3)
	local flash = makeFxPart(Vector3.new(0.7, 0.7, 0.7), color)
	flash.Shape = Enum.PartType.Ball
	flash.Position = position

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 4
	light.Range = 10
	light.Parent = flash

	flash.Parent = fxFolder
	fadeAndDestroy(flash, FLASH_TIME, Vector3.new(1.2, 1.2, 1.2))
end

-- A thin glowing line from the gun to where the bullet landed, which fades fast.
function Effects.tracer(from: Vector3, to: Vector3, color: Color3, width: number)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local tracer = makeFxPart(Vector3.new(width, width, length), color)
	tracer.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	tracer.Parent = fxFolder
	fadeAndDestroy(tracer, TRACER_TIME, Vector3.new(width * 0.3, width * 0.3, length))
end

-- A tiny puff where a bullet hit something.
function Effects.impact(position: Vector3)
	local puff = makeFxPart(Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(255, 255, 230))
	puff.Shape = Enum.PartType.Ball
	puff.Position = position
	puff.Parent = fxFolder
	fadeAndDestroy(puff, 0.15, Vector3.new(0.9, 0.9, 0.9))
end

-- A splash where a launcher glob lands: a quick glowing bubble that grows and fades.
function Effects.explosion(position: Vector3, color: Color3, radius: number)
	local bubble = makeFxPart(Vector3.new(1, 1, 1), color)
	bubble.Shape = Enum.PartType.Ball
	bubble.Position = position
	bubble.Transparency = 0.25
	bubble.Parent = fxFolder
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 3
	light.Range = radius * 1.6
	light.Parent = bubble
	fadeAndDestroy(bubble, 0.35, Vector3.one * radius * 2)
end

-- A launcher glob: a glowing ball that flies from `from` to `to`, then splashes.
function Effects.projectile(from: Vector3, to: Vector3, speed: number, color: Color3, radius: number)
	local glob = makeFxPart(Vector3.new(0.9, 0.9, 0.9), color)
	glob.Shape = Enum.PartType.Ball
	glob.Position = from
	glob.Parent = fxFolder
	local travel = math.max((to - from).Magnitude / speed, 0.05)
	local flight = TweenService:Create(glob, TweenInfo.new(travel, Enum.EasingStyle.Linear), { Position = to })
	flight.Completed:Once(function()
		glob:Destroy()
		Effects.explosion(to, color, radius)
	end)
	flight:Play()
end

-- Plays a non-positional sound (heard the same everywhere, like a UI sound).
function Effects.playSound(soundId: string, volume: number, pitch: number)
	if soundId == "" then
		return
	end
	local sound = soundCache[soundId]
	if not sound then
		local newSound = Instance.new("Sound")
		newSound.SoundId = soundId
		newSound.Parent = SoundService
		soundCache[soundId] = newSound
		sound = newSound
	end
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	-- Using PlayLocalSound lets the same sound overlap itself during fast hits.
	SoundService:PlayLocalSound(sound)
end

-- Plays a sound in the 3D world, for other players' shots.
function Effects.playSoundAt(soundId: string, position: Vector3, volume: number)
	if soundId == "" then
		return
	end
	-- Terrain sits at the world's center, so Position here is a world position.
	local holder = Instance.new("Attachment")
	holder.Position = position
	holder.Parent = workspace.Terrain
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMaxDistance = 300
	sound.Parent = holder
	sound.Ended:Once(function()
		holder:Destroy()
	end)
	sound:Play()
	-- Safety net in case the sound never loads.
	task.delay(5, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
end

return Effects

--!strict
--[[
	MapLightingController: every map has its own sky, light and haze.

	Lighting changes made by this script only affect YOUR screen, so the
	lobby can keep its bunker look for players there while you play under a
	starry sky on Astro Station or in blue underwater light on Coral Reef.

	  * In a team match: the map being played (MatchState MapId).
	  * In the free-for-all arena: its current theme (FreeForAllState.Arena).
	  * Anywhere else: the lobby's own lighting (as set in the place).
	Changes fade in over a moment.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapConfig = require(Shared:WaitForChild("Config"):WaitForChild("MapConfig"))
local MatchState = require(Shared:WaitForChild("Match"):WaitForChild("MatchState"))

type Haze = { Density: number, Color: Color3, Decay: Color3, Haze: number, Glare: number }
type Preset = {
	ClockTime: number,
	Brightness: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	Haze: Haze,
	Tint: Color3,
	Saturation: number,
	Contrast: number,
	Stars: number,
}

local C = Color3.fromRGB

-- Keyed by theme (Map/ArenaThemes) or, for the other maps, by map Id.
local PRESETS: { [string]: Preset } = {
	Space = {
		ClockTime = 0, Brightness = 1.3, Ambient = C(110, 115, 150), OutdoorAmbient = C(95, 100, 140),
		Haze = { Density = 0.05, Color = C(70, 80, 140), Decay = C(30, 30, 70), Haze = 0, Glare = 0 },
		Tint = C(225, 232, 255), Saturation = 0.12, Contrast = 0.1, Stars = 3000,
	},
	Kitchen = {
		ClockTime = 13, Brightness = 2.3, Ambient = C(150, 140, 130), OutdoorAmbient = C(175, 165, 155),
		Haze = { Density = 0.15, Color = C(255, 240, 220), Decay = C(240, 220, 200), Haze = 0.6, Glare = 0 },
		Tint = C(255, 248, 236), Saturation = 0.18, Contrast = 0.06, Stars = 0,
	},
	Fireplace = {
		ClockTime = 21, Brightness = 0.9, Ambient = C(125, 95, 75), OutdoorAmbient = C(95, 75, 65),
		Haze = { Density = 0.3, Color = C(90, 60, 40), Decay = C(60, 40, 30), Haze = 1, Glare = 0 },
		Tint = C(255, 236, 212), Saturation = 0.12, Contrast = 0.08, Stars = 1500,
	},
	AntFarm = {
		ClockTime = 15, Brightness = 2.4, Ambient = C(150, 130, 110), OutdoorAmbient = C(175, 155, 125),
		Haze = { Density = 0.35, Color = C(240, 215, 170), Decay = C(210, 170, 120), Haze = 1.3, Glare = 0.1 },
		Tint = C(255, 246, 226), Saturation = 0.15, Contrast = 0.05, Stars = 0,
	},
	Reef = {
		ClockTime = 12, Brightness = 1.7, Ambient = C(80, 140, 160), OutdoorAmbient = C(90, 165, 185),
		Haze = { Density = 0.5, Color = C(70, 170, 200), Decay = C(30, 110, 160), Haze = 2.2, Glare = 0 },
		Tint = C(215, 240, 255), Saturation = 0.22, Contrast = 0.04, Stars = 0,
	},
	Ice = {
		ClockTime = 14, Brightness = 2.5, Ambient = C(150, 170, 200), OutdoorAmbient = C(175, 195, 225),
		Haze = { Density = 0.4, Color = C(220, 235, 255), Decay = C(170, 200, 240), Haze = 1.6, Glare = 0.2 },
		Tint = C(236, 246, 255), Saturation = 0.1, Contrast = 0.05, Stars = 0,
	},
	Candy = {
		ClockTime = 16.5, Brightness = 2.4, Ambient = C(170, 140, 160), OutdoorAmbient = C(195, 165, 185),
		Haze = { Density = 0.3, Color = C(255, 215, 240), Decay = C(240, 170, 210), Haze = 1.2, Glare = 0.3 },
		Tint = C(255, 242, 250), Saturation = 0.32, Contrast = 0.06, Stars = 0,
	},
	Bounce = {
		ClockTime = 13.5, Brightness = 3, Ambient = C(140, 150, 170), OutdoorAmbient = C(175, 185, 205),
		Haze = { Density = 0.2, Color = C(200, 230, 255), Decay = C(150, 200, 255), Haze = 0.8, Glare = 0.2 },
		Tint = C(255, 255, 255), Saturation = 0.35, Contrast = 0.12, Stars = 0,
	},
	JellyArena = {
		ClockTime = 14, Brightness = 2.8, Ambient = C(140, 150, 170), OutdoorAmbient = C(170, 180, 200),
		Haze = { Density = 0.22, Color = C(210, 235, 255), Decay = C(160, 200, 250), Haze = 0.9, Glare = 0.15 },
		Tint = C(255, 252, 245), Saturation = 0.3, Contrast = 0.1, Stars = 0,
	},
	MossyKeep = {
		ClockTime = 16, Brightness = 2.4, Ambient = C(140, 150, 135), OutdoorAmbient = C(165, 175, 155),
		Haze = { Density = 0.3, Color = C(200, 225, 190), Decay = C(160, 190, 150), Haze = 1.2, Glare = 0.1 },
		Tint = C(250, 255, 240), Saturation = 0.2, Contrast = 0.06, Stars = 0,
	},
}

local player = Players.LocalPlayer
local MapLightingController = {}
local started = false

local function find(className: string): Instance?
	return Lighting:FindFirstChildOfClass(className)
end

-- What the place itself sets (the lobby's look), so we can go back to it.
local function capture(): Preset
	local atmosphere = find("Atmosphere") :: Atmosphere?
	local correction = find("ColorCorrectionEffect") :: ColorCorrectionEffect?
	local sky = find("Sky") :: Sky?
	return {
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		Haze = {
			Density = if atmosphere then atmosphere.Density else 0.3,
			Color = if atmosphere then atmosphere.Color else C(200, 220, 255),
			Decay = if atmosphere then atmosphere.Decay else C(140, 180, 240),
			Haze = if atmosphere then atmosphere.Haze else 1,
			Glare = if atmosphere then atmosphere.Glare else 0,
		},
		Tint = if correction then correction.TintColor else C(255, 255, 255),
		Saturation = if correction then correction.Saturation else 0,
		Contrast = if correction then correction.Contrast else 0,
		Stars = if sky then sky.StarCount else 3000,
	}
end

local function apply(preset: Preset)
	local info = TweenInfo.new(0.8, Enum.EasingStyle.Sine)
	Lighting.ClockTime = preset.ClockTime
	TweenService:Create(Lighting, info, {
		Brightness = preset.Brightness,
		Ambient = preset.Ambient,
		OutdoorAmbient = preset.OutdoorAmbient,
	}):Play()
	local atmosphere = find("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, info, {
			Density = preset.Haze.Density,
			Color = preset.Haze.Color,
			Decay = preset.Haze.Decay,
			Haze = preset.Haze.Haze,
			Glare = preset.Haze.Glare,
		}):Play()
	end
	local correction = find("ColorCorrectionEffect")
	if correction then
		TweenService:Create(correction, info, {
			TintColor = preset.Tint,
			Saturation = preset.Saturation,
			Contrast = preset.Contrast,
		}):Play()
	end
	local sky = find("Sky")
	if sky and sky:IsA("Sky") then
		sky.StarCount = preset.Stars
	end
end

function MapLightingController.start()
	if started then
		return
	end
	started = true
	local lobbyLook = capture()
	local matchState = ReplicatedStorage:WaitForChild(MatchState.FOLDER_NAME, 30)
	local current = ""

	-- Which look should this player see right now?
	local function wanted(): string
		if player:GetAttribute("FreeForAll") == true then
			local state = ReplicatedStorage:FindFirstChild("FreeForAllState")
			local theme = state and state:GetAttribute("Arena")
			return if typeof(theme) == "string" then theme else ""
		end
		local inMatch = player:GetAttribute(MatchState.PlayerAttr.Status) == "InMatch"
			and MatchState.toTeam(player:GetAttribute(MatchState.PlayerAttr.Team)) ~= nil
		if inMatch and matchState then
			local info = MapConfig.get(matchState:GetAttribute(MatchState.Attr.MapId))
			if info then
				return info.Theme or info.Id
			end
		end
		return ""
	end

	task.spawn(function()
		while true do
			local key = wanted()
			if key ~= current then
				current = key
				apply(PRESETS[key] or lobbyLook)
			end
			task.wait(0.5)
		end
	end)
end

return MapLightingController

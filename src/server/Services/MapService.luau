--!strict
--[[
	MapService: builds the map a match is played on.

	Each map has a builder module in server/Map (see Config/MapConfig).
	Loading a map removes the previous one, builds the new one, and gives
	its spawn points to SpawnService. Building is real work done right
	here, which is what the loading screen waits for.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local SpawnService = require(script.Parent.SpawnService)
local AmmoService = require(script.Parent.AmmoService)

type Built = { model: Model, spawnPoints: { BasePart }, ammoSpots: { Vector3 }? }
-- Builders get the size (1 = a 1v1), the theme and whether it's free for all;
-- builders that don't need them just ignore them.
type Builder = { build: (scale: number?, theme: string?, freeForAll: boolean?) -> Built }

local MapService = {}

local loadedId: string? = nil
local loadedKey: string? = nil -- the map plus its size, so a different size rebuilds it
local loadedModel: Model? = nil

function MapService.currentId(): string?
	return loadedId
end

-- Builds the map (if it isn't already loaded at this size). `scale` makes
-- themed arenas bigger for more players (Config/MapConfig.scaleFor), and
-- free for all adds spawn pads all around. Returns true on success.
function MapService.load(mapId: string, scale: number?, freeForAll: boolean?): boolean
	local key = `{mapId}|{scale or 1}|{freeForAll == true}`
	if loadedKey == key and loadedModel and loadedModel.Parent then
		return true
	end
	local info = MapConfig.get(mapId)
	local builderModule = info and script.Parent.Parent.Map:FindFirstChild(info.Builder)
	if not info or not builderModule or not builderModule:IsA("ModuleScript") then
		warn(`[MapService] Unknown map or builder: {mapId}`)
		return false
	end
	local builder = (require :: any)(builderModule) :: Builder
	local ok, result = pcall(builder.build, scale or 1, info.Theme, freeForAll == true)
	if not ok then
		warn(`[MapService] Building {mapId} failed: {result}`)
		return false
	end
	local built = result :: Built
	if loadedModel and loadedModel ~= built.model then
		loadedModel:Destroy()
	end
	loadedId = mapId
	loadedKey = key
	loadedModel = built.model
	SpawnService.init(built.spawnPoints)
	AmmoService.setSpots(built.ammoSpots or {}) -- slime ammo balls
	return true
end

return MapService

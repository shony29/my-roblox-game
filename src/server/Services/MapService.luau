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

type Built = { model: Model, spawnPoints: { BasePart } }
type Builder = { build: () -> Built }

local MapService = {}

local loadedId: string? = nil
local loadedModel: Model? = nil

function MapService.currentId(): string?
	return loadedId
end

-- Builds the map (if it isn't already loaded). Returns true on success.
function MapService.load(mapId: string): boolean
	if loadedId == mapId and loadedModel and loadedModel.Parent then
		return true
	end
	local info = MapConfig.get(mapId)
	local builderModule = info and script.Parent.Parent.Map:FindFirstChild(info.Builder)
	if not info or not builderModule or not builderModule:IsA("ModuleScript") then
		warn(`[MapService] Unknown map or builder: {mapId}`)
		return false
	end
	local builder = (require :: any)(builderModule) :: Builder
	local ok, result = pcall(builder.build)
	if not ok then
		warn(`[MapService] Building {mapId} failed: {result}`)
		return false
	end
	local built = result :: Built
	if loadedModel and loadedModel ~= built.model then
		loadedModel:Destroy()
	end
	loadedId = mapId
	loadedModel = built.model
	SpawnService.init(built.spawnPoints)
	return true
end

return MapService

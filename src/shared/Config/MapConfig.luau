--!strict
--[[
	MapConfig: every map players can vote for.

	Builder is the name of a ModuleScript in server/Map that builds the map
	and returns { model, spawnPoints }. Add a map by writing a builder and
	listing it here; voting turns on by itself once there are 2+ maps.
]]

export type MapInfo = {
	Id: string,
	DisplayName: string,
	Description: string,
	Builder: string,
	PreviewColor: Color3, -- placeholder card colour until real thumbnails exist
}

local Maps: { [string]: MapInfo } = {
	JellyArena = {
		Id = "JellyArena",
		DisplayName = "Jelly Arena",
		Description = "A compact, colourful arena with towers and a raised centre.",
		Builder = "ArenaBuilder",
		PreviewColor = Color3.fromRGB(134, 220, 132),
	},
}

local MapConfig = {
	Maps = Maps,
	Order = { "JellyArena" } :: { string },
	Default = "JellyArena",
	VoteTime = 10, -- seconds of map voting
	MaxChoices = 3, -- map cards shown per vote
}

function MapConfig.get(value: unknown): MapInfo?
	if typeof(value) ~= "string" then
		return nil
	end
	return Maps[value]
end

return MapConfig

--!strict
--[[
	MapConfig: every map players can vote for.

	Builder is the name of a ModuleScript in server/Map that builds the map
	and returns { model, spawnPoints }. Add a map by writing a builder and
	listing it here; voting turns on by itself once there are 2+ maps.

	The themed arenas share one builder (Map/ThemedArenaBuilder) and differ
	by Theme (Map/ArenaThemes). They grow with the number of players
	(MapConfig.scaleFor): smallest for a 1v1, bigger for 2v2 and 4v4, and
	biggest for free for all.
]]

export type MapInfo = {
	Id: string,
	DisplayName: string,
	Description: string,
	Builder: string,
	Theme: string?, -- themed arenas: which look (see Map/ArenaThemes)
	PreviewColor: Color3, -- the vote card's colour
	Emblems: { string }, -- little 3D charms shown on the vote card (Cosmetics/CharmBuilder)
}

local Maps: { [string]: MapInfo } = {
	JellyArena = {
		Id = "JellyArena",
		DisplayName = "Jelly Arena",
		Description = "A compact, colourful arena with towers and a raised centre.",
		Builder = "ArenaBuilder",
		PreviewColor = Color3.fromRGB(134, 220, 132),
		Emblems = { "Gem", "Star" },
	},
	MossyKeep = {
		Id = "MossyKeep",
		DisplayName = "Mossy Keep",
		Description = "Castle ruins in a pine forest: towers, gate arches and campfires.",
		Builder = "MossyKeepBuilder",
		PreviewColor = Color3.fromRGB(96, 150, 90),
		Emblems = { "Acorn", "Leaf" },
	},
	AstroStation = {
		Id = "AstroStation",
		DisplayName = "Astro Station",
		Description = "A space base on an asteroid: fuel tanks, a glass dome and glowing walkways.",
		Builder = "ThemedArenaBuilder",
		Theme = "Space",
		PreviewColor = Color3.fromRGB(80, 100, 160),
		Emblems = { "Moon", "Star", "Sparkle" },
	},
	ChefsKitchen = {
		Id = "ChefsKitchen",
		DisplayName = "Chef's Kitchen",
		Description = "Tiny slimes on a giant kitchen floor: rolling pins, jars and a mixing bowl.",
		Builder = "ThemedArenaBuilder",
		Theme = "Kitchen",
		PreviewColor = Color3.fromRGB(240, 200, 150),
		Emblems = { "Cupcake", "Egg", "Cheese" },
	},
	CozyFireplace = {
		Id = "CozyFireplace",
		DisplayName = "Cozy Fireplace",
		Description = "A giant living room at night: a crackling fire, candles and stacks of books.",
		Builder = "ThemedArenaBuilder",
		Theme = "Fireplace",
		PreviewColor = Color3.fromRGB(230, 140, 70),
		Emblems = { "Mug", "Cookie", "Book" },
	},
	AntFarm = {
		Id = "AntFarm",
		DisplayName = "Ant Farm",
		Description = "Sandy hills and sugar cubes behind giant glass walls.",
		Builder = "ThemedArenaBuilder",
		Theme = "AntFarm",
		PreviewColor = Color3.fromRGB(214, 170, 110),
		Emblems = { "Leaf", "Cheese" },
	},
	CoralReef = {
		Id = "CoralReef",
		DisplayName = "Coral Reef",
		Description = "Under the sea: coral towers, treasure chests and a sunken ship.",
		Builder = "ThemedArenaBuilder",
		Theme = "Reef",
		PreviewColor = Color3.fromRGB(70, 190, 220),
		Emblems = { "Shell", "Starfish" },
	},
	IceCastle = {
		Id = "IceCastle",
		DisplayName = "Ice Castle",
		Description = "An ice castle in the snow, with frozen ponds, snowmen and ice slides.",
		Builder = "ThemedArenaBuilder",
		Theme = "Ice",
		PreviewColor = Color3.fromRGB(170, 220, 255),
		Emblems = { "Snowflake", "Snowman" },
	},
	CandyLand = {
		Id = "CandyLand",
		DisplayName = "Candy Land",
		Description = "Gingerbread, gummy bears, candy canes and chocolate bars.",
		Builder = "ThemedArenaBuilder",
		Theme = "Candy",
		PreviewColor = Color3.fromRGB(255, 160, 210),
		Emblems = { "Lollipop", "CandyCane", "Candy" },
	},
	BounceHouse = {
		Id = "BounceHouse",
		DisplayName = "Bounce House",
		Description = "A bright inflatable playground by the water.",
		Builder = "ThemedArenaBuilder",
		Theme = "Bounce",
		PreviewColor = Color3.fromRGB(255, 210, 60),
		Emblems = { "BeachBall", "Balloon" },
	},
}

local MapConfig = {
	Maps = Maps,
	Order = {
		"JellyArena",
		"MossyKeep",
		"AstroStation",
		"ChefsKitchen",
		"CozyFireplace",
		"AntFarm",
		"CoralReef",
		"IceCastle",
		"CandyLand",
		"BounceHouse",
	} :: { string },
	Default = "JellyArena",
	VoteTime = 10, -- seconds of map voting
	MaxChoices = 10, -- map cards shown per vote (10 = every map)
}

-- How big a themed arena is for this many players (1 = a 1v1 arena).
function MapConfig.scaleFor(playerCount: number): number
	if playerCount <= 2 then
		return 1
	elseif playerCount <= 4 then
		return 1.25
	elseif playerCount <= 8 then
		return 1.55
	end
	return 1.55 + math.min((playerCount - 8) / 17, 1) * 0.45 -- free for all: up to 2x
end

function MapConfig.get(value: unknown): MapInfo?
	if typeof(value) ~= "string" then
		return nil
	end
	return Maps[value]
end

return MapConfig

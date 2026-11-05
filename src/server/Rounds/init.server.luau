--!strict
-- Server entry point for rounds: build the arena, then start the round loop.

local ArenaBuilder = require(script.Parent.Map.ArenaBuilder)
local RoundService = require(script.RoundService)
local SpawnService = require(script.SpawnService)

local arena = ArenaBuilder.build()
SpawnService.init(arena.spawnPoints)
RoundService.start()

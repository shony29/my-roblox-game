--!strict
-- Starts the movement controls and the blob jiggle on this player's computer.
local MovementController = require(script.MovementController)
local BlobAnimator = require(script.BlobAnimator)

MovementController.start()
BlobAnimator.start()

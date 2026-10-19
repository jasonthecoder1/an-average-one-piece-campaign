-- Server entry: lobby menu -> run (ship <-> sea chart <-> stops) -> back to the lobby.
local Run = require(script.Parent.Run)
local ShipService = require(script.Parent.ShipService)
local LobbyService = require(script.Parent.LobbyService)

ShipService.build()
Run.onShip = ShipService.board
Run.onChanged = ShipService.push
Run.onEnd = function(run)
	LobbyService.open(run)
end

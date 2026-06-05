local _Config = script.Parent
local _Repcl = _Config.Parent._Repcl

local Managers = _Repcl.Managers
local Types = require(_Repcl.Types)

local SessionManager = require(Managers.SessionManager)

function Register(config: Types.CELRegistry)

local CEL = {}

return CEL
local _Config = script.Parent
local _Repcl = _Config.Parent._Repcl

local Managers = _Repcl.Managers
local Types = require(_Repcl.Types)

local SessionManager = require(Managers.SessionManager)

function Register(config: Types.CommandRegistry)
	SessionManager.Register(config)
end

function Filter(T: {any}, Exclude: {string})
	T = table.clone(T)
	for i in Exclude do
		for k in T do
			local t = typeof(k)
			if typeof(k) == t then
				T[k] = nil
			end
		end
	end
	return T
end

local CEL = {}

CEL.SomeConfig = "SOmeValue"

function CEL.Export()
	return Filter(CEL, {"function"})
end

function CEL.Import(t: {Types.})
	return Filter(CEL, {"function"})
end

return CEL
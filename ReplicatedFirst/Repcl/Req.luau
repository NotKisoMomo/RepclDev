local cache: { [string]: any } = {}

local Req = {}

function Req.get(name: string): any
	if cache[name] then return cache[name] end
	local m = require(script.Parent[name])
	cache[name] = m
	return m
end

return setmetatable(Req, { __call = function(_, name) return Req.get(name) end })
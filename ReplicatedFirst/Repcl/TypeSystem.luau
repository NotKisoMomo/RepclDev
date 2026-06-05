--!strict

local Types = require(script.Parent.Types)
type TypeDef = Types.TypeDef

local registry: { [string]: TypeDef } = {}

local TypeSystem = {}

function TypeSystem.define(name: string, def: TypeDef)
	assert(not registry[name], "[Repcl:TypeSystem] type already defined: " .. name)
	registry[name] = def
end

function TypeSystem.override(name: string, def: TypeDef)
	registry[name] = def
end

function TypeSystem.get(name: string): TypeDef?
	return registry[name]
end

function TypeSystem.getAll(): { [string]: TypeDef }
	return registry
end

return TypeSystem
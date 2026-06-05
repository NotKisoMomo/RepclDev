--!strict
local Types = require(script.Parent.Types)
local Hooks = require(script.Parent.Hooks)
type CommandDef = Types.CommandDef

local registry: { [string]: CommandDef } = {}
local enabled:  { [string]: boolean }    = {}
local aliases:  { [string]: string }     = {}

local Registry = {}

function Registry.init()
	registry = {}
	enabled  = {}
	aliases  = {}
end

function Registry.register(def: CommandDef)
	assert(type(def.Name) == "string" and #def.Name > 0, "[Repcl:Registry] command Name is required")
	assert(
		def.Context == "Server" or def.Context == "Client"
			or def.Context == "Shared" or def.Context == "Bridge",
		"[Repcl:Registry] invalid Context on: " .. def.Name
	)
	local key = def.Name:lower()
	registry[key] = def
	enabled[key]  = true
	if def.Aliases then
		for _, alias in def.Aliases do
			aliases[alias:lower()] = key
		end
	end
	Hooks.fireRegister(def)
end

function Registry.unregister(name: string)
	local key = name:lower()
	local def = registry[key]
	if not def then return end
	if def.Aliases then
		for _, alias in def.Aliases do
			aliases[alias:lower()] = nil
		end
	end
	registry[key] = nil
	enabled[key]  = nil
	Hooks.fireUnregister(name)
end

function Registry.setEnabled(name: string, state: boolean)
	local key = name:lower()
	assert(registry[key], "[Repcl:Registry] command not found: " .. name)
	enabled[key] = state
end

function Registry.addAlias(name: string, alias: string)
	local key = name:lower()
	assert(registry[key], "[Repcl:Registry] command not found: " .. name)
	aliases[alias:lower()] = key
	local def = registry[key]
	if not def.Aliases then
		registry[key] = table.clone(def)
		registry[key].Aliases = {}
	end
	table.insert(registry[key].Aliases :: { string }, alias)
end

function Registry.get(name: string): CommandDef?
	local key      = name:lower()
	local resolved = aliases[key] or key
	local def      = registry[resolved]
	if not def then return nil end
	if not enabled[resolved] then return nil end
	return def
end

function Registry.getAll(): { CommandDef }
	local out = {}
	for _, def in registry do
		table.insert(out, def)
	end
	return out
end

-- FIX: The old snapshot used table.clone (shallow), which meant nested arrays
-- like Args, Aliases, and Flags were still shared references between the live
-- registry and the snapshot. A Reload() that mutated any nested table would
-- silently corrupt the snapshot used to re-register. Deep-clone those arrays.
local function deepCloneDef(def: CommandDef): CommandDef
	local clone = table.clone(def) :: any

	if def.Args then
		clone.Args = {}
		for i, arg in def.Args do
			local argClone = table.clone(arg) :: any
			if arg.Types then
				argClone.Types = table.clone(arg.Types)
			end
			clone.Args[i] = argClone
		end
	end

	if def.Flags then
		clone.Flags = {}
		for i, flag in def.Flags do
			clone.Flags[i] = table.clone(flag)
		end
	end

	if def.Aliases then
		clone.Aliases = table.clone(def.Aliases)
	end

	return clone :: CommandDef
end

function Registry.snapshot(): { CommandDef }
	local out = {}
	for _, def in registry do
		table.insert(out, deepCloneDef(def))
	end
	return out
end

function Registry.clear()
	registry = {}
	enabled  = {}
	aliases  = {}
end

return Registry
local Types    = require(script.Parent.Types)
local Registry = require(script.Parent.Registry)

type CommandDef = Types.CommandDef
type ArgDef     = Types.ArgDef
type FlagDef    = Types.FlagDef
type Ctx        = Types.Ctx

local Builder   = {}
Builder.__index = Builder

function Builder.new(name: string)
	local self    = setmetatable({}, Builder)
	self._def     = {
		Name        = name,
		Aliases     = {},
		Description = "",
		Context     = "Server",
		Permission  = "User",
		Args        = {},
		Flags       = {},
	} :: CommandDef
	return self
end

function Builder:Alias(alias: string)
	table.insert(self._def.Aliases :: { string }, alias)
	return self
end

function Builder:Description(desc: string)
	self._def.Description = desc
	return self
end

function Builder:Context(ctx: "Server" | "Client" | "Shared" | "Bridge")
	self._def.Context = ctx
	return self
end

function Builder:Permission(perm: string)
	self._def.Permission = perm
	return self
end

function Builder:Arg(def: ArgDef)
	table.insert(self._def.Args :: { ArgDef }, def)
	return self
end

function Builder:Flag(def: FlagDef)
	table.insert(self._def.Flags :: { FlagDef }, def)
	return self
end

function Builder:Run(fn: (ctx: Ctx) -> any)
	self._def.Run = fn
	return self
end

function Builder:Client(fn: (ctx: Ctx) -> any)
	self._def.Client = fn
	return self
end

function Builder:Server(fn: (ctx: Ctx, payload: any) -> any)
	self._def.Server = fn
	return self
end

function Builder:Register()
	Registry.register(self._def)
end

return Builder
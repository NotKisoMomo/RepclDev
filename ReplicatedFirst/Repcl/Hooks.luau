--!strict

local Types = require(script.Parent.Types)
type CommandDef  = Types.CommandDef
type Ctx         = Types.Ctx
type MiddlewareFn = Types.MiddlewareFn

local preFns:     { MiddlewareFn }                  = {}
local postFns:    { MiddlewareFn }                   = {}
local errHandler: ((ctx: Ctx, err: string) -> ())?  = nil
local onRegFns:   { (def: CommandDef) -> () }        = {}
local onUnregFns: { (name: string) -> () }           = {}
local onConnFns:  { (player: Player) -> () }         = {}
local onDiscFns:  { (player: Player) -> () }         = {}

local Hooks = {}

function Hooks.addPre(fn: MiddlewareFn)
	table.insert(preFns, fn)
end

function Hooks.addPost(fn: MiddlewareFn)
	table.insert(postFns, fn)
end

function Hooks.setErrorHandler(fn: (ctx: Ctx, err: string) -> ())
	errHandler = fn
end

function Hooks.onRegister(fn: (def: CommandDef) -> ())
	table.insert(onRegFns, fn)
end

function Hooks.onUnregister(fn: (name: string) -> ())
	table.insert(onUnregFns, fn)
end

function Hooks.onConnect(fn: (player: Player) -> ())
	table.insert(onConnFns, fn)
end

function Hooks.onDisconnect(fn: (player: Player) -> ())
	table.insert(onDiscFns, fn)
end

function Hooks.runPre(ctx: Ctx): boolean
	for _, fn in preFns do
		local ok, result = pcall(fn, ctx)
		if not ok then
			warn("[Repcl:Hooks] PreExecute error:", result)
		elseif result == false then
			return false
		end
	end
	return true
end

function Hooks.runPost(ctx: Ctx, result: any)
	for _, fn in postFns do
		pcall(fn, ctx, result)
	end
end

function Hooks.runError(ctx: Ctx, err: string)
	if errHandler then
		pcall(errHandler, ctx, err)
	else
		warn("[Repcl] /" .. ctx.Command .. " error:", err)
	end
end

function Hooks.fireRegister(def: CommandDef)
	for _, fn in onRegFns do pcall(fn, def) end
end

function Hooks.fireUnregister(name: string)
	for _, fn in onUnregFns do pcall(fn, name) end
end

function Hooks.fireConnect(player: Player)
	for _, fn in onConnFns do pcall(fn, player) end
end

function Hooks.fireDisconnect(player: Player)
	for _, fn in onDiscFns do pcall(fn, player) end
end

return Hooks
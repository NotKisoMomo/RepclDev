local Registry    = require(script.Registry)
local Executor    = require(script.Executor)
local AuthManager = require(script.AuthManager)
local Hooks       = require(script.Hooks)
local TypeSystem  = require(script.TypeSystem)
local Parser      = require(script.Parser)
local Network     = require(script.Network)
local Interface   = require(script.Interface)
local WindowMgr   = require(script.WindowManager)
local Repl        = require(script.Repl)
local BuiltinTypes = require(script.BuiltinTypes)
local Builtins    = require(script.Builtins)
local Builder     = require(script.Builder)
local Iris = require(script.deps.Iris)

local Types = require(script.Types)
type CommandDef   = Types.CommandDef
type TypeDef      = Types.TypeDef
type Config       = Types.Config
type AuthHook     = Types.AuthHook
type RoleHook     = Types.RoleHook
type GroupHook    = Types.GroupHook
type MiddlewareFn = Types.MiddlewareFn
type WindowFn     = Types.WindowFn
type Ctx          = Types.Ctx

local RunService = game:GetService("RunService")
local IS_SERVER  = RunService:IsServer()
local IS_CLIENT  = RunService:IsClient()

local _started = false

local Repcl = {}

Repcl.Iris = Iris
Repcl.Parser  = Parser
Repcl.Version = "0.1.0"

function Repcl.IsStarted(): boolean
	return _started
end

function Repcl.Start(config: Config)
	assert(not _started, "[Repcl] already started")
	_started = true

	BuiltinTypes.register()
	Registry.init()
	AuthManager.init(config)
	--Executor.
	Network.init()

	if IS_CLIENT then
		local Iris = require(script.deps.Iris)
		Iris.Init()
		Interface.init(config)
		WindowMgr.init()
		Network.listenClient()
	end

	if IS_SERVER then
		Network.listenServer()
	end

	Repl.init(config)
	Builtins.register()
end

function Repcl.Stop()
	assert(_started, "[Repcl] not started")
	Network.destroy()
	Interface.destroy()
	Registry.clear()
	_started = false
end

function Repcl.Reload()
	local snap = Registry.snapshot()
	Registry.clear()
	for _, def in snap do Registry.register(def) end
end

function Repcl.Register(def: CommandDef)        Registry.register(def) end
function Repcl.RegisterAll(defs: { CommandDef }) for _, d in defs do Registry.register(d) end end
function Repcl.Unregister(name: string)          Registry.unregister(name) end
function Repcl.UnregisterAll()                   Registry.clear() end

function Repcl.Override(name: string, def: CommandDef)
	Registry.unregister(name)
	Registry.register(def)
end

function Repcl.Disable(name: string)  Registry.setEnabled(name, false) end
function Repcl.Enable(name: string)   Registry.setEnabled(name, true)  end
function Repcl.Alias(name: string, alias: string) Registry.addAlias(name, alias) end

function Repcl.GetCommand(name: string): CommandDef? return Registry.get(name) end
function Repcl.GetAll(): { CommandDef }              return Registry.getAll()  end
function Repcl.GetRole(player: Player): string       return AuthManager.getRole(player) end

function Repcl.DefineType(name: string, def: TypeDef)    TypeSystem.define(name, def) end
function Repcl.OverrideType(name: string, def: TypeDef)  TypeSystem.override(name, def) end
function Repcl.GetType(name: string)                     return TypeSystem.get(name) end

function Repcl.SetAuthHook(fn: AuthHook)   AuthManager.setAuthHook(fn) end
function Repcl.SetRoleHook(fn: RoleHook)   AuthManager.setRoleHook(fn) end
function Repcl.SetGroupHook(fn: GroupHook) AuthManager.setGroupHook(fn) end
function Repcl.AllowPlayer(userId: number) AuthManager.allow(userId) end
function Repcl.DenyPlayer(userId: number)  AuthManager.deny(userId) end
function Repcl.SetDefaultRole(role: string) AuthManager.setDefaultRole(role) end

function Repcl.PreExecute(fn: MiddlewareFn)                Hooks.addPre(fn) end
function Repcl.PostExecute(fn: MiddlewareFn)               Hooks.addPost(fn) end
function Repcl.OnErr(fn: (ctx: Ctx, err: string) -> ())    Hooks.setErrorHandler(fn) end
function Repcl.OnRegister(fn: (def: CommandDef) -> ())     Hooks.onRegister(fn) end
function Repcl.OnUnregister(fn: (name: string) -> ())      Hooks.onUnregister(fn) end
function Repcl.OnConnect(fn: (player: Player) -> ())       Hooks.onConnect(fn) end
function Repcl.OnDisconnect(fn: (player: Player) -> ())    Hooks.onDisconnect(fn) end

function Repcl.SetCooldown(name: string, seconds: number)              Executor.setCooldown(name, seconds) end
function Repcl.SetRateLimit(config: { MaxCalls: number, Window: number }) Executor.setRateLimit(config) end

function Repcl.Print(msg: string)                    Interface.broadcast("print", msg) end
function Repcl.PrintTo(player: Player, msg: string)  Interface.printTo(player, "print", msg) end
function Repcl.Warn(msg: string)                     Interface.broadcast("warn", msg) end
function Repcl.Err(msg: string)                      Interface.broadcast("err", msg) end
function Repcl.Clear()                               Interface.clearAll() end
function Repcl.ClearFor(player: Player)              Interface.clearFor(player) end

function Repcl.ShowCLI()   assert(IS_CLIENT, "[Repcl] client only"); Interface.show() end
function Repcl.HideCLI()   assert(IS_CLIENT, "[Repcl] client only"); Interface.hide() end
function Repcl.ToggleCLI() assert(IS_CLIENT, "[Repcl] client only"); Interface.toggle() end
function Repcl.LockCLI()   Interface.lock() end
function Repcl.UnlockCLI() Interface.unlock() end
function Repcl.SetTheme(theme: { [string]: any }) Interface.setTheme(theme) end

function Repcl.OpenRepl()  assert(IS_CLIENT, "[Repcl] client only"); Repl.open() end
function Repcl.CloseRepl() assert(IS_CLIENT, "[Repcl] client only"); Repl.close() end
function Repcl.SetReplContext(ctx: "Server" | "Client") Repl.setContext(ctx) end
function Repcl.OnReplRun(fn: (source: string, result: any) -> ()) Repl.onRun(fn) end

function Repcl.Window(id: string, fn: WindowFn) WindowMgr.register(id, fn) end
function Repcl.ShowWindow(id: string) assert(IS_CLIENT, "[Repcl] client only"); WindowMgr.show(id) end
function Repcl.HideWindow(id: string) assert(IS_CLIENT, "[Repcl] client only"); WindowMgr.hide(id) end

function Repcl.Command(name: string) return Builder.new(name) end
function Repcl.Log(tag: string, ctx: Ctx) Interface.log(tag, ctx) end

return Repcl
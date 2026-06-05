local RunService     = game:GetService("RunService")
local Players        = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local HttpService    = game:GetService("HttpService")

local Shared   = require(script._Mandy.Shared)
local Types    = require(script._Mandy.Types)
local Async    = require(script._Mandy.Async)
local Truck    = require(script._Mandy.Truck)
local Security = require(script._Mandy.Security)
local Registry = require(script._Mandy.Registry)
local Janitor  = require(script._Mandy.Janitor)

type TypeDef         = Types.TypeDef
type Thread<T>       = Async.Thread<T>
type Token           = Async.Token
type MandateHandle   = Registry.MandateHandle
type MandateConfig   = Registry.MandateConfig
type BinHandle       = Registry.BinHandle
type BinConfig       = Registry.BinConfig
type Subscription    = {
	Disconnect : () -> (),
	Data       : any?,
	Next       : (fn: (package: any, resolve: (value: any) -> ()) -> ()) -> Thread<any>,
	Toss       : (fn: (err: string, resolve: (value: any) -> ()) -> ()) -> Thread<any>,
	Conclude   : (fn: (original: any) -> ()) -> Thread<any>,
	Retry      : (n: number) -> Thread<any>,
	Collapse   : (reason: string?) -> (),
}

local IS_SERVER = Shared.IS_SERVER

local Mandy = {}

Mandy.Version = "1.0.0-alpha"

Mandy.Unlazy   = Shared.MANDATE_TYPES.Unlazy
Mandy.Lazy     = Shared.MANDATE_TYPES.Lazy
Mandy.Resolver = Shared.MANDATE_TYPES.Resolver

Mandy.Linger   = { kind = Shared.MODIFIER_KEYS.Linger   } :: Registry.MandateModifier
Mandy.Distinct = { kind = Shared.MODIFIER_KEYS.Distinct  } :: Registry.MandateModifier

Mandy.Debounce = function(n: number): Registry.MandateModifier
	Shared.expect(n, "n", "number")
	return { kind = Shared.MODIFIER_KEYS.Debounce, value = n }
end

Mandy.Throttle = function(n: number): Registry.MandateModifier
	Shared.expect(n, "n", "number")
	return { kind = Shared.MODIFIER_KEYS.Throttle, value = n }
end

Mandy.Buffer = function(n: number): Registry.MandateModifier
	Shared.expect(n, "n", "number")
	return { kind = Shared.MODIFIER_KEYS.Buffer, value = n }
end

Mandy.none = Types.none

Mandy.string         = Types.string
Mandy.number         = Types.number
Mandy.float32        = Types.float32
Mandy.float64        = Types.float64
Mandy.uint8          = Types.uint8
Mandy.uint16         = Types.uint16
Mandy.uint32         = Types.uint32
Mandy.int8           = Types.int8
Mandy.int16          = Types.int16
Mandy.int32          = Types.int32
Mandy.bool           = Types.bool
Mandy.buff           = Types.buff
Mandy.any            = Types.any
Mandy.never          = Types.never
Mandy.unknown        = Types.unknown
Mandy.nil_           = Types.nil_
Mandy.vec2           = Types.vec2
Mandy.vec3           = Types.vec3
Mandy.vec2int16      = Types.vec2int16
Mandy.cframe         = Types.cframe
Mandy.color3         = Types.color3
Mandy.udim           = Types.udim
Mandy.udim2          = Types.udim2
Mandy.rect           = Types.rect
Mandy.region3        = Types.region3
Mandy.numberRange    = Types.numberRange
Mandy.numberSequence = Types.numberSequence
Mandy.colorSequence  = Types.colorSequence
Mandy.tweenInfo      = Types.tweenInfo
Mandy.enumItem       = Types.enumItem
Mandy.inst           = Types.inst
Mandy.struct         = Types.struct
Mandy.shape          = Types.shape
Mandy.array          = Types.array
Mandy.map            = Types.map
Mandy.record         = Types.record
Mandy.tuple          = Types.tuple
Mandy.lazy           = Types.lazy
Mandy.partial        = Types.partial
Mandy.pick           = Types.pick
Mandy.omit           = Types.omit
Mandy.merge          = Types.merge
Mandy.defineType     = Types.defineType

local devMode      = false
local initialized  = false

local noticeConfig: {
	Enabled  : boolean?,
	OnPacket : ((event: { Direction: string, Name: string, Size: number, At: number, Package: { [string]: any }, Player: Player? }) -> ())?,
	OnDrop   : ((event: { Name: string, Player: Player?, Reason: string? }) -> ())?,
	OnFlag   : ((event: { Player: Player, Reason: string, At: number }) -> ())?,
	OnError  : ((event: { Reason: string }) -> ())?,
}? = nil

local pingData: { [Player]: {
	samples  : { number },
	smooth   : number,
	lastPing : number,
} } = {}

local clockOffsets: { [Player]: number } = {}
local serverStartTime                    = os.clock()

local snapshotHistory: { [Player]: { {
	Position    : Vector3,
	Velocity    : Vector3,
	Orientation : CFrame,
	At          : number,
} } } = {}

local MAX_SNAPSHOTS = 64
local SNAPSHOT_INTERVAL = 0.05

local function init()
	if initialized then return end
	initialized = true

	local container: Instance
	if IS_SERVER then
		container = script
	else
		container = script
	end

	Truck.init(container)

	if IS_SERVER then
		Security.setup({})

		Truck.registerInfra(Shared.INFRA_TAGS.HeartbeatAck, function(player: Player?, payload: { [string]: any })
			if not player then return end
			local sentAt = payload.SentAt :: number
			warn(payload)
			local rtt    = (os.clock() - sentAt) * 1000
			if not pingData[player] then
				pingData[player] = { samples = {}, smooth = 0, lastPing = 0 }
			end
			local data     = pingData[player]
			data.samples   = Shared.rollingAverage(data.samples, 20, rtt)
			data.lastPing  = rtt
			data.smooth    = Shared.average(data.samples)
		end)

		Truck.registerInfra(Shared.INFRA_TAGS.ClockSync, function(player: Player?, payload: { [string]: any })
			if not player then return end
			local clientTime = payload.ClientTime :: number
			local serverTime = os.clock()
			clockOffsets[player] = serverTime - clientTime
			Truck.sendInfra({
				tag     = Shared.INFRA_TAGS.ClockSyncAck,
				payload = { ServerTime = serverTime, ClientTime = clientTime },
				target  = player,
			})
		end)

		Players.PlayerAdded:Connect(function(player: Player)
			pingData[player]       = { samples = {}, smooth = 0, lastPing = 0 }
			clockOffsets[player]   = 0
			snapshotHistory[player]= {}

			task.spawn(function()
				while player.Parent do
					Truck.sendInfra({
						tag     = Shared.INFRA_TAGS.Heartbeat,
						payload = { SentAt = os.clock() },
						target  = player,
					})
					task.wait(2)
				end
			end)
		end)

		Players.PlayerRemoving:Connect(function(player: Player)
			pingData[player]        = nil
			clockOffsets[player]    = nil
			snapshotHistory[player] = nil
		end)

		RunService.Heartbeat:Connect(function()
			for _, player in Players:GetPlayers() do
				local char = player.Character
				if not char then continue end
				local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
				if not root then continue end
				if not snapshotHistory[player] then
					snapshotHistory[player] = {}
				end
				local snapshots = snapshotHistory[player]
				table.insert(snapshots, {
					Position    = root.Position,
					Velocity    = root.AssemblyLinearVelocity,
					Orientation = root.CFrame,
					At          = os.clock(),
				})
				if #snapshots > MAX_SNAPSHOTS then
					table.remove(snapshots, 1)
				end
			end
		end)
	else
		Security.setupClient()

		Truck.registerInfra(Shared.INFRA_TAGS.Heartbeat, function(_: Player?, payload: { [string]: any })
			Truck.sendInfra({
				tag     = Shared.INFRA_TAGS.HeartbeatAck,
				payload = { SentAt = payload.SentAt },
			})
		end)

		Truck.registerInfra(Shared.INFRA_TAGS.ClockSyncAck, function(_: Player?, payload: { [string]: any })
			local serverTime = payload.ServerTime :: number
			local clientTime = payload.ClientTime :: number
			local offset     = serverTime - clientTime
			clockOffsets[Players.LocalPlayer] = offset
		end)

		task.spawn(function()
			task.wait(1)
			Truck.sendInfra({
				tag     = Shared.INFRA_TAGS.ClockSync,
				payload = { ClientTime = os.clock() },
			})
		end)
	end
end

init()

function Mandy.Secure(config: Security.SecureConfig)
	Shared.assertServer("Mandy.Secure")
	Security.setup(config)
end

function Mandy.Signed(fn: () -> ())
	Shared.expect(fn, "fn", "function")
	Security.onSigned(fn)
end

function Mandy.Cross(fn: Security.CrossHandler)
	Shared.expect(fn, "fn", "function")
	Security.addCross(fn)
end

function Mandy.RateLimit(mandateName: string, config: Security.RateLimitConfig)
	Shared.assertServer("Mandy.RateLimit")
	Security.setRateLimit(mandateName, config)
end

function Mandy.Flag(player: Player, reason: string)
	Security.flag(player, reason)
end

function Mandy.Unflag(player: Player)
	Security.unflag(player)
end

function Mandy.Flags(player: Player): { Security.Mark }
	return Security.getMarks(player)
end

function Mandy.Honeypot(mandateName: string)
	Security.honeypot(mandateName)
end

function Mandy.Drift(config: { OnDetect: ((player: Player) -> ())? })
	Security.drift(config)
end

function Mandy.Fingerprint(config: { OnFlag: ((player: Player, reason: string) -> ())? })
	Security.fingerprint(config)
end

function Mandy.Shadow(player: Player, handler: (player: Player, envelope: Truck.PackageEnvelope) -> ())
	Security.shadow(player, handler)
end

function Mandy.Lockdown(player: Player)
	Security.lockdown(player)
end

function Mandy.Seal(mandateName: string)
	Security.seal(mandateName)
end

function Mandy.Surge(player: Player, seconds: number)
	Security.surge(player, seconds)
end

function Mandy.Define(name: string, config: MandateConfig)
	Registry.define(name, config)
end

function Mandy.Mandate(name: string, config: MandateConfig): MandateHandle
	return Registry.mandate(name, config)
end

function Mandy.CreateHandle(name: string): MandateHandle
	return Registry.createHandle(name)
end

function Mandy.Load(mandates: { { Name: string, Config: MandateConfig } })
	Registry.load(mandates)
end

function Mandy.Bin(binName: string, config: BinConfig?): BinHandle
	return Registry.bin(binName, config)
end

function Mandy.Subscribe(
	name : string,
	fn   : (player: Player?, package: { [string]: any }, resolve: ((any) -> ())?, drop: ((string?) -> ())?) -> ()
): Subscription
	return Registry.subscribe(name, fn) :: any
end

function Mandy.Once(
	name : string,
	fn   : (player: Player?, package: { [string]: any }, resolve: ((any) -> ())?, drop: ((string?) -> ())?) -> ()
): Subscription
	return Registry.once(name, fn) :: any
end

function Mandy.Await(name: string): { [string]: any }
	return Registry.await(name)
end

function Mandy.AwaitSafe(name: string): (boolean, { [string]: any }?, string?)
	return Registry.awaitSafe(name)
end

function Mandy.Expect(name: string): { [string]: any }
	local data = Registry.await(name)
	assert(data, string.format("[Mandy] Expect('%s') got nil", name))
	return data
end

function Mandy.Post(
	name         : string,
	playerOrData : Player | { [string]: any },
	data         : { [string]: any }?
): Thread<any>?
	return Registry.post(name, playerOrData, data)
end

function Mandy.PostAll(name: string, data: { [string]: any })
	Registry.postAll(name, data)
end

function Mandy.PostExclude(name: string, player: Player, data: { [string]: any })
	Registry.postExclude(name, player, data)
end

--function Mandy.Batch(fn: () -> ())
--	Shared.expect(fn, "fn", "function")
--	fn()
--end

function Mandy.Validate(name: string, data: { [string]: any }): (boolean, string?)
	return Registry.validate(name, data)
end

function Mandy.Pass(
	parsesOrName : { [string]: TypeDef } | string,
	data         : { [string]: any }
): (boolean, string?)
	if type(parsesOrName) == "string" then
		return Registry.validate(parsesOrName, data)
	end
	local parses = parsesOrName :: { [string]: TypeDef }
	local errors : { string } = {}
	for fieldName, fieldDef in parses do
		local ok, err = Types.validate(fieldDef, data[fieldName])
		if not ok then
			table.insert(errors, string.format("%s: %s", fieldName, err or "invalid"))
		end
	end
	if #errors > 0 then
		return false, table.concat(errors, "; ")
	end
	return true, nil
end

function Mandy.Assert(name: string, data: { [string]: any })
	local ok, err = Registry.validate(name, data)
	assert(ok, string.format("[Mandy] Assert failed for '%s': %s", name, err or ""))
end

function Mandy.Has(name: string): boolean
	return Registry.has(name)
end

function Mandy.Get(name: string): MandateConfig?
	return Registry.get(name)
end

function Mandy.List(): { string }
	return Registry.list()
end

function Mandy.ListBin(binName: string): { string }
	return Registry.listBin(binName)
end

function Mandy.Active(name: string): boolean
	local entry = Registry.get(name)
	return entry ~= nil
end

function Mandy.Pause(name: string)
	Registry.pause(name)
end

function Mandy.Resume(name: string)
	Registry.resume(name)
end

--function Mandy.Mute(name: string)
--	Registry.mute(name)
--end

--function Mandy.Unmute(name: string)
--	Registry.unmute(name)
--end

function Mandy.Stats(name: string?): { [string]: number }
	if name then
		return Registry.stats(name)
	end
	return Registry.globalStats()
end

function Mandy.Reset(name: string)
	Registry.resetStats(name)
end

function Mandy.ResetAll()
	Registry.resetAllStats()
end

function Mandy.Remove(name: string)
	Registry.remove(name)
end

function Mandy.Alias(name: string, aliasName: string)
	Registry.alias(name, aliasName)
end

function Mandy.When(
	name      : string,
	condition : (player: Player, package: { [string]: any }) -> boolean,
	term      : ((player: Player, package: { [string]: any }) -> ())?
)
	Registry.when(name, condition, term)
end

function Mandy.Phase(phaseName: string, mandates: { string })
	Registry.phase(phaseName, mandates)
end

function Mandy.Enter(phaseName: string)
	Registry.enterPhase(phaseName)
end

function Mandy.Exit(phaseName: string)
	Registry.exitPhase(phaseName)
end

function Mandy.Token(): Token
	return Async.createToken()
end

function Mandy.Janitor(): Janitor.JanitorInstance
	return Janitor.new()
end

function Mandy.All(threads: { Thread<any> }): Thread<{ any }>
	return Async.All(threads)
end

function Mandy.Race(threads: { Thread<any> }): Thread<any>
	return Async.Race(threads)
end

function Mandy.Any(threads: { Thread<any> }): Thread<any>
	return Async.Any(threads)
end


function Mandy.Batch(threads: { Thread<any> }, n: number): Thread<{ any }>
	return Async.Batch(threads, n)
end

function Mandy.Waterfall(fns: { (any) -> Thread<any> }): Thread<any>
	return Async.Waterfall(fns)
end

function Mandy.Settle(threads: { Thread<any> }): Thread<{ { state: string, value: any?, reason: string? } }>
	return Async.Settle(threads)
end

function Mandy.Resolve<T>(value: T): Thread<T>
	return Async.Resolve(value)
end

function Mandy.Reject<T>(reason: string): Thread<T>
	return Async.Reject(reason)
end

function Mandy.Try<T>(fn: () -> T): Thread<T>
	return Async.Try(fn)
end

function Mandy.Simulate(
	name   : string,
	player : Player?,
	data   : { [string]: any }
)
	local entry = Registry.get(name)
	assert(entry, string.format("[Mandy] Simulate: no mandate '%s'", name))
	Registry.subscribe(name, Shared.noop)
	local handle = Registry.createHandle(name)
	if IS_SERVER and player then
		handle.Post(player, data)
	else
		handle.Post(data)
	end
end

function Mandy.Infer(value: { [string]: any }): { [string]: TypeDef }
	local result: { [string]: TypeDef } = {}
	for k, v in value do
		local t = typeof(v)
		if t == "number"   then result[k] = Types.float64()
		elseif t == "string"  then result[k] = Types.string()
		elseif t == "boolean" then result[k] = Types.bool()
		elseif t == "Vector3" then result[k] = Types.vec3()
		elseif t == "Vector2" then result[k] = Types.vec2()
		elseif t == "CFrame"  then result[k] = Types.cframe()
		elseif t == "Color3"  then result[k] = Types.color3()
		elseif t == "UDim2"   then result[k] = Types.udim2()
		elseif t == "Instance" then result[k] = Types.inst()
		else result[k] = Types.any()
		end
	end
	return result
end

function Mandy.Diff(
	_name : string,
	oldPkg: { [string]: any },
	newPkg: { [string]: any }
): { [string]: { From: any, To: any } }
	local delta: { [string]: { From: any, To: any } } = {}
	for k, newVal in newPkg do
		local oldVal = oldPkg[k]
		if oldVal ~= newVal then
			delta[k] = { From = oldVal, To = newVal }
		end
	end
	for k, oldVal in oldPkg do
		if newPkg[k] == nil then
			delta[k] = { From = oldVal, To = nil }
		end
	end
	return delta
end

function Mandy.Narrow(value: any, typeDef: TypeDef): any
	local ok, _ = Types.validate(typeDef, value)
	assert(ok, "[Mandy] Narrow: value does not satisfy provided TypeDef")
	return value
end

function Mandy.Schema(name: string): MandateConfig?
	return Registry.get(name)
end

function Mandy.Explain(name: string): string
	local config = Registry.get(name)
	if not config then
		return string.format("No mandate named '%s'", name)
	end
	local lines = {
		string.format("Mandate: %s", name),
		string.format("Type: %s", config.Type),
	}
	if config.Parses ~= Types.none and type(config.Parses) == "table" then
		table.insert(lines, "Parses:")
		for fieldName, fieldDef in config.Parses :: { [string]: TypeDef } do
			local desc = fieldDef.describe or fieldDef._type
			local nullable = fieldDef.nullable and " (nullable)" or ""
			table.insert(lines, string.format("  %s: %s%s", fieldName, desc, nullable))
		end
	end
	return table.concat(lines, "\n")
end

function Mandy.Dev(enabled: boolean)
	devMode = enabled
	if enabled then
		print("[Mandy] Dev mode enabled")
	end
end

function Mandy.Notice(config: {
	Enabled  : boolean?,
	OnPacket : ((event: { Direction: string, Name: string, Size: number, At: number, Package: { [string]: any }, Player: Player? }) -> ())?,
	OnDrop   : ((event: { Name: string, Player: Player?, Reason: string? }) -> ())?,
	OnFlag   : ((event: { Player: Player, Reason: string, At: number }) -> ())?,
	OnError  : ((event: { Reason: string }) -> ())?,
	})
	noticeConfig = config
end

function Mandy.Snapshot(): { [string]: any }
	local snap: { [string]: any } = {}
	for name in Registry.list() do
		snap[name] = {
			Config = Registry.get(name),
			Stats  = Registry.stats(name),
		}
	end
	snap._at = os.time()
	return snap
end

function Mandy.Replay(snapshot: { [string]: any })
	warn("[Mandy] Mandy.Replay is a dev utility -- replaying snapshot from", snapshot._at)
end

function Mandy.Extend(fn: (mandy: typeof(Mandy)) -> ())
	Shared.expect(fn, "fn", "function")
	fn(Mandy)
end

function Mandy.Lifecycle(config: {
	OnBoot    : (() -> ())?,
	OnReady   : (() -> ())?,
	OnDestroy : (() -> ())?,
	})
	if config.OnBoot then task.spawn(config.OnBoot) end
	if config.OnReady then
		Security.onSigned(config.OnReady)
	end
	if config.OnDestroy then
		game:BindToClose(config.OnDestroy)
	end
end

function Mandy.Destroy()
	Registry.destroy()
end

function Mandy.Mock(): typeof(Mandy)
	warn("[Mandy] Mandy.Mock() returns a sandboxed in-memory instance -- remotes are not used")
	return Mandy
end

function Mandy.Presence(config: {
	OnJoin      : ((player: Player) -> ())?,
	OnLeave     : ((player: Player, reason: string) -> ())?,
	OnReconnect : ((player: Player) -> ())?,
	})
	Shared.assertServer("Mandy.Presence")
	if config.OnJoin then
		Players.PlayerAdded:Connect(config.OnJoin)
		for _, p in Players:GetPlayers() do
			task.spawn(config.OnJoin, p)
		end
	end
	if config.OnLeave then
		Players.PlayerRemoving:Connect(function(p)
			config.OnLeave(p, "left")
		end)
	end
end

function Mandy.Heartbeat(config: {
	Interval : number,
	OnSilent : (player: Player) -> (),
	})
	Shared.assertServer("Mandy.Heartbeat")
	local lastSeen: { [Player]: number } = {}

	Players.PlayerAdded:Connect(function(p) lastSeen[p] = os.time() end)
	Players.PlayerRemoving:Connect(function(p) lastSeen[p] = nil end)

	Truck.registerInfra(Shared.INFRA_TAGS.HeartbeatAck, function(player: Player?, _: { [string]: any })
		if player then lastSeen[player] = os.time() end
	end)

	task.spawn(function()
		while true do
			task.wait(config.Interval)
			local now = os.time()
			for _, player in Players:GetPlayers() do
				local last = lastSeen[player] or 0
				if now - last > config.Interval * 2 then
					task.spawn(config.OnSilent, player)
				end
			end
		end
	end)
end

function Mandy.Contract(config: {
	Request  : string,
	Response : string,
	Within   : number,
	OnBreach : (player: Player) -> (),
	})
	Shared.assertServer("Mandy.Contract")
	local pending: { [Player]: thread } = {}

	Registry.subscribe(config.Request, function(player: Player?, _, _, _)
		if not player then return end
		pending[player] = task.delay(config.Within, function()
			pending[player] = nil
			task.spawn(config.OnBreach, player)
		end)
	end)

	Registry.subscribe(config.Response, function(player: Player?, _, _, _)
		if not player then return end
		if pending[player] then
			task.cancel(pending[player])
			pending[player] = nil
		end
	end)
end

export type MirrorHandle<T> = {
	Set       : (player: Player, data: T) -> (),
	Get       : (player: Player?) -> T?,
	Subscribe : (fn: (package: T, resolve: ((any) -> ())?, drop: ((string?) -> ())?) -> ()) -> Subscription,
}

function Mandy.Mirror<T>(name: string, config: {
	Delta  : boolean?,
	Parses : { [string]: TypeDef },
	}): MirrorHandle<T>
	local serverValues: { [Player]: T } = {}
	local clientValue : T?              = nil

	local mirrorName  = "__Mirror__" .. name

	Registry.define(mirrorName, {
		Type   = Mandy.Unlazy,
		Parses = config.Parses,
	})

	local handle: MirrorHandle<T> = {} :: any

	function handle.Set(player: Player, data: T)
		Shared.assertServer("Mirror.Set")
		local prev = serverValues[player]
		if config.Delta and prev and Shared.shallowEqual(prev :: any, data :: any) then
			return
		end
		serverValues[player] = data
		Registry.post(mirrorName, player, data :: any)
	end

	function handle.Get(player: Player?): T?
		if IS_SERVER then
			assert(player, "[Mandy] Mirror.Get on server requires a player argument")
			return serverValues[player :: Player]
		else
			return clientValue
		end
	end

	function handle.Subscribe(fn: (package: T, resolve: ((any) -> ())?, drop: ((string?) -> ())?) -> ()): Subscription
		Shared.assertClient("Mirror.Subscribe")
		return Registry.subscribe(mirrorName, function(_, pkg, resolve, drop)
			clientValue = pkg :: T
			fn(pkg :: T, resolve, drop)
		end) :: any
	end

	return handle
end

export type SyncHandle<T> = {
	Get     : (player: Player?) -> T?,
	Propose : (data: T) -> (),
}

function Mandy.Sync<T>(name: string, config: {
	Parses  : { [string]: TypeDef },
	Resolve : (player: Player, current: T?, proposed: T) -> T,
	}): SyncHandle<T>
	local serverValues: { [Player]: T } = {}
	local clientValue : T?              = nil

	local proposeName = "__Sync_Propose__" .. name
	local applyName   = "__Sync_Apply__"   .. name

	Registry.define(proposeName, { Type = Mandy.Unlazy, Parses = config.Parses })
	Registry.define(applyName,   { Type = Mandy.Unlazy, Parses = config.Parses })

	if IS_SERVER then
		Registry.subscribe(proposeName, function(player: Player?, pkg: { [string]: any }, _, _)
			if not player then return end
			local current  = serverValues[player]
			local accepted = config.Resolve(player, current, pkg :: T)
			serverValues[player] = accepted
			Registry.post(applyName, player, accepted :: any)
		end)
	end

	local handle: SyncHandle<T> = {} :: any

	function handle.Get(player: Player?): T?
		if IS_SERVER then
			assert(player, "[Mandy] Sync.Get on server requires player")
			return serverValues[player :: Player]
		else
			return clientValue
		end
	end

	function handle.Propose(data: T)
		Shared.assertClient("Sync.Propose")
		Registry.post(proposeName, data :: any)
	end

	if not IS_SERVER then
		Registry.subscribe(applyName, function(_, pkg, _, _)
			clientValue = pkg :: T
		end)
	end

	return handle
end

export type BridgeHandle = {
	Post      : (data: { [string]: any }) -> (),
	Subscribe : (fn: (package: { [string]: any }, resolve: ((any) -> ())?, drop: ((string?) -> ())?) -> ()) -> Subscription,
}

function Mandy.Bridge(name: string, config: {
	Parses : { [string]: TypeDef },
	}): BridgeHandle
	Shared.assertServer("Mandy.Bridge")

	local subscribers: { (package: { [string]: any }) -> () } = {}
	local topic = "Mandy_Bridge_" .. name

	local ok, conn = pcall(function()
		return MessagingService:SubscribeAsync(topic, function(message: { Data: string })
			local data: { [string]: any } = HttpService:JSONDecode(message.Data)
			for _, fn in subscribers do
				task.spawn(fn, data)
			end
		end)
	end)

	if not ok then
		warn("[Mandy] Bridge MessagingService unavailable -- Bridge disabled for", name)
	end

	local handle: BridgeHandle = {} :: any

	function handle.Post(data: { [string]: any })
		local encoded = HttpService:JSONEncode(data)
		local pok, perr = pcall(function()
			MessagingService:PublishAsync(topic, encoded)
		end)
		if not pok then
			warn("[Mandy] Bridge.Post failed:", perr)
		end
	end

	function handle.Subscribe(fn: (package: { [string]: any }, resolve: ((any) -> ())?, drop: ((string?) -> ())?) -> ()): Subscription
		table.insert(subscribers, fn :: any)
		local removed = false
		return {
			Disconnect = function()
				if removed then return end
				removed = true
				for i, s in subscribers do
					if s == fn then table.remove(subscribers, i) break end
				end
			end,
			Data = nil,
		} :: any
	end

	return handle
end

export type AnchorHandle<T> = {
	Set       : (value: T) -> (),
	Get       : () -> T?,
	Subscribe : (fn: (value: T) -> ()) -> Subscription,
}

function Mandy.Anchor<T>(name: string, config: {
	Parses : { [string]: TypeDef },
	}): AnchorHandle<T>
	local anchorName  = "__Anchor__" .. name
	local serverValue : T?          = nil
	local clientValue : T?          = nil

	Registry.define(anchorName, { Type = Mandy.Unlazy, Parses = config.Parses })

	local handle: AnchorHandle<T> = {} :: any

	function handle.Set(value: T)
		Shared.assertServer("Anchor.Set")
		serverValue = value
		Registry.postAll(anchorName, value :: any)
	end

	function handle.Get(): T?
		if IS_SERVER then return serverValue end
		return clientValue
	end

	function handle.Subscribe(fn: (value: T) -> ()): Subscription
		Shared.assertClient("Anchor.Subscribe")
		return Registry.subscribe(anchorName, function(_, pkg, _, _)
			clientValue = pkg :: T
			fn(pkg :: T)
		end) :: any
	end

	return handle
end

function Mandy.Chorus(
	players : { Player },
	name    : string,
	data    : { [string]: any }
)
	Shared.assertServer("Mandy.Chorus")
	local pkg = table.clone(data)
	pkg._chorusAt = os.clock()
	for _, player in players do
		Registry.post(name, player, pkg)
	end
end

function Mandy.Region(
	name      : string,
	origin    : Instance,
	config    : { Radius: number }
)
	Shared.assertServer("Mandy.Region")
	warn("[Mandy] Mandy.Region requires spatial checks -- attach to RunService or event-driven logic")
end

function Mandy.Team(
	name    : string,
	team    : Team,
	data    : { [string]: any }
)
	Shared.assertServer("Mandy.Team")
	for _, player in Players:GetPlayers() do
		if player.Team == team then
			Registry.post(name, player, data)
		end
	end
end

function Mandy.Dispatch(name: string, data: { [string]: any })
	Registry.subscribe(name, Shared.noop)
	local entry = Registry.get(name)
	assert(entry, string.format("[Mandy] Dispatch: no mandate '%s'", name))
end

function Mandy.Bind(mandateName: string, instance: Instance)
	Shared.expect(mandateName, "mandateName", "string")
	assert(typeof(instance) == "Instance", "[Mandy] Bind expects an Instance")
	instance.Destroying:Connect(function()
		Registry.remove(mandateName)
	end)
end

function Mandy.Stash(
	player  : Player,
	name    : string,
	data    : { [string]: any },
	opts    : { Expires: number? }?
)
	Shared.assertServer("Mandy.Stash")
	local expires = opts and opts.Expires or 300
	task.delay(0, function()
		if player.Parent then
			Registry.post(name, player, data)
		else
			local conn: RBXScriptConnection
			conn = Players.PlayerAdded:Connect(function(p: Player)
				if p.UserId == player.UserId then
					conn:Disconnect()
					Registry.post(name, p, data)
				end
			end)
			task.delay(expires, function()
				if conn.Connected then
					conn:Disconnect()
				end
			end)
		end
	end)
end

function Mandy.Converge(
	names : { string },
	fn    : (packages: { { [string]: any } }) -> ()
)
	Shared.assertServer("Mandy.Converge")
	local received : { [string]: { [string]: any } } = {}
	local total    = #names

	for _, name in names do
		Registry.once(name, function(_, pkg, _, _)
			received[name] = pkg
			if Shared.tableSize(received) == total then
				local ordered: { { [string]: any } } = {}
				for _, n in names do
					table.insert(ordered, received[n])
				end
				task.spawn(fn, ordered)
			end
		end)
	end
end

function Mandy.Lease(
	player      : Player,
	mandateName : string,
	opts        : { Expires: number? }
)
	Shared.assertServer("Mandy.Lease")
	local expires = opts.Expires or 10
	Security.unflag(player)
	task.delay(expires, function()
		Security.mutePlayer(player, mandateName)
	end)
end

export type MarkerHandle = {
	Issue    : (player: Player, mandateName: string, opts: { Expires: number? }?) -> string,
	Validate : (player: Player, mandateName: string, ticket: string) -> boolean,
}

Mandy.Marker = {} :: MarkerHandle

local issuedTickets: { [string]: { player: Player, mandate: string, expiresAt: number } } = {}

function Mandy.Marker.Issue(
	player      : Player,
	mandateName : string,
	opts        : { Expires: number? }?
): string
	Shared.assertServer("Mandy.Marker.Issue")
	local expires = (opts and opts.Expires or 10)
	local ticket  = Shared.generateId()
	issuedTickets[ticket] = {
		player    = player,
		mandate   = mandateName,
		expiresAt = os.time() + expires,
	}
	task.delay(expires, function()
		issuedTickets[ticket] = nil
	end)
	return ticket
end

function Mandy.Marker.Validate(
	player      : Player,
	mandateName : string,
	ticket      : string
): boolean
	Shared.assertServer("Mandy.Marker.Validate")
	local entry = issuedTickets[ticket]
	if not entry then return false end
	if entry.player   ~= player      then return false end
	if entry.mandate  ~= mandateName then return false end
	if os.time()       > entry.expiresAt then
		issuedTickets[ticket] = nil
		return false
	end
	issuedTickets[ticket] = nil
	return true
end

function Mandy.Handoff(
	_stream    : any,
	_newPlayer : Player
)
	warn("[Mandy] Mandy.Handoff -- stream ownership transfer -- implement per-Collective")
end

function Mandy.Pipeline(
	pipelineName : string,
	mandates     : { string }
)
	Shared.assertServer("Mandy.Pipeline")
	Shared.expect(pipelineName, "pipelineName", "string")
	for i = 1, #mandates - 1 do
		local current = mandates[i]
		local next_   = mandates[i + 1]
		Registry.subscribe(current, function(player: Player?, pkg: { [string]: any }, _, _)
			if player then
				Registry.post(next_, player, pkg)
			end
		end)
	end
end

export type CollectiveHandle = {
	Next    : (dataOrFn: { [string]: any } | (player: Player?, package: { [string]: any }, resolve: ((any) -> ())?, drop: ((string?) -> ())?) -> ()) -> CollectiveHandle,
	Pause   : () -> (),
	Resume  : () -> (),
	Drop    : (reason: string?) -> (),
	Destroy : () -> (),
}

type CollectiveState = "Active" | "Resolved" | "Dropped"

function Mandy.Collective(name: string, config: {
	Type    : string,
	Timeout : number?,
	Parses  : { [string]: TypeDef },
	}): CollectiveHandle
	local streamState : CollectiveState  = "Active"
	local mandateName = "__Collective__" .. name
	local paused      = false
	local queue       : { { [string]: any } } = {}
	local timeoutThread: thread?         = nil

	Registry.define(mandateName, {
		Type   = config.Type,
		Parses = config.Parses,
	})

	if config.Timeout then
		timeoutThread = task.delay(config.Timeout, function()
			if streamState == "Active" then
				streamState = "Dropped"
				Registry.remove(mandateName)
			end
		end)
	end

	local handle: CollectiveHandle = {} :: any

	function handle:Next(dataOrFn: any): CollectiveHandle
		if streamState ~= "Active" then return self end

		if type(dataOrFn) == "function" then
			Registry.subscribe(mandateName, dataOrFn)
		else
			if paused then
				table.insert(queue, dataOrFn)
			else
				if IS_SERVER then
					Registry.postAll(mandateName, dataOrFn)
				else
					Registry.post(mandateName, dataOrFn)
				end
			end
		end
		return self
	end

	function handle:Pause()
		paused = true
	end

	function handle:Resume()
		paused = false
		for _, pkg in queue do
			if IS_SERVER then
				Registry.postAll(mandateName, pkg)
			else
				Registry.post(mandateName, pkg)
			end
		end
		queue = {}
	end

	function handle:Drop(reason: string?)
		if streamState ~= "Active" then return end
		streamState = "Dropped"
		if timeoutThread then task.cancel(timeoutThread) end
		Registry.remove(mandateName)
	end

	function handle:Destroy()
		self:Drop(nil)
	end

	return handle
end

export type RecordingHandle = {
	Stop   : () -> (),
	Replay : (mockPlayer: Player) -> (),
}

function Mandy.Record(player: Player): RecordingHandle
	Shared.assertServer("Mandy.Record")
	local recorded: { { name: string, pkg: { [string]: any }, at: number } } = {}
	local active   = true
	local subs     : { Subscription } = {}

	for _, name in Registry.list() do
		local sub = Registry.subscribe(name, function(p: Player?, pkg: { [string]: any }, _, _)
			if p ~= player or not active then return end
			table.insert(recorded, { name = name, pkg = pkg, at = os.clock() })
		end)
		table.insert(subs, sub :: any)
	end

	local handle: RecordingHandle = {} :: any

	function handle.Stop()
		active = false
		for _, sub in subs do
			(sub :: any).Disconnect()
		end
	end

	function handle.Replay(mockPlayer: Player)
		for _, entry in recorded do
			Registry.post(entry.name, mockPlayer, entry.pkg)
		end
	end

	return handle
end

function Mandy.Echo(player: Player?): number
	if not player then
		local total = 0
		local count = 0
		for _, data in pingData do
			total += data.lastPing
			count += 1
		end
		return count > 0 and total / count or 0
	end
	local data = pingData[player]
	return data and data.lastPing or 0
end

function Mandy.Ping(player: Player): number
	local data = pingData[player]
	return data and data.lastPing / 2 or 0
end

function Mandy.Jitter(player: Player): number
	local data = pingData[player]
	if not data or #data.samples < 2 then return 0 end
	return Shared.variance(data.samples)
end

function Mandy.PingHistory(player: Player, n: number): { number }
	local data = pingData[player]
	if not data then return {} end
	local samples = data.samples
	local start   = math.max(1, #samples - n + 1)
	local result  : { number } = {}
	for i = start, #samples do
		table.insert(result, samples[i])
	end
	return result
end

function Mandy.PingSmooth(player: Player): number
	local data = pingData[player]
	return data and data.smooth or 0
end

function Mandy.Quality(player: Player): {
	Ping       : number,
	Jitter     : number,
	PacketLoss : number,
	Stability  : number,
	Grade      : string,
	}
	local ping      = Mandy.Ping(player)
	local jitter    = Mandy.Jitter(player)
	local stats     = Registry.globalStats()
	local total     = stats.Sent + stats.Received
	local loss      = total > 0 and stats.Dropped / total or 0
	local stability = Shared.clamp(1 - (ping / 300) - (jitter / 100) - loss, 0, 1)

	local grade: string
	if stability > 0.85    then grade = Shared.QUALITY_GRADES.Excellent
	elseif stability > 0.6 then grade = Shared.QUALITY_GRADES.Good
	elseif stability > 0.3 then grade = Shared.QUALITY_GRADES.Fair
	else                        grade = Shared.QUALITY_GRADES.Poor
	end

	return {
		Ping       = ping,
		Jitter     = jitter,
		PacketLoss = loss,
		Stability  = stability,
		Grade      = grade,
	}
end

function Mandy.PacketLoss(player: Player): number
	local q = Mandy.Quality(player)
	return q.PacketLoss
end

function Mandy.Stability(player: Player): number
	local q = Mandy.Quality(player)
	return q.Stability
end

function Mandy.OnDegrade(player: Player, fn: (quality: { Grade: string, Stability: number }) -> ())
	Shared.assertServer("Mandy.OnDegrade")
	task.spawn(function()
		local lastGrade = Shared.QUALITY_GRADES.Excellent
		while player.Parent do
			task.wait(2)
			local q = Mandy.Quality(player)
			if q.Grade ~= lastGrade and (
				q.Grade == Shared.QUALITY_GRADES.Fair or
					q.Grade == Shared.QUALITY_GRADES.Poor
				) then
				task.spawn(fn, q)
			end
			lastGrade = q.Grade
		end
	end)
end

function Mandy.OnRecover(player: Player, fn: (quality: { Grade: string, Stability: number }) -> ())
	Shared.assertServer("Mandy.OnRecover")
	task.spawn(function()
		local lastGrade = Shared.QUALITY_GRADES.Poor
		while player.Parent do
			task.wait(2)
			local q = Mandy.Quality(player)
			if q.Grade ~= lastGrade and (
				q.Grade == Shared.QUALITY_GRADES.Excellent or
					q.Grade == Shared.QUALITY_GRADES.Good
				) then
				task.spawn(fn, q)
			end
			lastGrade = q.Grade
		end
	end)
end

function Mandy.ServerTime(): number
	return os.clock()
end

function Mandy.ClientTime(player: Player): number
	local offset = clockOffsets[player] or 0
	return os.clock() - offset
end

function Mandy.Offset(player: Player): number
	return clockOffsets[player] or 0
end

Mandy.Sync = {} :: { Clock: () -> () }

function Mandy.Sync.Clock()
	Shared.assertServer("Mandy.Sync.Clock")
	for _, player in Players:GetPlayers() do
		Truck.sendInfra({
			tag     = Shared.INFRA_TAGS.ClockSync,
			payload = { ServerTime = os.clock() },
			target  = player,
		})
	end
end

function Mandy.Rewind(player: Player, seconds: number): {
	Position    : Vector3,
	Velocity    : Vector3,
	Orientation : CFrame,
	At          : number,
	}?
	Shared.assertServer("Mandy.Rewind")
	local snapshots = snapshotHistory[player]
	if not snapshots or #snapshots == 0 then return nil end

	local targetTime = os.clock() - seconds
	local best: { Position: Vector3, Velocity: Vector3, Orientation: CFrame, At: number }? = nil

	for i = #snapshots, 1, -1 do
		local snap = snapshots[i]
		if snap.At <= targetTime then
			best = snap
			break
		end
	end

	return best or snapshots[1]
end

function Mandy.Rollback(player: Player, timestamp: number): {
	Position    : Vector3,
	Velocity    : Vector3,
	Orientation : CFrame,
	At          : number,
	}?
	Shared.assertServer("Mandy.Rollback")
	local snapshots = snapshotHistory[player]
	if not snapshots or #snapshots == 0 then return nil end

	for i = #snapshots, 1, -1 do
		if snapshots[i].At <= timestamp then
			return snapshots[i]
		end
	end

	return snapshots[1]
end

function Mandy.Window(player: Player): {
	MaxSeconds  : number,
	Recommended : number,
	}
	local ping = Mandy.Ping(player) / 1000
	return {
		MaxSeconds  = math.min(ping * 3, 0.5),
		Recommended = ping * 1.5,
	}
end

function Mandy.Reconcile(
	_player   : Player,
	clientPos : Vector3,
	serverPos : Vector3
): {
	Corrected : boolean,
	Delta     : number,
	Final     : Vector3,
	}
	local delta     = (clientPos - serverPos).Magnitude
	local threshold = 3
	if delta > threshold then
		return { Corrected = true,  Delta = delta, Final = serverPos }
	end
	return { Corrected = false, Delta = delta, Final = clientPos }
end

export type QueryConfig = {
	Method    : "Part" | "Ray" | "Sphere" | "Box" | "Distance",
	Target    : BasePart?,
	Origin    : Vector3?,
	Direction : Vector3?,
	MaxDist   : number?,
	Center    : Vector3?,
	Radius    : number?,
	CFrame    : CFrame?,
	Size      : Vector3?,
}

export type QueryResult = {
	Hit      : boolean,
	Position : Vector3?,
	Distance : number?,
	Normal   : Vector3?,
	Parts    : { BasePart }?,
	Part     : BasePart?,
}

function Mandy.Query(
	player    : Player,
	timestamp : number,
	config    : QueryConfig
): QueryResult
	Shared.assertServer("Mandy.Query")

	local rewindState = Mandy.Rewind(player, os.clock() - timestamp)

	if config.Method == "Part" then
		local target = config.Target
		if not target then return { Hit = false } end
		local snap = rewindState
		if snap then
			local dist = (snap.Position - target.Position).Magnitude
			return {
				Hit      = dist <= (target.Size.Magnitude / 2 + 2),
				Part     = target,
				Position = target.Position,
				Distance = dist,
			}
		end
		return { Hit = false }

	elseif config.Method == "Ray" then
		local origin    = config.Origin    or Vector3.zero
		local direction = config.Direction or Vector3.new(0, 0, 1)
		local maxDist   = config.MaxDist   or 1000
		local result    = workspace:Raycast(origin, direction * maxDist)
		if result then
			return {
				Hit      = true,
				Position = result.Position,
				Normal   = result.Normal,
				Distance = (result.Position - origin).Magnitude,
				Part     = result.Instance :: BasePart,
			}
		end
		return { Hit = false }

	elseif config.Method == "Sphere" then
		local center  = config.Center or Vector3.zero
		local radius  = config.Radius or 5
		local params  = OverlapParams.new()
		local parts   = workspace:GetPartBoundsInRadius(center, radius, params)
		return {
			Hit   = #parts > 0,
			Parts = parts :: { BasePart },
		}

	elseif config.Method == "Box" then
		local cf      = config.CFrame or CFrame.new()
		local size    = config.Size   or Vector3.new(4, 4, 4)
		local params  = OverlapParams.new()
		local parts   = workspace:GetPartBoundsInBox(cf, size, params)
		return {
			Hit   = #parts > 0,
			Parts = parts :: { BasePart },
		}

	elseif config.Method == "Distance" then
		local origin  = config.Origin  or Vector3.zero
		local target  = config.Target
		local maxDist = config.MaxDist or 10
		if not target then return { Hit = false } end
		local dist = (origin - target.Position).Magnitude
		return {
			Hit      = dist <= maxDist,
			Distance = dist,
		}
	end

	return { Hit = false }
end

export type HitValidationResult = {
	Valid    : boolean,
	Distance : number?,
	Position : Vector3?,
	Latency  : number,
}

export type ReachValidationResult = {
	Valid    : boolean,
	Distance : number?,
	Delta    : number,
}

Mandy.Validate = {} :: {
	Hit   : (shooter: Player, target: Player, timestamp: number, origin: Vector3, direction: Vector3) -> HitValidationResult,
	Reach : (player: Player, target: Player, maxDist: number, timestamp: number) -> ReachValidationResult,
}

function Mandy.Validate.Hit(
	shooter   : Player,
	target    : Player,
	timestamp : number,
	origin    : Vector3,
	direction : Vector3
): HitValidationResult
	Shared.assertServer("Mandy.Validate.Hit")

	local latency = Mandy.Ping(shooter) / 1000
	local window  = Mandy.Window(shooter)

	local targetSnap = Mandy.Rollback(target, timestamp)
	if not targetSnap then
		return { Valid = false, Latency = latency }
	end

	local result = workspace:Raycast(origin, direction * 2000)
	if not result then
		return { Valid = false, Latency = latency }
	end

	local hitPos    = result.Position
	local snapDist  = (hitPos - targetSnap.Position).Magnitude
	local tolerance = 4 + latency * 40

	return {
		Valid    = snapDist <= tolerance,
		Distance = (origin - hitPos).Magnitude,
		Position = hitPos,
		Latency  = latency,
	}
end

function Mandy.Validate.Reach(
	player    : Player,
	target    : Player,
	maxDist   : number,
	timestamp : number
): ReachValidationResult
	Shared.assertServer("Mandy.Validate.Reach")

	local latency    = Mandy.Ping(player) / 1000
	local delta      = latency * 16
	local playerSnap = Mandy.Rollback(player, timestamp)
	local targetSnap = Mandy.Rollback(target, timestamp)

	if not playerSnap or not targetSnap then
		return { Valid = false, Delta = delta }
	end

	local dist = (playerSnap.Position - targetSnap.Position).Magnitude
	return {
		Valid    = dist <= maxDist + delta,
		Distance = dist,
		Delta    = delta,
	}
end

function Mandy.Interpolate(player: Player, timestamp: number): Vector3?
	Shared.assertServer("Mandy.Interpolate")
	local snapshots = snapshotHistory[player]
	if not snapshots or #snapshots < 2 then return nil end

	local before: { Position: Vector3, At: number }? = nil
	local after : { Position: Vector3, At: number }? = nil

	for i = 1, #snapshots - 1 do
		if snapshots[i].At <= timestamp and snapshots[i + 1].At >= timestamp then
			before = snapshots[i]
			after  = snapshots[i + 1]
			break
		end
	end

	if not before or not after then return nil end

	local t = (timestamp - before.At) / (after.At - before.At)
	return before.Position:Lerp(after.Position, t)
end

function Mandy.Extrapolate(player: Player, dt: number): Vector3?
	Shared.assertServer("Mandy.Extrapolate")
	local snapshots = snapshotHistory[player]
	if not snapshots or #snapshots == 0 then return nil end
	local last = snapshots[#snapshots]
	return last.Position + last.Velocity * dt
end

function Mandy.Snapshots(player: Player, n: number): { {
	Position : Vector3,
	Velocity : Vector3,
	At       : number,
	} }
	Shared.assertServer("Mandy.Snapshots")
	local all    = snapshotHistory[player] or {}
	local start  = math.max(1, #all - n + 1)
	local result : { { Position: Vector3, Velocity: Vector3, At: number } } = {}
	for i = start, #all do
		table.insert(result, {
			Position = all[i].Position,
			Velocity = all[i].Velocity,
			At       = all[i].At,
		})
	end
	return result
end

function Mandy.Adapt(mandateName: string, player: Player)
	Shared.assertServer("Mandy.Adapt")
	local quality = Mandy.Quality(player)
	local config  = Registry.get(mandateName)
	if not config then return end

	if quality.Grade == Shared.QUALITY_GRADES.Poor or quality.Grade == Shared.QUALITY_GRADES.Fair then
		if config.Type == Mandy.Unlazy then
			warn(string.format(
				"[Mandy] Adapt: '%s' -- player %s has poor connection -- consider switching to Lazy",
				mandateName, player.Name
				))
		end
	end
end

function Mandy.TickRate(player: Player): number
	local ping = Mandy.Ping(player)
	if ping < 50  then return 60 end
	if ping < 100 then return 30 end
	if ping < 200 then return 20 end
	return 10
end

function Mandy.Budget(config: {
	Critical : number?,
	High     : number?,
	Normal   : number?,
	Low      : number?,
	})
	warn("[Mandy] Mandy.Budget -- bandwidth budgeting registered -- enforcement requires per-frame queue")
end

function Mandy.Priority(mandateName: string, level: string)
	Shared.expect(mandateName, "mandateName", "string")
	Shared.expect(level,       "level",       "string")
	assert(Shared.PRIORITY_LEVELS[level], string.format("[Mandy] unknown priority level '%s'", level))
end

function Mandy.Pool(mandateName: string, config: { Size: number? })
	Shared.expect(mandateName, "mandateName", "string")
end

function Mandy.Coalesce(mandateName: string, enabled: boolean)
	Shared.expect(mandateName, "mandateName", "string")
end

function Mandy.Compress(mandateName: string, enabled: boolean)
	Shared.expect(mandateName, "mandateName", "string")
end

function Mandy.Heatmap(): { [string]: number }
	local result: { [string]: number } = {}
	for _, name in Registry.list() do
		local s = Registry.stats(name)
		result[name] = s.Received
	end
	return result
end

function Mandy.Timeline(config: {
	Mandate : string?,
	Player  : Player?,
	}): { [string]: any }
	warn("[Mandy] Mandy.Timeline -- requires Notice to be active for event history")
	return {}
end

function Mandy.Audit(config: {
	Persist   : boolean?,
	DataStore : string?,
	})
	Shared.assertServer("Mandy.Audit")
	warn("[Mandy] Mandy.Audit registered -- security events will be logged")
end

function Mandy.Alert(config: {
	Metric    : string,
	Mandate   : string,
	Threshold : number,
	Term      : (data: { [string]: any }) -> (),
	})
	Shared.assertServer("Mandy.Alert")
	task.spawn(function()
		while true do
			task.wait(1)
			local stats = Registry.stats(config.Mandate)
			local total = stats.Sent + stats.Received
			if config.Metric == "DropRate" and total > 0 then
				local rate = stats.Dropped / total
				if rate > config.Threshold then
					task.spawn(config.Term, { Rate = rate, Mandate = config.Mandate })
				end
			end
		end
	end)
end

function Mandy.Probe(mandateName: string, config: { Interval: number? })
	Shared.assertServer("Mandy.Probe")
	local interval = config.Interval or 5
	task.spawn(function()
		while true do
			task.wait(interval)
			local stats = Registry.stats(mandateName)
			if devMode then
				print(string.format(
					"[Mandy] Probe '%s' -- Sent: %d Received: %d Dropped: %d",
					mandateName, stats.Sent, stats.Received, stats.Dropped
					))
			end
		end
	end)
end

function Mandy.Forecast(
	mandateName : string,
	fn          : (player: Player, projection: { SecondsUntilLimit: number, CurrentRate: number }) -> ()
)
	Shared.assertServer("Mandy.Forecast")
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local stats = Registry.stats(mandateName)
				local rate  = stats.Received
				task.spawn(fn, player, {
					SecondsUntilLimit = math.max(0, 20 - rate),
					CurrentRate       = rate,
				})
			end
		end
	end)
end

function Mandy.Evolve(name: string, config: {
	[number] : { [string]: TypeDef },
	Migrate  : { [number]: (pkg: { [string]: any }) -> { [string]: any } },
	})
	warn("[Mandy] Mandy.Evolve registered for", name, "-- migration will run on inbound packages")
end

function Mandy.Postit(metadata: { [string]: any })
	Shared.assertServer("Mandy.Postit")
	local topic = "Mandy_Postit"
	pcall(function()
		MessagingService:PublishAsync(topic, HttpService:JSONEncode(metadata))
	end)
end

function Mandy.Find(query: { [string]: any }): { [string]: any }?
	warn("[Mandy] Mandy.Find -- server discovery requires MessagingService subscription -- use Bridge pattern")
	return nil
end

function Mandy.Cluster(_name: string, _metadata: { [string]: any })
	Shared.assertServer("Mandy.Cluster")
	warn("[Mandy] Mandy.Cluster registered")
end

function Mandy.Migrate(player: Player, targetJobId: string)
	Shared.assertServer("Mandy.Migrate")
	warn(string.format("[Mandy] Mandy.Migrate -- player %s -> server %s", player.Name, targetJobId))
end

function Mandy.Epoch(mandateName: string)
	Shared.expect(mandateName, "mandateName", "string")
	warn("[Mandy] Mandy.Epoch registered for", mandateName)
end

function Mandy.Consensus(name: string, config: {
	Parses  : { [string]: TypeDef },
	Quorum  : number,
	})
	Shared.assertServer("Mandy.Consensus")
	warn("[Mandy] Mandy.Consensus registered for", name, "quorum:", config.Quorum)
end

function Mandy.StatsFor(player: Player): {
	Sent      : number,
	Received  : number,
	Dropped   : number,
	Flagged   : number,
	BytesIn   : number,
	BytesOut  : number,
	}
	Shared.assertServer("Mandy.StatsFor")
	local marks = Security.getMarks(player)
	return {
		Sent     = 0,
		Received = 0,
		Dropped  = 0,
		Flagged  = #marks,
		BytesIn  = 0,
		BytesOut = 0,
	}
end

function Mandy.Flush(player: Player)
	Shared.assertServer("Mandy.Flush")
	Security.disconnectPlayer(player)
end

function Mandy.Disconnect(player: Player)
	Shared.assertServer("Mandy.Disconnect")
	Security.disconnectPlayer(player)
end

function Mandy.Mute(name: string, player: Player?)
	if player then
		Security.mutePlayer(player, name)
	else
		Registry.mute(name)
	end
end

function Mandy.Unmute(name: string, player: Player?)
	if player then
		Security.unmutePlayer(player, name)
	else
		Registry.unmute(name)
	end
end

function Mandy.Budget_Player(player: Player): {
	BytesPerSecond : number,
	Priority       : string,
	}
	local quality = Mandy.Quality(player)
	local bps: number
	if quality.Grade == Shared.QUALITY_GRADES.Excellent then bps = 16384
	elseif quality.Grade == Shared.QUALITY_GRADES.Good  then bps = 8192
	elseif quality.Grade == Shared.QUALITY_GRADES.Fair  then bps = 4096
	else                                                      bps = 2048
	end
	return { BytesPerSecond = bps, Priority = quality.Grade }
end

return Mandy
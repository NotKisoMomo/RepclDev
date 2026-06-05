local Shared   = require(script.Parent.Shared)
local Types    = require(script.Parent.Types)
local Truck    = require(script.Parent.Truck)
local Security = require(script.Parent.Security)
local Async    = require(script.Parent.Async)

local Registry = {}

type TypeDef     = Types.TypeDef
type Thread<T>   = Async.Thread<T>
type Promise<T>  = Async.Promise<T>
type Subscription = {
	Disconnect : () -> (),
	Data       : any?,
	Next       : (fn: (package: any, resolve: (value: any) -> ()) -> ()) -> Thread<any>,
	Toss       : (fn: (err: string, resolve: (value: any) -> ()) -> ()) -> Thread<any>,
	Conclude   : (fn: (original: any) -> ()) -> Thread<any>,
	Retry      : (n: number) -> Thread<any>,
	Collapse   : (reason: string?) -> (),
}

export type MandateModifier = {
	kind  : string,
	value : any?,
}

export type MandateConfig = {
	Type      : string,
	Parses    : { [string]: TypeDef } | typeof(Types.none),
	Modifiers : { MandateModifier }?,
	Security  : {
		RateLimit : {
			MaxPerSecond : number?,
			MaxPerMinute : number?,
		}?,
		Validate  : boolean?,
	}?,
	Conform   : boolean?,
	Timeout   : number?,
	Retries   : number?,
	Delta     : boolean?,
}

export type MandateHandle = {
	Subscribe   : (fn: (player: Player?, package: { [string]: any }, resolve: ((any) -> ())?, drop: ((string?) -> ())?) -> ()) -> Subscription,
	Post        : (playerOrData: Player | { [string]: any }, data: { [string]: any }?) -> Thread<any>?,
	PostAll     : (data: { [string]: any }) -> (),
	PostExclude : (player: Player, data: { [string]: any }) -> (),
	Validate    : (data: { [string]: any }) -> (boolean, string?),
	Destroy     : () -> (),
}

export type BinConfig = {
	Security : {
		RateLimit : {
			MaxPerSecond : number?,
			MaxPerMinute : number?,
		}?,
		Validate  : boolean?,
	}?,
	Mandates : { [string]: MandateConfig }?,
}

export type BinHandle = {
	Define        : (name: string, config: MandateConfig) -> (),
	CreateHandle  : (name: string) -> MandateHandle,
	Subscribe     : (name: string, fn: (...any) -> ()) -> Subscription,
	Post          : (name: string, playerOrData: Player | { [string]: any }, data: { [string]: any }?) -> Thread<any>?,
	PostAll       : (name: string, data: { [string]: any }) -> (),
	PostExclude   : (name: string, player: Player, data: { [string]: any }) -> (),
	Has           : (name: string) -> boolean,
	List          : () -> { string },
	Stats         : (name: string) -> { [string]: number },
	Pause         : (name: string) -> (),
	Resume        : (name: string) -> (),
	Mute          : (name: string) -> (),
	Unmute        : (name: string) -> (),
	Remove        : (name: string) -> (),
	Destroy       : () -> (),
}

type MandateEntry = {
	name        : string,
	config      : MandateConfig,
	subscribers : { (player: Player?, package: { [string]: any }, resolve: ((any) -> ())?, drop: ((string?) -> ())?) -> () },
	stats       : { Sent: number, Received: number, Dropped: number, Flagged: number, BytesIn: number, BytesOut: number },
	paused      : boolean,
	muted       : boolean,
	queue       : { Truck.PackageEnvelope }?,
	lastPackage : { [string]: any }?,
	buffer      : { { [string]: any } }?,
}

type RegistryState = {
	mandates    : { [string]: MandateEntry },
	aliases     : { [string]: string },
	whenGates   : { [string]: { condition: (Player, { [string]: any }) -> boolean, term: ((Player, { [string]: any }) -> ())? } },
	phases      : { [string]: { mandates: { string }, active: boolean } },
	prequeue    : { { mandateName: string, playerOrData: any, data: any? } },
	initialized : boolean,
}

local state: RegistryState = {
	mandates    = {},
	aliases     = {},
	whenGates   = {},
	phases      = {},
	prequeue    = {},
	initialized = false,
}

local IS_SERVER = Shared.IS_SERVER

local function resolveAlias(name: string): string
	return state.aliases[name] or name
end

local function getEntry(name: string): MandateEntry?
	return state.mandates[resolveAlias(name)]
end

local function hasModifier(config: MandateConfig, kind: string): boolean
	if not config.Modifiers then return false end
	for _, mod in config.Modifiers do
		if mod.kind == kind then return true end
	end
	return false
end

local function getModifierValue(config: MandateConfig, kind: string): any
	if not config.Modifiers then return nil end
	for _, mod in config.Modifiers do
		if mod.kind == kind then return mod.value end
	end
	return nil
end

local function shouldCoalesceOrBuffer(entry: MandateEntry, pkg: { [string]: any }): boolean
	if hasModifier(entry.config, Shared.MODIFIER_KEYS.Distinct) then
		if entry.lastPackage and Shared.shallowEqual(entry.lastPackage, pkg) then
			return false
		end
	end
	return true
end

local function createSubscription(
	entry     : MandateEntry,
	fn        : (player: Player?, package: { [string]: any }, resolve: ((any) -> ())?, drop: ((string?) -> ())?) -> ()
): Subscription
	local idx     = #entry.subscribers + 1
	entry.subscribers[idx] = fn

	local promise  = Async.createPromise()
	local thread   = Async.createThread(promise)
	local removed  = false

	local sub: Subscription = {
		Disconnect = function()
			if removed then return end
			removed = true
			for i, s in entry.subscribers do
				if s == fn then
					table.remove(entry.subscribers, i)
					break
				end
			end
		end,
		Data = nil,
	} :: any

	sub.Next     = function(_, nextFn) return thread:Next(nextFn) end
	sub.Toss     = function(_, tossFn) return thread:Toss(tossFn) end
	sub.Conclude = function(_, concFn) return thread:Conclude(concFn) end
	sub.Retry    = function(_, n)      return thread:Retry(n) end
	sub.Collapse = function(_, reason) thread:Collapse(reason) end

	if hasModifier(entry.config, Shared.MODIFIER_KEYS.Linger) and entry.lastPackage then
		task.spawn(fn, nil, entry.lastPackage, nil, nil)
		sub.Data = entry.lastPackage
		promise.Resolve(entry.lastPackage)
	end

	return sub
end

local function dispatchToSubscribers(
	entry   : MandateEntry,
	player  : Player?,
	pkg     : { [string]: any }
)
	if entry.muted then return end
	if entry.paused then
		if not entry.queue then entry.queue = {} end
		table.insert(entry.queue :: { Truck.PackageEnvelope }, {
			mandateName = entry.name,
			payload     = pkg,
			sequence    = 0,
			nonce       = "",
			timestamp   = os.time(),
		})
		return
	end

	if not shouldCoalesceOrBuffer(entry, pkg) then return end

	local bufferSize = getModifierValue(entry.config, Shared.MODIFIER_KEYS.Buffer)
	if bufferSize then
		if not entry.buffer then entry.buffer = {} end
		table.insert(entry.buffer :: { { [string]: any } }, pkg)
		if #(entry.buffer :: { { [string]: any } }) >= bufferSize then
			local batch = entry.buffer :: { { [string]: any } }
			entry.buffer = {}
			for _, sub in entry.subscribers do
				task.spawn(sub, player, batch, nil, nil)
			end
			entry.lastPackage = pkg
		end
		return
	end

	entry.lastPackage = pkg
	entry.stats.Received += 1

	for _, sub in entry.subscribers do
		task.spawn(sub, player, pkg, nil, nil)
	end
end

local function dispatchResolver(
	entry   : MandateEntry,
	player  : Player?,
	pkg     : { [string]: any }
): { [string]: any }
	if entry.muted then return {} end

	entry.lastPackage = pkg
	entry.stats.Received += 1

	local result: { [string]: any } = {}
	local resolved = false

	local resolveCallback = function(value: { [string]: any })
		if resolved then return end
		resolved = true
		result   = value
	end

	local dropCallback = function(reason: string?)
		if resolved then return end
		resolved = true
	end

	for _, sub in entry.subscribers do
		sub(player, pkg, resolveCallback, dropCallback)
		if resolved then break end
	end

	return result
end

local function registerWithTruck(name: string, entry: MandateEntry)
	if entry.config.Type == Shared.MANDATE_TYPES.Resolver then
		Truck.registerResolver(name, function(player: Player?, payload: { [string]: any })
			if IS_SERVER and player then
				local allowed = true
				Security.verify(
					player,
					{
						mandateName = name,
						payload     = payload,
						sequence    = 0,
						nonce       = Shared.generateId(),
						timestamp   = os.time(),
					},
					function() allowed = true end,
					function(_) allowed = false entry.stats.Dropped += 1 end
				)
				if not allowed then return {} end
			end
			if entry.config.Security and entry.config.Security.Validate then
				if entry.config.Parses ~= Types.none then
					for fieldName, fieldDef in entry.config.Parses :: { [string]: TypeDef } do
						local ok, err = Types.validate(fieldDef, payload[fieldName])
						if not ok then
							entry.stats.Flagged += 1
							return {}
						end
					end
				end
			end
			return dispatchResolver(entry, player, payload)
		end)
	else
		Truck.registerDispatch(name, function(player: Player?, envelope: Truck.PackageEnvelope)
			if IS_SERVER and player then
				local allowed = true
				Security.verify(
					player :: Player,
					envelope,
					function() allowed = true end,
					function(_) allowed = false entry.stats.Dropped += 1 end
				)
				if not allowed then return end
			end

			local pkg = envelope.payload

			if entry.config.Security and entry.config.Security.Validate then
				if entry.config.Parses ~= Types.none then
					for fieldName, fieldDef in entry.config.Parses :: { [string]: TypeDef } do
						local ok, _ = Types.validate(fieldDef, pkg[fieldName])
						if not ok then
							entry.stats.Flagged += 1
							return
						end
					end
				end
			end

			if entry.config.Conform and entry.config.Parses ~= Types.none then
				pkg = Types.applyDefaults(
					Types.struct(entry.config.Parses :: { [string]: TypeDef }),
					pkg
				)
			end

			local whenGate = state.whenGates[name]
			if whenGate and player then
				if not whenGate.condition(player, pkg) then
					if whenGate.term then
						task.spawn(whenGate.term :: (Player, { [string]: any }) -> (), player, pkg)
					end
					return
				end
			end

			dispatchToSubscribers(entry, player, pkg)
		end)
	end
end

local function makeEntry(name: string, config: MandateConfig): MandateEntry
	return {
		name        = name,
		config      = config,
		subscribers = {},
		stats       = { Sent = 0, Received = 0, Dropped = 0, Flagged = 0, BytesIn = 0, BytesOut = 0 },
		paused      = false,
		muted       = false,
		queue       = nil,
		lastPackage = nil,
		buffer      = nil,
	}
end

function Registry.define(name: string, config: MandateConfig)
	Shared.expect(name, "name", "string")
	Shared.expectNotNil(config, "config")
	Shared.expectNotNil(config.Type, "config.Type")

	assert(not Security.isSealed(name), string.format("[Mandy] mandate '%s' is sealed", name))

	if state.mandates[name] then
		warn(string.format("[Mandy] mandate '%s' already defined -- skipping", name))
		return
	end

	local entry = makeEntry(name, config)
	state.mandates[name] = entry

	if config.Security and config.Security.RateLimit then
		Security.setRateLimit(name, config.Security.RateLimit :: any)
	end

	registerWithTruck(name, entry)
end

function Registry.createHandle(name: string): MandateHandle
	Shared.expect(name, "name", "string")

	local resolved = resolveAlias(name)
	assert(state.mandates[resolved], string.format("[Mandy] no mandate named '%s'", name))

	return Registry.mandate(name, state.mandates[resolved].config)
end

function Registry.mandate(name: string, config: MandateConfig): MandateHandle
	Registry.define(name, config)

	local entry = state.mandates[resolveAlias(name)] :: MandateEntry

	local handle: MandateHandle = {} :: any

	function handle.Subscribe(fn)
		Shared.expect(fn, "fn", "function")
		return createSubscription(entry, fn)
	end

	function handle.Post(playerOrData: Player | { [string]: any }, data: { [string]: any }?)
		local payload: { [string]: any }
		local target: Player?

		if IS_SERVER then
			assert(typeof(playerOrData) == "Instance", "[Mandy] server Post requires a Player as first argument")
			target  = playerOrData :: Player
			payload = data or {}
		else
			payload = playerOrData :: { [string]: any }
			target  = nil
		end

		entry.stats.Sent += 1

		if config.Type == Shared.MANDATE_TYPES.Resolver then
			local promise = Async.createPromise()
			local thread  = Async.createThread(promise)

			if IS_SERVER then
				warn("[Mandy] server cannot invoke Resolver -- use Subscribe instead")
				promise.Reject("server cannot invoke resolver")
				return thread
			end

			task.spawn(function()
				local result = Truck.send({
					mandateType = config.Type,
					mandateName = name,
					payload     = payload,
					target      = target,
					signature   = Security.getSignature(),
				})
				if result then
					promise.Resolve(result)
				else
					promise.Reject("resolver returned nil")
				end
			end)

			return thread
		else
			Truck.send({
				mandateType = config.Type,
				mandateName = name,
				payload     = payload,
				target      = target,
				signature   = Security.getSignature(),
			})
			return nil
		end
	end

	function handle.PostAll(data: { [string]: any })
		Shared.assertServer("PostAll")
		entry.stats.Sent += 1
		Truck.sendAll({
			mandateType = config.Type,
			mandateName = name,
			payload     = data,
			signature   = Security.getSignature(),
		})
	end

	function handle.PostExclude(player: Player, data: { [string]: any })
		Shared.assertServer("PostExclude")
		entry.stats.Sent += 1
		Truck.sendAll({
			mandateType = config.Type,
			mandateName = name,
			payload     = data,
			exclude     = player,
			signature   = Security.getSignature(),
		})
	end

	function handle.Validate(data: { [string]: any }): (boolean, string?)
		if config.Parses == Types.none then return true, nil end
		local parses = config.Parses :: { [string]: TypeDef }
		local errors: { string } = {}
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

	function handle.Destroy()
		Truck.unregisterDispatch(name)
		state.mandates[resolveAlias(name)] = nil
	end

	return handle
end

function Registry.subscribe(
	name : string,
	fn   : (player: Player?, package: { [string]: any }, resolve: ((any) -> ())?, drop: ((string?) -> ())?) -> ()
): Subscription
	Shared.expect(name, "name", "string")
	Shared.expect(fn, "fn", "function")

	local entry = getEntry(name)
	assert(entry, string.format("[Mandy] no mandate named '%s'", name))

	return createSubscription(entry :: MandateEntry, fn)
end

function Registry.once(
	name : string,
	fn   : (player: Player?, package: { [string]: any }, resolve: ((any) -> ())?, drop: ((string?) -> ())?) -> ()
): Subscription
	Shared.expect(name, "name", "string")
	local sub: Subscription
	sub = Registry.subscribe(name, function(player, pkg, resolve, drop)
		sub.Disconnect()
		fn(player, pkg, resolve, drop)
	end)
	return sub
end

function Registry.await(name: string): { [string]: any }
	Shared.expect(name, "name", "string")
	local co      = coroutine.running()
	local result: { [string]: any }
	local sub: Subscription
	sub = Registry.once(name, function(_, pkg, _, _)
		result = pkg
		task.spawn(co)
	end)
	coroutine.yield()
	return result
end

function Registry.awaitSafe(name: string): (boolean, { [string]: any }?, string?)
	local ok, result = pcall(function()
		return Registry.await(name)
	end)
	if ok then
		return true, result :: { [string]: any }, nil
	else
		return false, nil, tostring(result)
	end
end

function Registry.post(
	name        : string,
	playerOrData: Player | { [string]: any },
	data        : { [string]: any }?
): Thread<any>?
	Shared.expect(name, "name", "string")
	local entry = getEntry(name)
	assert(entry, string.format("[Mandy] no mandate named '%s'", name))

	local handle = Registry.createHandle(name)
	return handle.Post(playerOrData, data)
end

function Registry.postAll(name: string, data: { [string]: any })
	Shared.expect(name, "name", "string")
	local entry = getEntry(name)
	assert(entry, string.format("[Mandy] no mandate named '%s'", name))
	local handle = Registry.createHandle(name)
	handle.PostAll(data)
end

function Registry.postExclude(name: string, player: Player, data: { [string]: any })
	Shared.expect(name, "name", "string")
	local entry = getEntry(name)
	assert(entry, string.format("[Mandy] no mandate named '%s'", name))
	local handle = Registry.createHandle(name)
	handle.PostExclude(player, data)
end

function Registry.validate(name: string, data: { [string]: any }): (boolean, string?)
	Shared.expect(name, "name", "string")
	local entry = getEntry(name)
	assert(entry, string.format("[Mandy] no mandate named '%s'", name))
	local handle = Registry.createHandle(name)
	return handle.Validate(data)
end

function Registry.has(name: string): boolean
	return state.mandates[resolveAlias(name)] ~= nil
end

function Registry.get(name: string): MandateConfig?
	local entry = getEntry(name)
	return entry and entry.config or nil
end

function Registry.list(): { string }
	local names: { string } = {}
	for name in state.mandates do
		table.insert(names, name)
	end
	return names
end

function Registry.stats(name: string): { [string]: number }
	local entry = getEntry(name)
	if not entry then return {} end
	return {
		Sent     = entry.stats.Sent,
		Received = entry.stats.Received,
		Dropped  = entry.stats.Dropped,
		Flagged  = entry.stats.Flagged,
		BytesIn  = entry.stats.BytesIn,
		BytesOut = entry.stats.BytesOut,
	}
end

function Registry.globalStats(): { [string]: number }
	local totals = { Sent = 0, Received = 0, Dropped = 0, Flagged = 0, BytesIn = 0, BytesOut = 0 }
	for _, entry in state.mandates do
		totals.Sent     += entry.stats.Sent
		totals.Received += entry.stats.Received
		totals.Dropped  += entry.stats.Dropped
		totals.Flagged  += entry.stats.Flagged
		totals.BytesIn  += entry.stats.BytesIn
		totals.BytesOut += entry.stats.BytesOut
	end
	return totals
end

function Registry.resetStats(name: string)
	local entry = getEntry(name)
	if not entry then return end
	entry.stats = { Sent = 0, Received = 0, Dropped = 0, Flagged = 0, BytesIn = 0, BytesOut = 0 }
end

function Registry.resetAllStats()
	for _, entry in state.mandates do
		entry.stats = { Sent = 0, Received = 0, Dropped = 0, Flagged = 0, BytesIn = 0, BytesOut = 0 }
	end
end

function Registry.pause(name: string)
	local entry = getEntry(name)
	if not entry then return end
	entry.paused = true
	entry.queue  = entry.queue or {}
end

function Registry.resume(name: string)
	local entry = getEntry(name)
	if not entry then return end
	entry.paused = false
	local queue  = entry.queue
	entry.queue  = nil
	if queue then
		for _, envelope in queue do
			dispatchToSubscribers(entry, nil, envelope.payload)
		end
	end
end

function Registry.mute(name: string)
	local entry = getEntry(name)
	if not entry then return end
	entry.muted = true
end

function Registry.unmute(name: string)
	local entry = getEntry(name)
	if not entry then return end
	entry.muted = false
end

function Registry.remove(name: string)
	local resolved = resolveAlias(name)
	Truck.unregisterDispatch(resolved)
	state.mandates[resolved] = nil
end

function Registry.alias(name: string, aliasName: string)
	Shared.expect(name,      "name",      "string")
	Shared.expect(aliasName, "aliasName", "string")
	assert(state.mandates[name], string.format("[Mandy] no mandate named '%s'", name))
	state.aliases[aliasName] = name
end

function Registry.when(
	name      : string,
	condition : (player: Player, package: { [string]: any }) -> boolean,
	term      : ((player: Player, package: { [string]: any }) -> ())?
)
	Shared.assertServer("Registry.when")
	Shared.expect(name,      "name",      "string")
	Shared.expect(condition, "condition", "function")
	state.whenGates[name] = { condition = condition, term = term }
end

function Registry.load(mandates: { { Name: string, Config: MandateConfig } })
	for _, entry in mandates do
		Shared.expect(entry.Name,   "entry.Name",   "string")
		Shared.expectNotNil(entry.Config, "entry.Config")
		Registry.define(entry.Name, entry.Config)
	end
end

function Registry.bin(binName: string, config: BinConfig?): BinHandle
	Shared.expect(binName, "binName", "string")

	local cfg          = config or {}
	local mandateNames : { string } = {}

	local function prefixed(name: string): string
		return binName .. "." .. name
	end

	local bin: BinHandle = {} :: any

	function bin.Define(name: string, mandateConfig: MandateConfig)
		Shared.expect(name, "name", "string")
		local full = prefixed(name)
		if cfg.Security and cfg.Security.RateLimit and not mandateConfig.Security then
			mandateConfig.Security = cfg.Security :: any
		end
		Registry.define(full, mandateConfig)
		table.insert(mandateNames, full)
	end

	function bin.CreateHandle(name: string): MandateHandle
		return Registry.createHandle(prefixed(name))
	end

	function bin.Subscribe(name: string, fn: (...any) -> ()): Subscription
		return Registry.subscribe(prefixed(name), fn :: any)
	end

	function bin.Post(name: string, playerOrData: any, data: { [string]: any }?): Thread<any>?
		return Registry.post(prefixed(name), playerOrData, data)
	end

	function bin.PostAll(name: string, data: { [string]: any })
		Registry.postAll(prefixed(name), data)
	end

	function bin.PostExclude(name: string, player: Player, data: { [string]: any })
		Registry.postExclude(prefixed(name), player, data)
	end

	function bin.Has(name: string): boolean
		return Registry.has(prefixed(name))
	end

	function bin.List(): { string }
		local result: { string } = {}
		for _, full in mandateNames do
			table.insert(result, full:sub(#binName + 2))
		end
		return result
	end

	function bin.Stats(name: string): { [string]: number }
		return Registry.stats(prefixed(name))
	end

	function bin.Pause(name: string)
		Registry.pause(prefixed(name))
	end

	function bin.Resume(name: string)
		Registry.resume(prefixed(name))
	end

	function bin.Mute(name: string)
		Registry.mute(prefixed(name))
	end

	function bin.Unmute(name: string)
		Registry.unmute(prefixed(name))
	end

	function bin.Remove(name: string)
		local full = prefixed(name)
		Registry.remove(full)
		for i, n in mandateNames do
			if n == full then table.remove(mandateNames, i) break end
		end
	end

	function bin.Destroy()
		for _, full in mandateNames do
			Registry.remove(full)
		end
		mandateNames = {}
	end

	if cfg.Mandates then
		for name, mandateConfig in cfg.Mandates do
			bin.Define(name, mandateConfig)
		end
	end

	return bin
end

function Registry.listBin(binName: string): { string }
	local prefix  = binName .. "."
	local result  : { string } = {}
	for name in state.mandates do
		if name:sub(1, #prefix) == prefix then
			table.insert(result, name:sub(#prefix + 1))
		end
	end
	return result
end

function Registry.destroy()
	for name in state.mandates do
		Truck.unregisterDispatch(name)
	end
	state.mandates  = {}
	state.aliases   = {}
	state.whenGates = {}
	state.phases    = {}
	state.prequeue  = {}
end

function Registry.phase(phaseName: string, mandates: { string })
	Shared.assertServer("Registry.phase")
	state.phases[phaseName] = { mandates = mandates, active = false }
end

function Registry.enterPhase(phaseName: string)
	Shared.assertServer("Registry.enterPhase")
	local phase = state.phases[phaseName]
	assert(phase, string.format("[Mandy] no phase named '%s'", phaseName))
	phase.active = true
	for _, name in phase.mandates do
		Registry.unmute(name)
	end
end

function Registry.exitPhase(phaseName: string)
	Shared.assertServer("Registry.exitPhase")
	local phase = state.phases[phaseName]
	assert(phase, string.format("[Mandy] no phase named '%s'", phaseName))
	phase.active = false
	for _, name in phase.mandates do
		Registry.mute(name)
	end
end

return Registry
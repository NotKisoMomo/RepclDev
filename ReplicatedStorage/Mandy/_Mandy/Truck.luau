local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")
local Shared     = require(script.Parent.Shared)

local Truck = {}

export type PackageEnvelope = {
	mandateName : string,
	payload     : { [string]: any },
	traceId     : string?,
	sequence    : number,
	nonce       : string,
	timestamp   : number,
	signature   : string?,
}

export type InfraEnvelope = {
	tag     : string,
	payload : { [string]: any },
}

export type DispatchHandler = (
	player    : Player?,
	envelope  : PackageEnvelope
) -> ()

export type InfraHandler = (
	player  : Player?,
	payload : { [string]: any }
) -> ()

export type DiagnosticHandler = (
	player  : Player?,
	payload : { [string]: any }
) -> ()

type RemoteSet = {
	Lazy               : UnreliableRemoteEvent,
	Unlazy             : RemoteEvent,
	Resolver           : RemoteFunction,
	LazyDiagnostic     : UnreliableRemoteEvent,
	UnlazyDiagnostic   : RemoteEvent,
	ResolverDiagnostic : RemoteFunction,
	Bootstrap          : RemoteEvent,
	Infra              : RemoteEvent,
}

type TruckState = {
	remotes             : RemoteSet?,
	dispatchHandlers    : { [string]: DispatchHandler },
	infraHandlers       : { [string]: InfraHandler },
	diagnosticHandlers  : { [string]: DiagnosticHandler },
	resolverHandlers    : { [string]: (player: Player?, payload: { [string]: any }) -> { [string]: any } },
	sequenceCounter     : number,
	bootstrapHandler    : ((player: Player, signature: string) -> ())?,
	bootstrapAckHandler : ((signature: string) -> ())?,
}

local state: TruckState = {
	remotes             = nil,
	dispatchHandlers    = {},
	infraHandlers       = {},
	diagnosticHandlers  = {},
	resolverHandlers    = {},
	sequenceCounter     = 0,
	bootstrapHandler    = nil,
	bootstrapAckHandler = nil,
}

local IS_SERVER = Shared.IS_SERVER

local function getOrCreateRemote<T>(parent: Instance, className: string, name: string): T
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing :: any
	end
	local remote    = Instance.new(className)
	remote.Name     = name
	remote.Parent   = parent
	return remote :: any
end

local function encodeEnvelope(envelope: PackageEnvelope): string
	return game:GetService("HttpService"):JSONEncode(envelope)
end

local function decodeEnvelope(raw: string): PackageEnvelope?
	local ok, result = pcall(function()
		return game:GetService("HttpService"):JSONDecode(raw)
	end)
	if ok then
		return result :: PackageEnvelope
	end
	return nil
end

local function encodeInfra(infra: InfraEnvelope): string
	return game:GetService("HttpService"):JSONEncode(infra)
end

local function decodeInfra(raw: string): InfraEnvelope?
	local ok, result = pcall(function()
		return game:GetService("HttpService"):JSONDecode(raw)
	end)
	if ok then
		return result :: InfraEnvelope
	end
	return nil
end

local function nextSequence(): number
	state.sequenceCounter += 1
	return state.sequenceCounter
end

local function getRemoteType(mandateType: string): "Lazy" | "Unlazy" | "Resolver"
	if mandateType == Shared.MANDATE_TYPES.Lazy then
		return "Lazy"
	elseif mandateType == Shared.MANDATE_TYPES.Resolver then
		return "Resolver"
	end
	return "Unlazy"
end

function Truck.init(container: Instance)
	assert(not state.remotes, "[Mandy] Truck.init called more than once")

	local remotes: RemoteSet = {
		Lazy               = getOrCreateRemote(container, "UnreliableRemoteEvent", Shared.REMOTE_NAMES.Lazy),
		Unlazy             = getOrCreateRemote(container, "RemoteEvent",           Shared.REMOTE_NAMES.Unlazy),
		Resolver           = getOrCreateRemote(container, "RemoteFunction",        Shared.REMOTE_NAMES.Resolver),
		LazyDiagnostic     = getOrCreateRemote(container, "UnreliableRemoteEvent", Shared.REMOTE_NAMES.LazyDiagnostic),
		UnlazyDiagnostic   = getOrCreateRemote(container, "RemoteEvent",           Shared.REMOTE_NAMES.UnlazyDiagnostic),
		ResolverDiagnostic = getOrCreateRemote(container, "RemoteFunction",        Shared.REMOTE_NAMES.ResolverDiagnostic),
		Bootstrap          = getOrCreateRemote(container, "RemoteEvent",           Shared.REMOTE_NAMES.Bootstrap),
		Infra              = getOrCreateRemote(container, "RemoteEvent",           Shared.REMOTE_NAMES.Infra),
	}

	state.remotes = remotes

	if IS_SERVER then
		remotes.Lazy.OnServerEvent:Connect(function(player: Player, raw: string)
			local envelope = decodeEnvelope(raw)
			if not envelope then return end
			local handler = state.dispatchHandlers[envelope.mandateName]
			if handler then
				task.spawn(handler, player, envelope)
			end
		end)

		remotes.Unlazy.OnServerEvent:Connect(function(player: Player, raw: string)
			local envelope = decodeEnvelope(raw)
			if not envelope then return end
			local handler = state.dispatchHandlers[envelope.mandateName]
			if handler then
				task.spawn(handler, player, envelope)
			end
		end)

		remotes.Resolver.OnServerInvoke = function(player: Player, raw: string): string
			local envelope = decodeEnvelope(raw)
			if not envelope then return "{}" end
			local handler = state.resolverHandlers[envelope.mandateName]
			if handler then
				local result = handler(player, envelope.payload)
				return game:GetService("HttpService"):JSONEncode(result or {})
			end
			return "{}"
		end

		remotes.Infra.OnServerEvent:Connect(function(player: Player, raw: string)
			local infra = decodeInfra(raw)
			if not infra then return end
			local handler = state.infraHandlers[infra.tag]
			if handler then
				task.spawn(handler, player, infra.payload)
			end
		end)

		remotes.Bootstrap.OnServerEvent:Connect(function(player: Player, signature: string)
			if state.bootstrapHandler then
				state.bootstrapHandler(player, signature)
			end
		end)

		remotes.LazyDiagnostic.OnServerEvent:Connect(function(player: Player, raw: string)
			local payload = game:GetService("HttpService"):JSONDecode(raw)
			local handler = state.diagnosticHandlers[payload.tag]
			if handler then
				task.spawn(handler, player, payload)
			end
		end)

		remotes.UnlazyDiagnostic.OnServerEvent:Connect(function(player: Player, raw: string)
			local payload = game:GetService("HttpService"):JSONDecode(raw)
			local handler = state.diagnosticHandlers[payload.tag]
			if handler then
				task.spawn(handler, player, payload)
			end
		end)

		remotes.ResolverDiagnostic.OnServerInvoke = function(player: Player, raw: string): string
			local payload = game:GetService("HttpService"):JSONDecode(raw)
			local handler = state.diagnosticHandlers[payload.tag]
			if handler then
				local result = (handler :: any)(player, payload)
				return game:GetService("HttpService"):JSONEncode(result or {})
			end
			return "{}"
		end
	else
		remotes.Lazy.OnClientEvent:Connect(function(raw: string)
			local envelope = decodeEnvelope(raw)
			if not envelope then return end
			local handler = state.dispatchHandlers[envelope.mandateName]
			if handler then
				task.spawn(handler, nil, envelope)
			end
		end)

		remotes.Unlazy.OnClientEvent:Connect(function(raw: string)
			local envelope = decodeEnvelope(raw)
			if not envelope then return end
			local handler = state.dispatchHandlers[envelope.mandateName]
			if handler then
				task.spawn(handler, nil, envelope)
			end
		end)

		remotes.Infra.OnClientEvent:Connect(function(raw: string)
			local infra = decodeInfra(raw)
			if not infra then return end
			local handler = state.infraHandlers[infra.tag]
			if handler then
				task.spawn(handler, nil, infra.payload)
			end
		end)

		remotes.Bootstrap.OnClientEvent:Connect(function(signature: string)
			if state.bootstrapAckHandler then
				state.bootstrapAckHandler(signature)
			end
		end)

		remotes.LazyDiagnostic.OnClientEvent:Connect(function(raw: string)
			local payload = game:GetService("HttpService"):JSONDecode(raw)
			local handler = state.diagnosticHandlers[payload.tag]
			if handler then
				task.spawn(handler, nil, payload)
			end
		end)

		remotes.UnlazyDiagnostic.OnClientEvent:Connect(function(raw: string)
			local payload = game:GetService("HttpService"):JSONDecode(raw)
			local handler = state.diagnosticHandlers[payload.tag]
			if handler then
				task.spawn(handler, nil, payload)
			end
		end)
	end
end

function Truck.registerDispatch(mandateName: string, handler: DispatchHandler)
	Shared.expect(mandateName, "mandateName", "string")
	Shared.expect(handler, "handler", "function")
	state.dispatchHandlers[mandateName] = handler
end

function Truck.registerResolver(
	mandateName : string,
	handler     : (player: Player?, payload: { [string]: any }) -> { [string]: any }
)
	Shared.expect(mandateName, "mandateName", "string")
	Shared.expect(handler, "handler", "function")
	state.resolverHandlers[mandateName] = handler
end

function Truck.registerInfra(tag: string, handler: InfraHandler)
	Shared.expect(tag, "tag", "string")
	Shared.expect(handler, "handler", "function")
	state.infraHandlers[tag] = handler
end

function Truck.registerDiagnostic(tag: string, handler: DiagnosticHandler)
	Shared.expect(tag, "tag", "string")
	Shared.expect(handler, "handler", "function")
	state.diagnosticHandlers[tag] = handler
end

function Truck.onBootstrap(handler: (player: Player, signature: string) -> ())
	state.bootstrapHandler = handler
end

function Truck.onBootstrapAck(handler: (signature: string) -> ())
	state.bootstrapAckHandler = handler
end

export type SendOptions = {
	mandateType : string,
	mandateName : string,
	payload     : { [string]: any },
	target      : Player?,
	signature   : string?,
	traceId     : string?,
}

function Truck.send(opts: SendOptions)
	assert(state.remotes, "[Mandy] Truck not initialized -- call Truck.init first")
	local remotes = state.remotes :: RemoteSet

	local envelope: PackageEnvelope = {
		mandateName = opts.mandateName,
		payload     = opts.payload,
		traceId     = opts.traceId,
		sequence    = nextSequence(),
		nonce       = Shared.generateId(),
		timestamp   = os.time(),
		signature   = opts.signature,
	}

	local raw       = encodeEnvelope(envelope)
	local remoteKey = getRemoteType(opts.mandateType)

	if IS_SERVER then
		if remoteKey == "Lazy" then
			if opts.target then
				remotes.Lazy:FireClient(opts.target, raw)
			end
		elseif remoteKey == "Unlazy" then
			if opts.target then
				remotes.Unlazy:FireClient(opts.target, raw)
			end
		end
	else
		if remoteKey == "Lazy" then
			remotes.Lazy:FireServer(raw)
		elseif remoteKey == "Unlazy" then
			remotes.Unlazy:FireServer(raw)
		elseif remoteKey == "Resolver" then
			local resultRaw = remotes.Resolver:InvokeServer(raw)
			return game:GetService("HttpService"):JSONDecode(resultRaw)
		end
	end

	return nil
end

export type SendAllOptions = {
	mandateType : string,
	mandateName : string,
	payload     : { [string]: any },
	exclude     : Player?,
	signature   : string?,
	traceId     : string?,
}

function Truck.sendAll(opts: SendAllOptions)
	assert(IS_SERVER,         "[Mandy] Truck.sendAll is server-only")
	assert(state.remotes,     "[Mandy] Truck not initialized")
	local remotes = state.remotes :: RemoteSet

	local envelope: PackageEnvelope = {
		mandateName = opts.mandateName,
		payload     = opts.payload,
		traceId     = opts.traceId,
		sequence    = nextSequence(),
		nonce       = Shared.generateId(),
		timestamp   = os.time(),
		signature   = opts.signature,
	}

	local raw       = encodeEnvelope(envelope)
	local remoteKey = getRemoteType(opts.mandateType)

	if remoteKey == "Lazy" then
		for _, player in Players:GetPlayers() do
			if player ~= opts.exclude then
				remotes.Lazy:FireClient(player, raw)
			end
		end
	elseif remoteKey == "Unlazy" then
		if opts.exclude then
			for _, player in Players:GetPlayers() do
				if player ~= opts.exclude then
					remotes.Unlazy:FireClient(player, raw)
				end
			end
		else
			remotes.Unlazy:FireAllClients(raw)
		end
	end
end

export type SendInfraOptions = {
	tag     : string,
	payload : { [string]: any },
	target  : Player?,
}

function Truck.sendInfra(opts: SendInfraOptions)
	assert(state.remotes, "[Mandy] Truck not initialized")
	local remotes = state.remotes :: RemoteSet

	local infra: InfraEnvelope = {
		tag     = opts.tag,
		payload = opts.payload,
	}
	local raw = encodeInfra(infra)

	if IS_SERVER then
		if opts.target then
			remotes.Infra:FireClient(opts.target, raw)
		else
			remotes.Infra:FireAllClients(raw)
		end
	else
		remotes.Infra:FireServer(raw)
	end
end

function Truck.sendBootstrap(player: Player, signature: string)
	assert(IS_SERVER,     "[Mandy] Truck.sendBootstrap is server-only")
	assert(state.remotes, "[Mandy] Truck not initialized")
	local remotes = state.remotes :: RemoteSet
	remotes.Bootstrap:FireClient(player, signature)
end

function Truck.sendDiagnostic(opts: {
	tag         : string,
	payload     : { [string]: any },
	mandateType : string,
	target      : Player?,
	})
	assert(state.remotes, "[Mandy] Truck not initialized")
	local remotes   = state.remotes :: RemoteSet
	local diagnostic = table.clone(opts.payload)
	diagnostic.tag = opts.tag
	local raw = game:GetService("HttpService"):JSONEncode(diagnostic :: any)
	local remoteKey = getRemoteType(opts.mandateType)

	if IS_SERVER then
		if opts.target then
			if remoteKey == "Lazy" then
				remotes.LazyDiagnostic:FireClient(opts.target, raw)
			else
				remotes.UnlazyDiagnostic:FireClient(opts.target, raw)
			end
		end
	else
		if remoteKey == "Lazy" then
			remotes.LazyDiagnostic:FireServer(raw)
		elseif remoteKey == "Unlazy" then
			remotes.UnlazyDiagnostic:FireServer(raw)
		elseif remoteKey == "Resolver" then
			remotes.ResolverDiagnostic:InvokeServer(raw)
		end
	end
end

function Truck.unregisterDispatch(mandateName: string)
	state.dispatchHandlers[mandateName]  = nil
	state.resolverHandlers[mandateName]  = nil
end

return Truck
--!strict

local Shared = require(script.Parent.Shared)
local Truck  = require(script.Parent.Truck)

local Security = {}

export type SecureConfig = {
	RateLimit : {
		MaxPerSecond : number?,
		MaxPerMinute : number?,
	}?,
	Nonce     : boolean?,
	Sequence  : boolean?,
	OnFlag    : ((player: Player, reason: string) -> ())?,
}

export type Mark = {
	Reason : string,
	At     : number,
}

export type RateLimitConfig = {
	MaxPerSecond : number?,
	MaxPerMinute : number?,
}

export type CrossPacket = {
	Name      : string,
	Package   : { [string]: any },
	Player    : Player?,
	Direction : "Inbound" | "Outbound",
	At        : number,
	Drop      : () -> (),
}

export type CrossHandler = (packet: CrossPacket, next: () -> ()) -> ()

export type SessionData = {
	Signature  : string,
	IssuedAt   : number,
	LastSeq    : number,
	SeenNonces : { [string]: boolean },
}

type SecurityState = {
	config           : SecureConfig?,
	active           : boolean,
	sessions         : { [Player]: SessionData },
	marks            : { [Player]: { Mark } },
	crossHandlers    : { CrossHandler },
	rateLimits       : { [string]: RateLimitConfig },
	rateBuckets      : { [Player]: { [string]: { second: number, minute: number, lastSec: number, lastMin: number } } },
	honeypots        : { [string]: boolean },
	shadowHandlers   : { [Player]: (player: Player, envelope: Truck.PackageEnvelope) -> () },
	lockedDown       : { [Player]: boolean },
	sealed           : { [string]: boolean },
	driftSamples     : { [Player]: { number } },
	driftConfig      : { OnDetect: ((player: Player) -> ())? }?,
	fingerprintData  : { [Player]: { timestamps: { number }, counts: { [string]: number } } },
	fingerprintConfig: { OnFlag: ((player: Player, reason: string) -> ())? }?,
	signature        : string?,
	signedCallbacks  : { () -> () },
	bootstrapped     : boolean,
}

local state: SecurityState = {
	config            = nil,
	active            = false,
	sessions          = {},
	marks             = {},
	crossHandlers     = {},
	rateLimits        = {},
	rateBuckets       = {},
	honeypots         = {},
	shadowHandlers    = {},
	lockedDown        = {},
	sealed            = {},
	driftSamples      = {},
	driftConfig       = nil,
	fingerprintData   = {},
	fingerprintConfig = nil,
	signature         = nil,
	signedCallbacks   = {},
	bootstrapped      = false,
}

local TIMESTAMP_WINDOW = 5
local NONCE_HISTORY    = 512

local function deriveSignature(): string
	local epoch  = Shared.EPOCH
	local delta  = os.time() - epoch
	local seed   = 42 ^ (os.clock() / delta)
	local rng    = Random.new(seed)

	local raw = ""
	for _ = 1, 64 do
		raw = raw .. string.char(rng:NextInteger(1, 126))
	end

	local DOTT_MAP: { [string]: number } = {}
	for i = 1, 26 do
		DOTT_MAP[string.char(i + 96)] = i
	end
	for i = 0, 9 do
		DOTT_MAP[tostring(i)] = 27 + i
	end
	DOTT_MAP[" "] = 37

	local function dottEncode(input: string): string
		local result = ""
		for i = 1, #input do
			local c    = input:sub(i, i)
			local code = DOTT_MAP[c:lower()]
			if code then
				result = result .. string.format("%02d", code)
			else
				result = result .. "00"
			end
		end
		return result
	end

	local pass1 = dottEncode(raw)
	local pass2 = dottEncode(pass1)

	local translated = ""
	local i = 1
	while i <= #pass2 - 1 do
		local code = tonumber(pass2:sub(i, i + 1)) or 0
		local clamped = math.max(1, math.min(26, code))
		translated = translated .. string.char(clamped + 96)
		i += 2
	end

	return translated:sub(1, 32)
end

local function flagPlayer(player: Player, reason: string)
	if not state.marks[player] then
		state.marks[player] = {}
	end
	table.insert(state.marks[player], {
		Reason = reason,
		At     = os.time(),
	})
	if state.config and state.config.OnFlag then
		task.spawn(state.config.OnFlag :: (Player, string) -> (), player, reason)
	end
end

local function checkRateLimit(player: Player, mandateName: string): boolean
	local config = state.rateLimits[mandateName] or (state.config and state.config.RateLimit) or nil
	if not config then return true end

	if not state.rateBuckets[player] then
		state.rateBuckets[player] = {}
	end
	if not state.rateBuckets[player][mandateName] then
		state.rateBuckets[player][mandateName] = {
			second  = 0,
			minute  = 0,
			lastSec = os.time(),
			lastMin = os.time(),
		}
	end

	local bucket  = state.rateBuckets[player][mandateName]
	local now     = os.time()

	if now - bucket.lastSec >= 1 then
		bucket.second  = 0
		bucket.lastSec = now
	end
	if now - bucket.lastMin >= 60 then
		bucket.minute  = 0
		bucket.lastMin = now
	end

	bucket.second += 1
	bucket.minute += 1

	if config.MaxPerSecond and bucket.second > config.MaxPerSecond then
		return false
	end
	if config.MaxPerMinute and bucket.minute > config.MaxPerMinute then
		return false
	end

	return true
end

local function runCrossChain(
	packet  : CrossPacket,
	index   : number,
	onAllow : () -> ()
)
	if index > #state.crossHandlers then
		onAllow()
		return
	end
	local dropped = false
	local originalDrop = packet.Drop
	packet.Drop = function()
		dropped = true
		originalDrop()
	end
	state.crossHandlers[index](packet, function()
		if not dropped then
			runCrossChain(packet, index + 1, onAllow)
		end
	end)
end

function Security.verify(
	player   : Player,
	envelope : Truck.PackageEnvelope,
	onAllow  : () -> (),
	onDrop   : (reason: string) -> ()
)
	if state.lockedDown[player] then
		onDrop("player locked down")
		return
	end

	if state.honeypots[envelope.mandateName] then
		flagPlayer(player, "posted to honeypot: " .. envelope.mandateName)
		onDrop("honeypot")
		return
	end

	local shadowHandler = state.shadowHandlers[player]
	if shadowHandler then
		task.spawn(shadowHandler, player, envelope)
	end

	if state.active and state.config then
		local session = state.sessions[player]

		if not session then
			flagPlayer(player, "no session -- possible signature bypass")
			onDrop("no session")
			return
		end

		if envelope.signature ~= session.Signature then
			flagPlayer(player, "signature mismatch")
			onDrop("signature mismatch")
			return
		end

		if state.config.Nonce then
			if session.SeenNonces[envelope.nonce] then
				flagPlayer(player, "replay attack -- duplicate nonce")
				onDrop("duplicate nonce")
				return
			end
			session.SeenNonces[envelope.nonce] = true
			local nonceCount = Shared.tableSize(session.SeenNonces)
			if nonceCount > NONCE_HISTORY then
				local oldest = next(session.SeenNonces)
				if oldest then
					session.SeenNonces[oldest] = nil
				end
			end
		end

		if state.config.Sequence then
			if envelope.sequence <= session.LastSeq then
				flagPlayer(player, "sequence replay")
				onDrop("sequence replay")
				return
			end
			session.LastSeq = envelope.sequence
		end

		local drift = math.abs(os.time() - envelope.timestamp)
		if drift > TIMESTAMP_WINDOW then
			if state.driftConfig then
				state.driftSamples[player] = state.driftSamples[player] or {}
				table.insert(state.driftSamples[player], drift)
				if #state.driftSamples[player] > 10 then
					local avg = Shared.average(state.driftSamples[player])
					if avg > TIMESTAMP_WINDOW * 2 and state.driftConfig.OnDetect then
						task.spawn(state.driftConfig.OnDetect :: (Player) -> (), player)
					end
					table.remove(state.driftSamples[player], 1)
				end
			end
			flagPlayer(player, "timestamp outside window")
			onDrop("timestamp drift")
			return
		end
	end

	if not checkRateLimit(player, envelope.mandateName) then
		flagPlayer(player, "rate limit exceeded: " .. envelope.mandateName)
		onDrop("rate limit")
		return
	end

	if state.fingerprintConfig then
		if not state.fingerprintData[player] then
			state.fingerprintData[player] = { timestamps = {}, counts = {} }
		end
		local fp = state.fingerprintData[player]
		local now = os.clock()
		table.insert(fp.timestamps, now)
		fp.counts[envelope.mandateName] = (fp.counts[envelope.mandateName] or 0) + 1
		if #fp.timestamps > 100 then
			table.remove(fp.timestamps, 1)
		end
		if #fp.timestamps >= 10 then
			local variance = Shared.variance(fp.timestamps)
			if variance < 0.001 then
				if state.fingerprintConfig.OnFlag then
					task.spawn(
						state.fingerprintConfig.OnFlag :: (Player, string) -> (),
						player,
						"inhuman packet timing -- possible bot"
					)
				end
			end
		end
	end

	local dropped   = false
	local crossPkt  : CrossPacket = {
		Name      = envelope.mandateName,
		Package   = envelope.payload,
		Player    = player,
		Direction = "Inbound",
		At        = envelope.timestamp,
		Drop      = function()
			dropped = true
			onDrop("cross middleware dropped")
		end,
	}

	runCrossChain(crossPkt, 1, function()
		if not dropped then
			onAllow()
		end
	end)
end

function Security.setup(config: SecureConfig)
	Shared.assertServer("Security.setup")
	state.config = config
	state.active = true

	state.signature = deriveSignature()

	game:GetService("Players").PlayerAdded:Connect(function(player: Player)
		local sig = state.signature :: string

		state.sessions[player] = {
			Signature  = sig,
			IssuedAt   = os.time(),
			LastSeq    = 0,
			SeenNonces = {},
		}

		Truck.sendBootstrap(player, sig)
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		state.sessions[player]      = nil
		state.marks[player]         = nil
		state.rateBuckets[player]   = nil
		state.shadowHandlers[player]= nil
		state.lockedDown[player]    = nil
		state.driftSamples[player]  = nil
		state.fingerprintData[player]= nil
	end)

	for _, player in game:GetService("Players"):GetPlayers() do
		local sig = state.signature :: string
		state.sessions[player] = {
			Signature  = sig,
			IssuedAt   = os.time(),
			LastSeq    = 0,
			SeenNonces = {},
		}
		Truck.sendBootstrap(player, sig)
	end

	state.bootstrapped = true
	for _, cb in state.signedCallbacks do
		task.spawn(cb)
	end
	state.signedCallbacks = {}
end

function Security.setupClient()
	Truck.onBootstrapAck(function(signature: string)
		state.signature    = signature
		state.bootstrapped = true
		for _, cb in state.signedCallbacks do
			task.spawn(cb)
		end
		state.signedCallbacks = {}
	end)
end

function Security.onSigned(fn: () -> ())
	if state.bootstrapped then
		task.spawn(fn)
	else
		table.insert(state.signedCallbacks, fn)
	end
end

function Security.getSignature(): string?
	return state.signature
end

function Security.isBootstrapped(): boolean
	return state.bootstrapped
end

function Security.addCross(handler: CrossHandler)
	table.insert(state.crossHandlers, handler)
end

function Security.setRateLimit(mandateName: string, config: RateLimitConfig)
	Shared.assertServer("Security.setRateLimit")
	state.rateLimits[mandateName] = config
end

function Security.flag(player: Player, reason: string)
	Shared.assertServer("Security.flag")
	Shared.expectNotNil(player, "player")
	Shared.expect(reason, "reason", "string")
	flagPlayer(player, reason)
end

function Security.unflag(player: Player)
	Shared.assertServer("Security.unflag")
	state.marks[player] = {}
end

function Security.getMarks(player: Player): { Mark }
	return state.marks[player] or {}
end

function Security.honeypot(mandateName: string)
	Shared.assertServer("Security.honeypot")
	Shared.expect(mandateName, "mandateName", "string")
	state.honeypots[mandateName] = true
end

function Security.shadow(player: Player, handler: (player: Player, envelope: Truck.PackageEnvelope) -> ())
	Shared.assertServer("Security.shadow")
	state.shadowHandlers[player] = handler
end

function Security.lockdown(player: Player)
	Shared.assertServer("Security.lockdown")
	state.lockedDown[player] = true
end

function Security.unlock(player: Player)
	Shared.assertServer("Security.unlock")
	state.lockedDown[player] = nil
end

function Security.seal(mandateName: string)
	state.sealed[mandateName] = true
end

function Security.isSealed(mandateName: string): boolean
	return state.sealed[mandateName] == true
end

function Security.surge(player: Player, seconds: number)
	Shared.assertServer("Security.surge")
	local prev = state.rateBuckets[player]
	state.rateBuckets[player] = nil
	task.delay(seconds, function()
		if not state.rateBuckets[player] then
			state.rateBuckets[player] = prev
		end
	end)
end

function Security.drift(config: { OnDetect: ((player: Player) -> ())? })
	Shared.assertServer("Security.drift")
	state.driftConfig = config
end

function Security.fingerprint(config: { OnFlag: ((player: Player, reason: string) -> ())? })
	Shared.assertServer("Security.fingerprint")
	state.fingerprintConfig = config
end

function Security.mutePlayer(player: Player, mandateName: string)
	Shared.assertServer("Security.mutePlayer")
	if not state.rateLimits[mandateName .. ".__mute__" .. player.UserId] then
		state.rateLimits[mandateName .. ".__mute__" .. player.UserId] = {
			MaxPerSecond = 0,
			MaxPerMinute = 0,
		}
	end
end

function Security.unmutePlayer(player: Player, mandateName: string)
	Shared.assertServer("Security.unmutePlayer")
	state.rateLimits[mandateName .. ".__mute__" .. player.UserId] = nil
end

function Security.disconnectPlayer(player: Player)
	Shared.assertServer("Security.disconnectPlayer")
	state.sessions[player]    = nil
	state.rateBuckets[player] = nil
end

function Security.isActive(): boolean
	return state.active
end

return Security
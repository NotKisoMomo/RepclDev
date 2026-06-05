local HttpService = game:GetService("HttpService")

local Shared = {}

export type Map<K, V>    = { [K]: V }
export type Array<T>     = { T }
export type Option<T>    = T?
export type Callback     = (...any) -> ()
export type Destructor   = () -> ()

export type Result<T> = {
	Ok    : boolean,
	Value : T?,
	Error : string?,
}

export type Signal<T...> = {
	Connect    : (self: Signal<T...>, fn: (T...) -> ()) -> SignalConnection,
	Once       : (self: Signal<T...>, fn: (T...) -> ()) -> SignalConnection,
	Fire       : (self: Signal<T...>, T...) -> (),
	Destroy    : (self: Signal<T...>) -> (),
}

export type SignalConnection = {
	Disconnect : (self: SignalConnection) -> (),
	Connected  : boolean,
}

Shared.REMOTE_NAMES = {
	Lazy               = "__Mandy_Lazy",
	Unlazy             = "__Mandy_Unlazy",
	Resolver           = "__Mandy_Resolver",
	LazyDiagnostic     = "__Mandy_Lazy_Diagnostic",
	UnlazyDiagnostic   = "__Mandy_Unlazy_Diagnostic",
	ResolverDiagnostic = "__Mandy_Resolver_Diagnostic",
	Bootstrap          = "__Mandy_Bootstrap",
	Infra              = "__Mandy_Infra",
}

Shared.INFRA_TAGS = {
	ClockSync      = "CS",
	ClockSyncAck   = "CA",
	LagComp        = "LC",
	Bridge         = "BR",
	Stash          = "ST",
	Migrate        = "MG",
	Heartbeat      = "HB",
	HeartbeatAck   = "HA",
	Postit         = "PI",
	Diagnostic     = "DG",
}

Shared.MANDATE_TYPES = {
	Lazy     = "Lazy",
	Unlazy   = "Unlazy",
	Resolver = "Resolver",
}

Shared.MODIFIER_KEYS = {
	Linger   = "Linger",
	Distinct = "Distinct",
	Debounce = "Debounce",
	Throttle = "Throttle",
	Buffer   = "Buffer",
}

Shared.PRIORITY_LEVELS = {
	Critical = 1,
	High     = 2,
	Normal   = 3,
	Low      = 4,
}

Shared.QUALITY_GRADES = {
	Excellent = "Excellent",
	Good      = "Good",
	Fair      = "Fair",
	Poor      = "Poor",
}

Shared.IS_SERVER = game:GetService("RunService"):IsServer()

Shared.EPOCH = os.time({
	year  = 1970,
	month = 1,
	day   = 1,
	hour  = 0,
	min   = 0,
	sec   = 0,
	wday  = 5,
	yday  = 1,
	isdst = false,
})

function Shared.ok<T>(value: T): Result<T>
	return { Ok = true, Value = value, Error = nil }
end

function Shared.err<T>(error: string): Result<T>
	return { Ok = false, Value = nil, Error = error }
end

function Shared.assertServer(fnName: string)
	assert(Shared.IS_SERVER, string.format("[Mandy] %s is server-only", fnName))
end

function Shared.assertClient(fnName: string)
	assert(not Shared.IS_SERVER, string.format("[Mandy] %s is client-only", fnName))
end

function Shared.expect(value: any, name: string, expectedType: string)
	assert(
		type(value) == expectedType,
		string.format("[Mandy] expected %s to be %s, got %s", name, expectedType, type(value))
	)
end

function Shared.expectNotNil(value: any, name: string)
	assert(value ~= nil, string.format("[Mandy] %s must not be nil", name))
end

function Shared.shallowEqual(a: { [any]: any }, b: { [any]: any }): boolean
	for k, v in a do
		if b[k] ~= v then return false end
	end
	for k, v in b do
		if a[k] ~= v then return false end
	end
	return true
end

function Shared.deepCopy<T>(t: T): T
	if type(t) ~= "table" then return t end
	local copy = {}
	for k, v in t :: any do
		copy[k] = Shared.deepCopy(v)
	end
	return (copy :: any) :: T
end

function Shared.merge<T>(base: T, override: { [any]: any }): T
	local result = Shared.deepCopy(base) :: any
	for k, v in override do
		result[k] = v
	end
	return result
end

function Shared.generateId(): string
	return HttpService:GenerateGUID(false)
end

function Shared.clamp(value: number, min: number, max: number): number
	return math.max(min, math.min(max, value))
end

function Shared.rollingAverage(samples: { number }, maxSize: number, newValue: number): { number }
	local next = table.clone(samples)
	table.insert(next, newValue)
	if #next > maxSize then
		table.remove(next, 1)
	end
	return next
end

function Shared.average(samples: { number }): number
	if #samples == 0 then return 0 end
	local sum = 0
	for _, v in samples do sum += v end
	return sum / #samples
end

function Shared.variance(samples: { number }): number
	if #samples < 2 then return 0 end
	local avg = Shared.average(samples)
	local sumSq = 0
	for _, v in samples do sumSq += (v - avg) ^ 2 end
	return math.sqrt(sumSq / #samples)
end

function Shared.tableSize(t: { [any]: any }): number
	local count = 0
	for _ in t do count += 1 end
	return count
end

function Shared.includes<T>(arr: { T }, value: T): boolean
	for _, v in arr do
		if v == value then return true end
	end
	return false
end

function Shared.filter<T>(arr: { T }, predicate: (T) -> boolean): { T }
	local result: { T } = {}
	for _, v in arr do
		if predicate(v) then
			table.insert(result, v)
		end
	end
	return result
end

function Shared.map<T, U>(arr: { T }, transform: (T) -> U): { U }
	local result: { U } = {}
	for i, v in arr do
		result[i] = transform(v)
	end
	return result
end

function Shared.noop() end

return Shared
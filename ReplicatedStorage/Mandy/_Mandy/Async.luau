local Shared = require(script.Parent.Shared)

local Async = {}

type Map<K, V>  = Shared.Map<K, V>
type Array<T>   = Shared.Array<T>
type Option<T>  = Shared.Option<T>
type Callback   = Shared.Callback

export type SignalConnection = {
	Disconnect : (self: SignalConnection) -> (),
	Connected  : boolean,
}

export type Signal<T...> = {
	Connect : (self: Signal<T...>, fn: (T...) -> ()) -> SignalConnection,
	Once    : (self: Signal<T...>, fn: (T...) -> ()) -> SignalConnection,
	Fire    : (self: Signal<T...>, T...) -> (),
	Destroy : (self: Signal<T...>) -> (),
}

export type PromiseState = "Pending" | "Resolved" | "Rejected" | "Cancelled"

export type Promise<T> = {
	State    : PromiseState,
	Resolve  : (value: T) -> (),
	Reject   : (reason: string) -> (),
	Cancel   : (reason: string?) -> (),
	OnResolve: (fn: (T) -> ()) -> (),
	OnReject : (fn: (reason: string) -> ()) -> (),
	OnCancel : (fn: (reason: string?) -> ()) -> (),
}

export type Thread<T> = {
	Next     : (self: Thread<T>, fn: (package: T, resolve: (value: any) -> ()) -> ()) -> Thread<any>,
	Toss     : (self: Thread<T>, fn: (err: string, resolve: (value: any) -> ()) -> ()) -> Thread<any>,
	Conclude : (self: Thread<T>, fn: (original: T) -> ()) -> Thread<T>,
	Retry    : (self: Thread<T>, n: number) -> Thread<T>,
	Collapse : (self: Thread<T>, reason: string?) -> (),
}

export type Token = {
	Cancelled  : boolean,
	Reason     : string?,
	Cancel     : (self: Token, reason: string?) -> (),
	Next       : (self: Token, fn: ((package: { Reason: string? }, resolve: (value: any) -> ()) -> ())?) -> Thread<{ Reason: string? }>,
	Toss       : (self: Token, fn: (err: string, resolve: (value: any) -> ()) -> ()) -> Thread<any>,
	Conclude   : (self: Token, fn: (original: { Reason: string? }) -> ()) -> Thread<{ Reason: string? }>,
	Collapse   : (self: Token, reason: string?) -> (),
	Destroy    : (self: Token) -> (),
}

type SignalImpl<T...> = Signal<T...> & {
	_connections: { { fn: (T...) -> (), once: boolean } },
	_destroyed  : boolean,
}

local function createSignal<T...>(): Signal<T...>
	local self: SignalImpl<T...> = {
		_connections = {},
		_destroyed   = false,
	} :: any

	function self:Connect(fn: (T...) -> ()): SignalConnection
		assert(not self._destroyed, "[Mandy] Signal:Connect called on destroyed signal")
		local conn = { fn = fn, once = false }
		table.insert(self._connections, conn)
		return {
			Connected  = true,
			Disconnect = function(c: SignalConnection)
				c.Connected = false
				for i, v in self._connections do
					if v == conn then
						table.remove(self._connections, i)
						break
					end
				end
			end,
		}
	end

	function self:Once(fn: (T...) -> ()): SignalConnection
		assert(not self._destroyed, "[Mandy] Signal:Once called on destroyed signal")
		local conn = { fn = fn, once = true }
		table.insert(self._connections, conn)
		return {
			Connected  = true,
			Disconnect = function(c: SignalConnection)
				c.Connected = false
				for i, v in self._connections do
					if v == conn then
						table.remove(self._connections, i)
						break
					end
				end
			end,
		}
	end

	function self:Fire(...: T...)
		if self._destroyed then return end
		local toRemove: { number } = {}
		for i, conn in self._connections do
			conn.fn(...)
			if conn.once then
				table.insert(toRemove, i)
			end
		end
		for i = #toRemove, 1, -1 do
			table.remove(self._connections, toRemove[i])
		end
	end

	function self:Destroy()
		self._destroyed   = true
		self._connections = {}
	end

	return self
end

type PromiseImpl<T> = Promise<T> & {
	_state      : PromiseState,
	_value      : T?,
	_reason     : string?,
	_onResolve  : { (T) -> () },
	_onReject   : { (string) -> () },
	_onCancel   : { (string?) -> () },
}

local function createPromise<T>(): Promise<T>
	local self: PromiseImpl<T> = {
		State      = "Pending",
		_state     = "Pending",
		_value     = nil,
		_reason    = nil,
		_onResolve = {},
		_onReject  = {},
		_onCancel  = {},
	} :: any

	function self.Resolve(value: T)
		if self._state ~= "Pending" then return end
		self._state = "Resolved"
		self.State  = "Resolved"
		self._value = value
		for _, fn in self._onResolve do
			task.spawn(fn, value)
		end
		self._onResolve = {}
		self._onReject  = {}
		self._onCancel  = {}
	end

	function self.Reject(reason: string)
		if self._state ~= "Pending" then return end
		self._state  = "Rejected"
		self.State   = "Rejected"
		self._reason = reason
		for _, fn in self._onReject do
			task.spawn(fn, reason)
		end
		self._onResolve = {}
		self._onReject  = {}
		self._onCancel  = {}
	end

	function self.Cancel(reason: string?)
		if self._state ~= "Pending" then return end
		self._state  = "Cancelled"
		self.State   = "Cancelled"
		self._reason = reason
		for _, fn in self._onCancel do
			task.spawn(fn, reason)
		end
		self._onResolve = {}
		self._onReject  = {}
		self._onCancel  = {}
	end

	function self.OnResolve(fn: (T) -> ())
		if self._state == "Resolved" then
			task.spawn(fn, self._value :: T)
		elseif self._state == "Pending" then
			table.insert(self._onResolve, fn)
		end
	end

	function self.OnReject(fn: (string) -> ())
		if self._state == "Rejected" then
			task.spawn(fn, self._reason :: string)
		elseif self._state == "Pending" then
			table.insert(self._onReject, fn)
		end
	end

	function self.OnCancel(fn: (string?) -> ())
		if self._state == "Cancelled" then
			task.spawn(fn, self._reason)
		elseif self._state == "Pending" then
			table.insert(self._onCancel, fn)
		end
	end

	return self
end

type ThreadStep = {
	kind     : "next" | "toss" | "conclude",
	fn       : (any, ((any) -> ())?) -> (),
}

type ThreadImpl<T> = Thread<T> & {
	_promise   : Promise<T>,
	_steps     : { ThreadStep },
	_original  : T?,
	_retries   : number,
	_collapsed : boolean,
}

local function createThread<T>(promise: Promise<T>): Thread<T>
	local self: ThreadImpl<T> = {
		_promise   = promise,
		_steps     = {},
		_original  = nil,
		_retries   = 0,
		_collapsed = false,
	} :: any

	local function run(value: any, stepIndex: number, originalValue: any)
		if self._collapsed then return end
		if stepIndex > #self._steps then return end

		local step = self._steps[stepIndex]

		if step.kind == "conclude" then
			step.fn(originalValue, nil)
			run(value, stepIndex + 1, originalValue)
			return
		end

		if step.kind == "next" then
			local resolved = false
			local function resolve(newValue: any)
				if resolved then return end
				resolved = true
				run(newValue, stepIndex + 1, originalValue)
			end
			step.fn(value, resolve)
		end
	end

	local function runWithRetry(value: any)
		self._original = value
		run(value, 1, value)
	end

	local function handleReject(reason: string)
		if self._collapsed then return end
		if self._retries > 0 then
			self._retries -= 1
			promise.OnResolve(runWithRetry)
			return
		end
		for _, step in self._steps do
			if step.kind == "toss" then
				local resolved = false
				local function resolve(newValue: any)
					if resolved then return end
					resolved = true
					run(newValue, 1, self._original)
				end
				step.fn(reason, resolve)
				return
			end
		end
	end

	promise.OnResolve(runWithRetry)
	promise.OnReject(handleReject)

	function self:Next(fn: (package: any, resolve: (value: any) -> ()) -> ()): Thread<any>
		table.insert(self._steps, { kind = "next", fn = fn })
		return self :: any
	end

	function self:Toss(fn: (err: string, resolve: (value: any) -> ()) -> ()): Thread<any>
		table.insert(self._steps, { kind = "toss", fn = fn })
		return self :: any
	end

	function self:Conclude(fn: (original: any) -> ()): Thread<T>
		table.insert(self._steps, { kind = "conclude", fn = fn :: any })
		return self
	end

	function self:Retry(n: number): Thread<T>
		Shared.expect(n, "n", "number")
		self._retries = n
		return self
	end

	function self:Collapse(reason: string?)
		self._collapsed = true
		self._promise.Cancel(reason)
	end

	return self
end

local function createToken(): Token
	local signal   = createSignal :: any
	local promise  = createPromise :: any
	local thread   = createThread(promise)

	local self: Token = {
		Cancelled = false,
		Reason    = nil,
	} :: any

	function self:Cancel(reason: string?)
		if self.Cancelled then return end
		self.Cancelled = true
		self.Reason    = reason
		promise.Resolve({ Reason = reason })
		signal:Fire({ Reason = reason })
	end

	function self:Next(fn: ((package: { Reason: string? }, resolve: (value: any) -> ()) -> ())?): Thread<{ Reason: string? }>
		if fn then
			return thread:Next(fn)
		else
			if self.Cancelled then
				promise.Resolve({ Reason = self.Reason })
			end
			return thread
		end
	end

	function self:Toss(fn: (err: string, resolve: (value: any) -> ()) -> ()): Thread<any>
		return thread:Toss(fn)
	end

	function self:Conclude(fn: (original: { Reason: string? }) -> ()): Thread<{ Reason: string? }>
		return thread:Conclude(fn)
	end

	function self:Collapse(reason: string?)
		thread:Collapse(reason)
	end

	function self:Destroy()
		signal:Destroy()
	end

	return self
end

local function awaitPromise<T>(promise: Promise<T>): (boolean, T?, string?)
	local co      = coroutine.running()
	local resumed = false

	local function tryResume(ok: boolean, val: T?, err: string?)
		if resumed then return end
		resumed = true
		task.spawn(co, ok, val, err)
	end

	promise.OnResolve(function(value: T)
		tryResume(true, value, nil)
	end)
	promise.OnReject(function(reason: string)
		tryResume(false, nil, reason)
	end)
	promise.OnCancel(function(reason: string?)
		tryResume(false, nil, reason)
	end)

	return coroutine.yield()
end

Async.createSignal  = createSignal
Async.createPromise = createPromise
Async.createThread  = createThread
Async.createToken   = createToken
Async.awaitPromise  = awaitPromise

function Async.All(threads: { Thread<any> }): Thread<{ any }>
	local results: { any }     = {}
	local count                = #threads
	local resolved             = 0
	local promise              = createPromise

	if count == 0 then
		promise.Resolve({})
		return createThread(promise)
	end

	for i, t in threads do
		(t :: ThreadImpl<any>)._promise.OnResolve(function(value: any)
			results[i] = value
			resolved  += 1
			if resolved == count then
				promise.Resolve(results)
			end
		end);
		(t :: ThreadImpl<any>)._promise.OnReject(function(reason: string)
			promise.Reject(reason)
		end)
	end

	return createThread(promise)
end

function Async.Race(threads: { Thread<any> }): Thread<any>
	local promise = createPromise
	local settled = false

	for _, t in threads do
		(t :: ThreadImpl<any>)._promise.OnResolve(function(value: any)
			if settled then return end
			settled = true
			promise.Resolve(value)
		end);
		(t :: ThreadImpl<any>)._promise.OnReject(function(reason: string)
			if settled then return end
			settled = true
			promise.Reject(reason)
		end)
	end

	return createThread(promise)
end

function Async.Any(threads: { Thread<any> }): Thread<any>
	local promise  = createPromise
	local settled  = false
	local rejected = 0
	local count    = #threads

	for _, t in threads do
		(t :: ThreadImpl<any>)._promise.OnResolve(function(value: any)
			if settled then return end
			settled = true
			promise.Resolve(value)
		end);
		(t :: ThreadImpl<any>)._promise.OnReject(function()
			rejected += 1
			if rejected == count and not settled then
				promise.Reject("All threads rejected")
			end
		end)
	end

	return createThread(promise)
end

function Async.Settle(threads: { Thread<any> }): Thread<{ { state: string, value: any?, reason: string? } }>
	local results: { { state: string, value: any?, reason: string? } } = {}
	local count    = #threads
	local settled  = 0
	local promise  = createPromise

	if count == 0 then
		promise.Resolve({})
		return createThread(promise)
	end

	for i, t in threads do
		(t :: ThreadImpl<any>)._promise.OnResolve(function(value: any)
			results[i] = { state = "Resolved", value = value, reason = nil }
			settled   += 1
			if settled == count then promise.Resolve(results) end
		end);
		(t :: ThreadImpl<any>)._promise.OnReject(function(reason: string)
			results[i] = { state = "Rejected", value = nil, reason = reason }
			settled   += 1
			if settled == count then promise.Resolve(results) end
		end)
	end

	return createThread(promise)
end

function Async.Waterfall(fns: { (any) -> Thread<any> }): Thread<any>
	local promise = createPromise
	promise.Resolve(nil)
	local thread  = createThread(promise)

	for _, fn in fns do
		thread = thread:Next(function(value: any, resolve: (any) -> ())
			local next = fn(value)
			;(next :: ThreadImpl<any>)._promise.OnResolve(resolve)
		end)
	end

	return thread
end

function Async.Batch(threads: { Thread<any> }, n: number): Thread<{ any }>
	Shared.expect(n, "n", "number")
	local results  : { any } = {}
	local promise            = createPromise
	local index              = 0
	local completed          = 0
	local total              = #threads

	if total == 0 then
		promise.Resolve({})
		return createThread(promise)
	end

	local function runNext()
		index += 1
		if index > total then return end
		local i = index
		local t = threads[i]
		;(t :: ThreadImpl<any>)._promise.OnResolve(function(value: any)
			results[i]  = value
			completed  += 1
			if completed == total then
				promise.Resolve(results)
			else
				runNext()
			end
		end);
		(t :: ThreadImpl<any>)._promise.OnReject(function(reason: string)
			promise.Reject(reason)
		end)
	end

	for _ = 1, math.min(n, total) do
		runNext()
	end

	return createThread(promise)
end

function Async.Resolve<T>(value: T): Thread<T>
	local promise = createPromise
	promise.Resolve(value)
	return createThread(promise)
end

function Async.Reject<T>(reason: string): Thread<T>
	local promise = createPromise
	promise.Reject(reason)
	return createThread(promise)
end

function Async.Try<T>(fn: () -> T): Thread<T>
	local promise = createPromise
	local ok, result = pcall(fn)
	if ok then
		promise.Resolve(result :: T)
	else
		promise.Reject(tostring(result))
	end
	return createThread(promise)
end

return Async
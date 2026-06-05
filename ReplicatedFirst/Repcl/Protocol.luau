--!strict
local Req    = require(script.Parent.Req)
local Schema = require(script.Parent.deps.Schema)

local RunService = game:GetService("RunService")
local IS_SERVER  = RunService:IsServer()

local Protocol = {}

local EXEC_INVOKE  = "Repcl.Repl.Exec"
local EXEC_RESULT  = "Repcl.Repl.Result"

local S = Schema.Type

local _context: "Server" | "Client" = "Server"
local _defined  = false
local _onOutput: ((line: string) -> ())? = nil
local _onDone:   (() -> ())?             = nil

local function ensureDefined()
	if _defined then return end
	_defined = true
	Schema.define(EXEC_INVOKE, { source = S.string(), ctx = S.string() })
	Schema.define(EXEC_RESULT, { output = S.string(), done = S.boolean() })
end

local SANDBOX_ENV: { [string]: any } = {
	print   = print,
	warn    = warn,
	error   = error,
	pcall   = pcall,
	xpcall  = xpcall,
	pairs   = pairs,
	ipairs  = ipairs,
	next    = next,
	select  = select,
	tonumber = tonumber,
	tostring = tostring,
	type    = type,
	typeof  = typeof,
	unpack  = table.unpack,
	math    = math,
	table   = table,
	string  = string,
	task    = task,
	bit32   = bit32,
	os      = os,
	game    = game,
	workspace = workspace,
	script  = nil,
	require = nil,
}

local function runSandboxed(source: string, outputFn: (line: string) -> ()): (boolean, string)
	local env = setmetatable({}, { __index = SANDBOX_ENV })
	env.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, tostring(select(i, ...)))
		end
		outputFn(table.concat(parts, "\t"))
	end
	env.warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, tostring(select(i, ...)))
		end
		outputFn("[warn] " .. table.concat(parts, "\t"))
	end

	local fn, loadErr = loadstring(source)
	if not fn then
		return false, tostring(loadErr)
	end

	setfenv(fn, env)

	local ok, runErr = pcall(fn)
	if not ok then
		return false, tostring(runErr)
	end

	return true, ""
end

function Protocol.init(ctx: "Server" | "Client")
	_context = ctx
	ensureDefined()

	if IS_SERVER then
		Schema.subscribe(EXEC_INVOKE, function(player: Player?, data: any)
			if not player then return end
			local AuthMgr = Req("AuthManager")
			if not AuthMgr.checkRepl(player) then
				Schema.post(EXEC_RESULT, player, { output = "[error] Permission denied.", done = false })
				Schema.post(EXEC_RESULT, player, { output = "", done = true })
				return
			end

			task.spawn(function()
				local lines: {string} = {}
				local ok, err = runSandboxed(data.source, function(line: string)
					table.insert(lines, line)
					Schema.post(EXEC_RESULT, player, { output = line, done = false })
				end)
				if not ok then
					Schema.post(EXEC_RESULT, player, { output = "[error] " .. err, done = false })
				end
				Schema.post(EXEC_RESULT, player, { output = "", done = true })
			end)
		end)
	else
		Schema.subscribe(EXEC_RESULT, function(_player: Player?, data: any)
			if data.done then
				if _onDone then _onDone() end
			else
				if _onOutput then _onOutput(data.output) end
			end
		end)
	end
end

function Protocol.setContext(ctx: "Server" | "Client")
	_context = ctx
end

function Protocol.execute(source: string, onOutput: (line: string) -> (), onDone: () -> ())
	ensureDefined()
	_onOutput = onOutput
	_onDone   = onDone

	if _context == "Server" then
		Schema.post(EXEC_INVOKE, { source = source, ctx = "Server" })
	else
		task.spawn(function()
			local ok, err = runSandboxed(source, onOutput)
			if not ok then
				onOutput("[error] " .. err)
			end
			onDone()
		end)
	end
end

return Protocol
--!strict
-- Executor.lua
-- Fixes applied:
--   (1) def.Run support — commands using Run= are now executed correctly
--   (2) Bridge detection via Context == "Bridge" instead of def.Bridge boolean
--   (3) ctx.Flags, ctx.Error alias, ctx.Notify preserved
--   (4) Args resolved by name (ArgDef.Name) before falling back to positional index

local Req     = require(script.Parent.Req)
local Types   = require(script.Parent.Types)
local Network = require(script.Parent.Network)

type CommandDef  = Types.CommandDef
type RepclCtx    = Types.RepclCtx
type ParseResult = Types.ParseResult

local Executor = {}

local function buildCtx(def: CommandDef, parsed: ParseResult, player: Player?, isServer: boolean): RepclCtx
	local output: { Types.OutputEntry } = {}
	local commitPayload: any = nil

	local ctx: RepclCtx = {
		Args     = parsed.args,
		Flags    = parsed.flags,
		Player   = player :: Player,
		IsServer = isServer,

		Print = function(msg: string)
			table.insert(output, { kind = "print", text = msg })
		end,
		Warn = function(msg: string)
			table.insert(output, { kind = "warn", text = msg })
		end,
		Err = function(msg: string)
			table.insert(output, { kind = "error", text = msg })
		end,
		Error = function(msg: string)
			table.insert(output, { kind = "error", text = msg })
		end,
		Notify = function(msg: string)
			table.insert(output, { kind = "notify", text = msg })
		end,
		Reply = function(msg: string)
			table.insert(output, { kind = "reply", text = msg })
		end,
		Abort = function(reason: string?)
			error("__repcl_abort__" .. (reason or ""), 0)
		end,
		Commit = function(payload: any)
			commitPayload = payload
		end,

		_getOutput = function(): { Types.OutputEntry }
			return output
		end,
		_getCommit = function(): any
			return commitPayload
		end,
	}

	return ctx
end

-- Resolve a token list into a named args table using ArgDef names.
-- Variadic args collect all remaining tokens into a table keyed by Name.
-- Falls back to numeric string keys for any args with no ArgDef.
local function resolveArgs(def: CommandDef, argTokens: { string }): { [string]: any }
	local result: { [string]: any } = {}
	local argDefs = def.Args or {}

	-- Import TypeSystem lazily to avoid circular deps
	local ok, TypeSystem = pcall(require, script.Parent.TypeSystem)
	if not ok then TypeSystem = nil end

	local function parseToken(raw: string, typeName: string?): any
		if not typeName or not TypeSystem then return raw end
		local typeDef = TypeSystem.get(typeName)
		if typeDef and typeDef.Parse then
			local parsed = typeDef.Parse(raw)
			return parsed ~= nil and parsed or raw
		end
		return raw
	end

	for i, argDef in argDefs do
		local ad = argDef :: any
		if ad.Variadic then
			-- Collect all remaining tokens from position i onwards
			local collected = {}
			for j = i, #argTokens do
				local typeName = (ad.Types and ad.Types[1]) or ad.Type
				table.insert(collected, parseToken(argTokens[j], typeName))
			end
			result[ad.Name] = #collected > 0 and collected or (ad.Default ~= nil and { ad.Default } or {})
			break
		else
			local raw = argTokens[i]
			if raw ~= nil then
				local typeName = (ad.Types and ad.Types[1]) or ad.Type
				result[ad.Name] = parseToken(raw, typeName)
			elseif ad.Default ~= nil then
				result[ad.Name] = ad.Default
			end
		end
	end

	-- Stash any extra positional tokens that had no ArgDef under numeric keys
	for i = #argDefs + 1, #argTokens do
		result[i] = argTokens[i]
	end

	return result
end

-- Resolve flag tokens into a named flags table using FlagDef.
local function resolveFlags(def: CommandDef, flagTokens: { string }): { [string]: any }
	local result: { [string]: any } = {}
	local flagDefs = def.Flags or {}

	-- Build lookup: short/name -> FlagDef
	local lookup: { [string]: any } = {}
	for _, fd in flagDefs do
		local f = fd :: any
		if f.Short then lookup[f.Short:lower()] = f end
		if f.Name  then lookup[f.Name:lower()]  = f end
	end

	for _, token in flagTokens do
		-- Flags arrive as "-v" or "--verbose" or "-v=value"
		local stripped = token:match("^%-%-(.+)") or token:match("^%-(.+)") or token
		local key, val = stripped:match("^([^=]+)=(.*)$")
		if not key then key = stripped end

		local fd = lookup[key:lower()]
		if fd then
			-- Boolean flags: presence = true; valued flags: use val or next token
			local typeName = (fd.Types and fd.Types[1]) or fd.Type
			if typeName and typeName ~= "Boolean" and val then
				result[fd.Name] = val
			else
				result[fd.Name] = val or true
			end
		else
			-- Unknown flag — store raw under its stripped key
			result[key] = val or true
		end
	end

	return result
end

-- Core run: picks def.Run, def.Client, or def.Server depending on context.
-- Bridge commands: client side calls def.Client, captures Commit, fires Network.sendBridge.
function Executor.run(def: CommandDef, parsed: ParseResult, player: Player?)
	local isServer = game:GetService("RunService"):IsServer()

	-- Resolve args/flags if parsed.args is a raw token list (array of strings)
	-- Interface passes { args = argTokens, flags = flagTokens, raw = ... }
	-- so we need to promote token arrays into named tables.
	local resolvedArgs:  { [string]: any }
	local resolvedFlags: { [string]: any }

	-- Detect whether args is already named (string keys) or still a token array
	local argsIsTokenList = true
	if type(parsed.args) == "table" then
		for k in parsed.args do
			if type(k) == "string" and not tonumber(k) then
				argsIsTokenList = false
				break
			end
		end
	end

	if argsIsTokenList then
		-- Convert token array → named table using ArgDefs
		local tokenArr: { string } = {}
		for i = 1, #(parsed.args :: any) do
			tokenArr[i] = tostring((parsed.args :: any)[i])
		end
		resolvedArgs = resolveArgs(def, tokenArr)
	else
		resolvedArgs = parsed.args
	end

	-- Flags: token list is an array of "-flag" strings; named table has string keys
	local flagsIsTokenList = true
	if type(parsed.flags) == "table" then
		for k in parsed.flags do
			if type(k) == "string" and not tonumber(k) and not k:match("^%-") then
				flagsIsTokenList = false
				break
			end
		end
	end

	if flagsIsTokenList then
		local tokenArr: { string } = {}
		for i = 1, #(parsed.flags :: any) do
			tokenArr[i] = tostring((parsed.flags :: any)[i])
		end
		resolvedFlags = resolveFlags(def, tokenArr)
	else
		resolvedFlags = parsed.flags
	end

	local resolvedParsed: ParseResult = {
		args  = resolvedArgs,
		flags = resolvedFlags,
		raw   = parsed.raw,
	}

	-- Bridge: client runs Client(), captures Commit payload, sends to server
	local isBridge = (def :: any).Context == "Bridge"
	if isBridge then
		if isServer then
			warn("[Repcl] Executor.run called on server for a Bridge command — use runServerBridge instead")
			return nil
		end
		local ctx = buildCtx(def, resolvedParsed, player, false)
		local clientFn = (def :: any).Client or (def :: any).Run
		local ok, err = pcall(function()
			if clientFn then clientFn(ctx) end
		end)
		local payload = ctx._getCommit()
		local output  = ctx._getOutput()
		if not ok and not string.find(tostring(err), "__repcl_abort__") then
			table.insert(output, { kind = "error", text = tostring(err) })
		end
		if payload ~= nil then
			Network.sendBridge((def :: any).Name, payload)
		end
		return output
	end

	if isServer then
		local ctx = buildCtx(def, resolvedParsed, player, true)
		local fn = (def :: any).Server or (def :: any).Run
		local ok, err = pcall(function()
			if fn then fn(ctx) end
		end)
		local output = ctx._getOutput()
		if not ok and not string.find(tostring(err), "__repcl_abort__") then
			table.insert(output, { kind = "error", text = tostring(err) })
		end
		return output
	else
		local ctx = buildCtx(def, resolvedParsed, player, false)
		local fn = (def :: any).Client or (def :: any).Run
		local ok, err = pcall(function()
			if fn then fn(ctx) end
		end)
		local output = ctx._getOutput()
		if not ok and not string.find(tostring(err), "__repcl_abort__") then
			table.insert(output, { kind = "error", text = tostring(err) })
		end
		return output
	end
end

function Executor.runServerBridge(player: Player, cmdName: string, payload: any)
	local Registry = Req("Registry")
	local def = Registry.get(cmdName)
	if not def then
		warn("[Repcl] runServerBridge: unknown command", cmdName)
		return
	end
	if (def :: any).Context ~= "Bridge" then
		warn("[Repcl] runServerBridge: command is not a Bridge command", cmdName)
		return
	end
	local parsed: ParseResult = {
		args  = payload.args  or {},
		flags = payload.flags or {},
		raw   = payload.raw   or "",
	}
	local ctx = buildCtx(def, parsed, player, true)
	local serverFn = (def :: any).Server or (def :: any).Run
	local ok, err = pcall(function()
		if serverFn then serverFn(ctx) end
	end)
	local output = ctx._getOutput()
	if not ok and not string.find(tostring(err), "__repcl_abort__") then
		table.insert(output, { kind = "error", text = tostring(err) })
	end
	Network.sendOutput(player, output)
end

return Executor
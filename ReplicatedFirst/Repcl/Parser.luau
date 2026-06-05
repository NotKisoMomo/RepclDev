local Types = require(script.Parent.Types)
type AST       = Types.AST
type ChainNode = Types.ChainNode
type ChainOp   = Types.ChainOp

local COND_OPS = { "!=", ">=", "<=", "=", ">", "<", "~", "!" }

local customTokens:   { [string]: { handler: (any, any, { any }) -> any } } = {}
local customResolvers: { [string]: (raw: string, stack: { any }) -> any }   = {}

local Parser = {}

function Parser.DefineToken(symbol: string, config: { handler: (any, any, { any }) -> any })
	customTokens[symbol] = config
end

function Parser.DefineResolver(name: string, fn: (raw: string, stack: { any }) -> any)
	customResolvers[name] = fn
end

function Parser.Tokenize(raw: string): { string }
	local tokens:  { string } = {}
	local current = ""
	local i = 1

	while i <= #raw do
		local c = raw:sub(i, i)

		if c == '"' then
			local j = raw:find('"', i + 1, true)
			if j then
				if current ~= "" then table.insert(tokens, current); current = "" end
				table.insert(tokens, raw:sub(i + 1, j - 1))
				i = j + 1
			else
				current ..= c
				i += 1
			end
		elseif c == " " or c == "\t" then
			if current ~= "" then table.insert(tokens, current); current = "" end
			i += 1
		else
			local two = raw:sub(i, i + 1)
			if two == "&&" or two == "||" or two == "!=" or two == ">=" or two == "<=" then
				if current ~= "" then table.insert(tokens, current); current = "" end
				table.insert(tokens, two)
				i += 2
			else
				current ..= c
				i += 1
			end
		end
	end

	if current ~= "" then table.insert(tokens, current) end
	return tokens
end

local function splitChain(tokens: { string }): { { tokens: { string }, op: ChainOp? } }
	local segments: { { tokens: { string }, op: ChainOp? } } = {}
	local current:  { string } = {}
	local pendingOp: ChainOp?  = nil

	for _, t in tokens do
		if t == "&" or t == "&&" or t == "||" then
			if #current > 0 then
				table.insert(segments, { tokens = current, op = pendingOp })
				current = {}
			end
			pendingOp = t :: ChainOp
		else
			table.insert(current, t)
		end
	end

	if #current > 0 then
		table.insert(segments, { tokens = current, op = pendingOp })
	end

	return segments
end

local function parseCond(tokens: { string }): ({ op: string, left: string, right: string }?, { string })
	for _, op in COND_OPS do
		for i, t in tokens do
			if t == op then
				local left  = i > 1 and tokens[i - 1] or ""
				local right = tokens[i + 1] or ""
				local rem:  { string } = {}
				for j, tok in tokens do
					if j ~= i - 1 and j ~= i and j ~= i + 1 then
						table.insert(rem, tok)
					end
				end
				return { op = op, left = left, right = right }, rem
			end
		end
	end
	return nil, tokens
end

function Parser.Parse(raw: string): AST
	local tokens   = Parser.Tokenize(raw)
	local segments = splitChain(tokens)
	local ast: AST = {}

	for idx, seg in segments do
		local cond, remaining = parseCond(seg.tokens)
		local cmdName = remaining[1] or ""

		local argTokens:  { string } = {}
		local flagTokens: { string } = {}

		for i = 2, #remaining do
			local t = remaining[i]
			if t:sub(1, 1) == "-" then
				table.insert(flagTokens, t)
			else
				table.insert(argTokens, t)
			end
		end

		local nextSeg = segments[idx + 1]

		table.insert(ast, {
			command    = cmdName,
			op         = nextSeg and nextSeg.op or nil,
			cond       = cond,
			argTokens  = argTokens,
			flagTokens = flagTokens,
		} :: ChainNode)
	end

	return ast
end

function Parser.ResolveStackRef(ref: string, stack: { any }): any
	if not ref:match("^_+") then return nil end

	local depth = 0
	local rest  = ref
	while rest:sub(1, 1) == "_" do
		depth += 1
		rest = rest:sub(2)
	end

	local idx = #stack - (depth - 1)
	if idx < 1 then return nil end

	local obj = stack[idx]
	if rest == "" then return obj end

	local parts = rest:sub(2):split(".")
	for _, part in parts do
		if obj == nil then return nil end
		obj = (obj :: any)[part]
	end
	return obj
end

function Parser.EvalMath(expr: string, stack: { any }): number?
	local resolved = expr:gsub("(_+%.?[%w%.]*)", function(ref)
		local val = Parser.ResolveStackRef(ref, stack)
		return type(val) == "number" and tostring(val) or "nil"
	end)
	local fn = loadstring("return " .. resolved)
	if not fn then return nil end
	local ok, result = pcall(fn)
	return (ok and type(result) == "number") and result or nil
end

local function evalCond(cond: { op: string, left: string, right: string }, stack: { any }): boolean
	local function resolveVal(s: string): any
		if s:match("^_+") then return Parser.ResolveStackRef(s, stack) end
		return tonumber(s) or s
	end

	local op    = cond.op
	local left  = resolveVal(cond.left)
	local right = resolveVal(cond.right)

	if op == "~"  then return left ~= nil end
	if op == "!"  then return left == nil end
	if op == "="  then return left == right end
	if op == "!=" then return left ~= right end

	local ln = type(left)  == "number" and left  or nil
	local rn = type(right) == "number" and right or nil
	if ln and rn then
		if op == ">"  then return (ln :: number) >  (rn :: number) end
		if op == "<"  then return (ln :: number) <  (rn :: number) end
		if op == ">=" then return (ln :: number) >= (rn :: number) end
		if op == "<=" then return (ln :: number) <= (rn :: number) end
	end

	return false
end

function Parser.Execute(
	ast: AST,
	runFn: (cmdName: string, argTokens: { string }, flagTokens: { string }) -> (any, string?)
): { results: { any }, errors: { string } }
	local stack:   { any }    = {}
	local results: { any }    = {}
	local errors:  { string } = {}

	for i, node in ast do
		if node.cond then
			local pass = evalCond(node.cond, stack)
			if not pass then
				local prevOp = i > 1 and ast[i - 1].op or nil
				if prevOp == "&&" then break end
				continue
			end
		end

		local resolvedArgs: { string } = {}
		for _, t in node.argTokens do
			if t:match("^_+") then
				local val = Parser.ResolveStackRef(t, stack)
				table.insert(resolvedArgs, val ~= nil and tostring(val) or t)
			elseif t:match("_") and t:match("[%+%-%*/%%]") then
				local val = Parser.EvalMath(t, stack)
				table.insert(resolvedArgs, val ~= nil and tostring(val) or t)
			else
				table.insert(resolvedArgs, t)
			end
		end

		local result, err = runFn(node.command, resolvedArgs, node.flagTokens)
		local op = node.op

		if err then
			table.insert(errors, err)
			if op == "&&" then break end
		else
			if result ~= nil then table.insert(stack, result) end
			table.insert(results, result)
		end
	end

	return { results = results, errors = errors }
end

return Parser
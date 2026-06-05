local Lexer   = require(script.Parent.Lexer)
local Grammar = require(script.Parent.Grammar)

local Analyzer = {}

export type ScopeVar = {
	name:     string,
	typeName: string?,
	token:    Lexer.Token,
}

export type Scope = {
	parent: Scope?,
	vars:   { [string]: ScopeVar },
}

export type CursorContext = {
	kind:       "global" | "member" | "method" | "argument" | "keyword" | "unknown",
	prefix:     string,
	objectType: string?,
	argIndex:   number?,
	cmdName:    string?,
	token:      Lexer.Token?,
}

export type AnalysisResult = {
	tokens:  {Lexer.Token},
	scope:   Scope,
	cursor:  CursorContext,
	locals:  { [string]: ScopeVar },
}

local function newScope(parent: Scope?): Scope
	return { parent = parent, vars = {} }
end

local function scopeGet(scope: Scope, name: string): ScopeVar?
	local s: Scope? = scope
	while s do
		local v = s.vars[name]
		if v then return v end
		s = s.parent
	end
	return nil
end

local function scopeSet(scope: Scope, name: string, var: ScopeVar)
	scope.vars[name] = var
end

local KNOWN_SERVICE_TYPES: { [string]: string } = {
	Players               = "Players",
	Workspace             = "Workspace",
	RunService            = "RunService",
	TweenService          = "TweenService",
	UserInputService      = "UserInputService",
	ReplicatedStorage     = "ReplicatedStorage",
	ServerStorage         = "ServerStorage",
	ServerScriptService   = "ServerScriptService",
	DataStoreService      = "DataStoreService",
	HttpService           = "HttpService",
	PathfindingService    = "PathfindingService",
	CollectionService     = "CollectionService",
	PhysicsService        = "PhysicsService",
	ContextActionService  = "ContextActionService",
	SoundService          = "SoundService",
	MarketplaceService    = "MarketplaceService",
	Teams                 = "Teams",
	Lighting              = "Lighting",
}

local CONSTRUCTOR_TYPES: { [string]: string } = {
	Vector3       = "Vector3",
	Vector2       = "Vector2",
	CFrame        = "CFrame",
	Color3        = "Color3",
	UDim2         = "UDim2",
	UDim          = "UDim",
	TweenInfo     = "TweenInfo",
	NumberRange   = "NumberRange",
	NumberSequence = "NumberSequence",
	ColorSequence = "ColorSequence",
	Rect          = "Rect",
	Region3       = "Region3",
	Ray           = "Ray",
	BrickColor    = "BrickColor",
	RaycastParams = "RaycastParams",
	OverlapParams = "OverlapParams",
}

local function inferTypeFromExpr(tokens: {Lexer.Token}, idx: number, scope: Scope): string?
	local tok = tokens[idx]
	if not tok then return nil end

	if tok.kind == "identifier" then
		local next1 = tokens[idx + 1]
		local next2 = tokens[idx + 2]

		if tok.value == "game" and next1 and next1.value == ":" then
			local method = tokens[idx + 2]
			if method and (method.value == "GetService" or method.value == "FindService") then
				local openParen = tokens[idx + 3]
				local svcName   = tokens[idx + 4]
				if openParen and openParen.value == "(" and svcName and svcName.kind == "string" then
					local name = string.match(svcName.value, '"([^"]+)"') or string.match(svcName.value, "'([^']+)'")
					if name then return KNOWN_SERVICE_TYPES[name] end
				end
			end
		end

		if next1 and next1.value == "." and next2 and next2.value == "new" then
			return CONSTRUCTOR_TYPES[tok.value]
		end

		if next1 and next1.value == "." and next2 then
			local parentType = inferTypeFromExpr(tokens, idx, scope)
			if parentType then
				local member = Grammar.lookupMember(parentType, next2.value)
				if member then return member.detail end
			end
		end

		local var = scopeGet(scope, tok.value)
		if var and var.typeName then return var.typeName end

		local entry = Grammar.lookup(tok.value)
		if entry then return entry.label end
	end

	return nil
end

local function extractLocals(tokens: {Lexer.Token}, scope: Scope)
	local i = 1
	while i <= #tokens do
		local tok = tokens[i]

		if tok.kind == "keyword" and tok.value == "local" then
			local next = tokens[i + 1]
			if next and next.kind == "identifier" then
				local typeName: string? = nil
				local j = i + 2
				local jt = tokens[j]
				if jt and jt.value == ":" then
					local typeToken = tokens[j + 1]
					if typeToken and typeToken.kind == "identifier" then
						typeName = typeToken.value
						j += 2
						jt = tokens[j]
					end
				end
				if jt and jt.value == "=" then
					typeName = typeName or inferTypeFromExpr(tokens, j + 1, scope)
				end
				scopeSet(scope, next.value, {
					name     = next.value,
					typeName = typeName,
					token    = next,
				})
			end
		end

		i += 1
	end
end

local function buildCursorContext(tokens: {Lexer.Token}, cursorPos: number, scope: Scope): CursorContext
	local _, tokIdx = Lexer.tokenAtPos(tokens, cursorPos)

	local cur   = tokens[tokIdx]
	local prev1 = tokIdx > 1 and tokens[tokIdx - 1] or nil
	local prev2 = tokIdx > 2 and tokens[tokIdx - 2] or nil
	local prev3 = tokIdx > 3 and tokens[tokIdx - 3] or nil

	local prefix = ""
	if cur and (cur.kind == "identifier" or cur.kind == "keyword") then
		prefix = cur.value
	end

	if prev1 and (prev1.value == "." or prev1.value == ":") and prev2 then
		local isMethod = prev1.value == ":"
		local objectName = prev2.value
		local objectType: string? = nil

		local var = scopeGet(scope, objectName)
		if var and var.typeName then
			objectType = var.typeName
		else
			local entry = Grammar.lookup(objectName)
			if entry then objectType = entry.label end
		end

		if not objectType and prev3 and prev3.value == "." and tokens[tokIdx - 4] then
			local chainBase = tokens[tokIdx - 4].value
			local baseType = (scopeGet(scope, chainBase) or {typeName=nil}).typeName
				or (Grammar.lookup(chainBase) and Grammar.lookup(chainBase).label)
			if baseType then
				local member = Grammar.lookupMember(baseType, objectName)
				if member and member.detail then objectType = member.detail end
			end
		end

		return {
			kind       = isMethod and "method" or "member",
			prefix     = prefix,
			objectType = objectType or objectName,
			token      = cur,
		}
	end

	if cur and cur.kind == "keyword" then
		return { kind = "keyword", prefix = prefix, token = cur }
	end

	return { kind = "global", prefix = prefix, token = cur }
end

function Analyzer.analyze(src: string, cursorPos: number): AnalysisResult
	local allTokens = Lexer.tokenize(src)
	local significant = Lexer.stripTrivia(allTokens)

	local rootScope = newScope(nil)
	extractLocals(significant, rootScope)

	local flatLocals: { [string]: ScopeVar } = {}
	for k, v in rootScope.vars do
		flatLocals[k] = v
	end

	local cursor = buildCursorContext(significant, cursorPos, rootScope)

	return {
		tokens = significant,
		scope  = rootScope,
		cursor = cursor,
		locals = flatLocals,
	}
end

function Analyzer.getWordAtCursor(src: string, cursorPos: number): (string, number, number)
	local startI = cursorPos
	while startI > 1 do
		local c = string.sub(src, startI - 1, startI - 1)
		if not (c:match("[%w_]")) then break end
		startI -= 1
	end
	local endI = cursorPos
	while endI <= #src do
		local c = string.sub(src, endI, endI)
		if not (c:match("[%w_]")) then break end
		endI += 1
	end
	return string.sub(src, startI, endI - 1), startI, endI - 1
end

function Analyzer.getMemberChain(src: string, cursorPos: number): {string}
	local chain: {string} = {}
	local pos = cursorPos
	while pos > 1 do
		local c = string.sub(src, pos - 1, pos - 1)
		if c:match("[%w_]") then
			local wordEnd = pos - 1
			local wordStart = wordEnd
			while wordStart > 1 and string.sub(src, wordStart - 1, wordStart - 1):match("[%w_]") do
				wordStart -= 1
			end
			table.insert(chain, 1, string.sub(src, wordStart, wordEnd))
			pos = wordStart
		elseif c == "." or c == ":" then
			pos -= 1
		else
			break
		end
	end
	return chain
end

return Analyzer
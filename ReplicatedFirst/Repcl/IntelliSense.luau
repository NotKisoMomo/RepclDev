local Grammar  = require(script.Parent.Grammar)
local Analyzer = require(script.Parent.Analyzer)

local IntelliSense = {}

export type CompletionItem = {
	label:       string,
	kind:        Grammar.CompletionKind,
	detail:      string?,
	insertText:  string?,
	sortScore:   number,
}

export type CompletionResult = {
	items:     {CompletionItem},
	replacing: { start: number, finish: number }?,
}

local KIND_SCORE: { [Grammar.CompletionKind]: number } = {
	keyword  = 0,
	snippet  = 1,
	repcl    = 2,
	builtin  = 3,
	global   = 4,
	property = 5,
	method   = 6,
	type     = 7,
}

local function makeItem(entry: Grammar.GrammarEntry | Grammar.Completion, localBoost: boolean?): CompletionItem
	local base = KIND_SCORE[entry.kind] or 9
	return {
		label      = entry.label,
		kind       = entry.kind,
		detail     = entry.detail,
		insertText = entry.insertText,
		sortScore  = localBoost and (base - 0.5) or base,
	}
end

local function fuzzyMatch(candidate: string, prefix: string): boolean
	if prefix == "" then return true end
	local ci = 1
	local pl = string.lower(prefix)
	local cl = string.lower(candidate)
	for pi = 1, #pl do
		local pc = string.sub(pl, pi, pi)
		while ci <= #cl do
			if string.sub(cl, ci, ci) == pc then
				ci += 1
				break
			end
			ci += 1
		end
		if ci > #cl + 1 then return false end
	end
	return true
end

local function prefixMatch(candidate: string, prefix: string): boolean
	if prefix == "" then return true end
	return string.lower(string.sub(candidate, 1, #prefix)) == string.lower(prefix)
end

function IntelliSense.complete(src: string, cursorPos: number): CompletionResult
	local analysis = Analyzer.analyze(src, cursorPos)
	local ctx      = analysis.cursor
	local prefix   = ctx.prefix

	local word, wStart, wEnd = Analyzer.getWordAtCursor(src, cursorPos)
	local replacing: { start: number, finish: number }? = nil
	if word ~= "" then
		replacing = { start = wStart, finish = wEnd }
	end

	local items: {CompletionItem} = {}
	local seen: { [string]: boolean } = {}

	local function add(entry: Grammar.GrammarEntry | Grammar.Completion, boost: boolean?)
		if seen[entry.label] then return end
		if prefixMatch(entry.label, prefix) or fuzzyMatch(entry.label, prefix) then
			seen[entry.label] = true
			table.insert(items, makeItem(entry, boost))
		end
	end

	if ctx.kind == "member" or ctx.kind == "method" then
		local objectType = ctx.objectType
		if objectType then
			local grammarEntry = Grammar.lookup(objectType)
			if grammarEntry and grammarEntry.members then
				for _, member in grammarEntry.members do
					if ctx.kind == "method" then
						if member.kind == "method" then add(member) end
					else
						add(member)
					end
				end
			end
		end

		if #items == 0 then
			local grammarResults = Grammar.complete(prefix, objectType)
			for _, entry in grammarResults do add(entry) end
		end
	else
		for name, var in analysis.locals do
			if prefixMatch(name, prefix) or fuzzyMatch(name, prefix) then
				if not seen[name] then
					seen[name] = true
					table.insert(items, {
						label      = name,
						kind       = "global",
						detail     = var.typeName and ("local " .. var.typeName) or "local",
						insertText = nil,
						sortScore  = -1,
					})
				end
			end
		end

		local grammarResults = Grammar.complete(prefix)
		for _, entry in grammarResults do add(entry) end

		for _, entry in Grammar.Snippets do add(entry) end
		for _, entry in Grammar.RepclContext do add(entry) end
	end

	table.sort(items, function(a, b)
		if a.sortScore ~= b.sortScore then return a.sortScore < b.sortScore end
		local ap = prefixMatch(a.label, prefix) and 0 or 1
		local bp = prefixMatch(b.label, prefix) and 0 or 1
		if ap ~= bp then return ap < bp end
		return a.label < b.label
	end)

	if #items > 50 then
		local trimmed: {CompletionItem} = {}
		for i = 1, 50 do trimmed[i] = items[i] end
		items = trimmed
	end

	return { items = items, replacing = replacing }
end

function IntelliSense.signature(src: string, cursorPos: number): (string?, string?)
	local before = string.sub(src, 1, cursorPos)
	local depth  = 0
	local funcEnd = cursorPos

	for i = #before, 1, -1 do
		local c = string.sub(before, i, i)
		if c == ")" then
			depth += 1
		elseif c == "(" then
			if depth == 0 then
				funcEnd = i - 1
				break
			end
			depth -= 1
		end
	end

	local funcName = string.match(string.sub(before, 1, funcEnd), "([%w_%.%:]+)%s*$")
	if not funcName then return nil, nil end

	local base, member = string.match(funcName, "^([%w_]+)[%.%:]([%w_]+)$")
	if base and member then
		local entry = Grammar.lookup(base)
		if entry and entry.members then
			local m = entry.members[member]
			if m then return funcName, m.detail end
		end
	end

	local entry = Grammar.lookup(funcName)
	if entry then return funcName, entry.detail end

	return funcName, nil
end

function IntelliSense.hover(src: string, cursorPos: number): (string?, string?)
	local word = Analyzer.getWordAtCursor(src, cursorPos)
	if word == "" then return nil, nil end

	local chain = Analyzer.getMemberChain(src, cursorPos)
	if #chain >= 2 then
		local base   = chain[1]
		local member = chain[#chain]
		local entry  = Grammar.lookup(base)
		if entry and entry.members then
			local m = entry.members[member]
			if m then return member, m.detail end
		end
	end

	local entry = Grammar.lookup(word)
	if entry then return entry.label, entry.detail or entry.documentation end

	return nil, nil
end

return IntelliSense
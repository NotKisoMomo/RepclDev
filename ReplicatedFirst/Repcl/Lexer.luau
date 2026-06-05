local Grammar = require(script.Parent.Grammar)

local Lexer = {}

export type TokenKind =
	"keyword" | "identifier" | "number" | "string" | "operator" |
"punctuation" | "comment" | "whitespace" | "unknown" | "eof"

export type Token = {
	kind:   TokenKind,
	value:  string,
	start:  number,
	finish: number,
	line:   number,
	col:    number,
}

local KEYWORDS: { [string]: boolean } = {}
for _, entry in Grammar.Keywords do
	KEYWORDS[entry.label] = true
end
for _, entry in Grammar.Types do
	KEYWORDS[entry.label] = true
end

local function isDigit(c: string): boolean
	return c >= "0" and c <= "9"
end

local function isAlpha(c: string): boolean
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"
end

local function isAlNum(c: string): boolean
	return isAlpha(c) or isDigit(c)
end

local function isHex(c: string): boolean
	return isDigit(c) or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")
end

export type LexerState = {
	src:    string,
	len:    number,
	pos:    number,
	line:   number,
	col:    number,
	tokens: {Token},
}

local function makeState(src: string): LexerState
	return {
		src    = src,
		len    = #src,
		pos    = 1,
		line   = 1,
		col    = 1,
		tokens = {},
	}
end

local function peek(s: LexerState, offset: number?): string
	local i = s.pos + (offset or 0)
	if i > s.len then return "" end
	return string.sub(s.src, i, i)
end

local function peekStr(s: LexerState, n: number): string
	return string.sub(s.src, s.pos, s.pos + n - 1)
end

local function advance(s: LexerState): string
	local c = string.sub(s.src, s.pos, s.pos)
	s.pos += 1
	if c == "\n" then
		s.line += 1
		s.col = 1
	else
		s.col += 1
	end
	return c
end

local function push(s: LexerState, kind: TokenKind, value: string, startPos: number, startLine: number, startCol: number)
	table.insert(s.tokens, {
		kind   = kind,
		value  = value,
		start  = startPos,
		finish = s.pos - 1,
		line   = startLine,
		col    = startCol,
	})
end

local function skipLongString(s: LexerState): (string, boolean)
	local level = 0
	while peek(s) == "=" do
		level += 1
		advance(s)
	end
	if peek(s) ~= "[" then
		return "", false
	end
	advance(s)
	local buf = ""
	local closing = "]" .. string.rep("=", level) .. "]"
	while s.pos <= s.len do
		if peekStr(s, #closing) == closing then
			for _ = 1, #closing do advance(s) end
			return buf, true
		end
		buf ..= advance(s)
	end
	return buf, false
end

local function lexString(s: LexerState, quote: string): string
	local buf = quote
	while s.pos <= s.len do
		local c = advance(s)
		buf ..= c
		if c == "\\" then
			if s.pos <= s.len then
				buf ..= advance(s)
			end
		elseif c == quote then
			break
		end
	end
	return buf
end

local function lexNumber(s: LexerState): string
	local buf = ""
	if peek(s) == "0" and (peek(s, 1) == "x" or peek(s, 1) == "X") then
		buf ..= advance(s) .. advance(s)
		while isHex(peek(s)) or peek(s) == "_" do buf ..= advance(s) end
		return buf
	end
	if peek(s) == "0" and (peek(s, 1) == "b" or peek(s, 1) == "B") then
		buf ..= advance(s) .. advance(s)
		while peek(s) == "0" or peek(s) == "1" or peek(s) == "_" do buf ..= advance(s) end
		return buf
	end
	while isDigit(peek(s)) or peek(s) == "_" do buf ..= advance(s) end
	if peek(s) == "." and isDigit(peek(s, 1)) then
		buf ..= advance(s)
		while isDigit(peek(s)) or peek(s) == "_" do buf ..= advance(s) end
	end
	if peek(s) == "e" or peek(s) == "E" then
		buf ..= advance(s)
		if peek(s) == "+" or peek(s) == "-" then buf ..= advance(s) end
		while isDigit(peek(s)) do buf ..= advance(s) end
	end
	return buf
end

local OPERATORS: { [string]: boolean } = {
	["+"]  = true, ["-"]  = true, ["*"]  = true, ["/"]  = true,
	["%"]  = true, ["^"]  = true, ["#"]  = true, ["&"]  = true,
	["|"]  = true, ["~"]  = true, ["<"]  = true, [">"]  = true,
	["="]  = true, [".."] = true, ["..."]= true, ["//"] = true,
	["=="] = true, ["~="] = true, ["<="] = true, [">="] = true,
	["->"] = true, ["+="] = true, ["-="] = true, ["*="] = true,
	["/="] = true, ["%="] = true, ["//="]= true, ["..="]= true,
	["<<"] = true, [">>"] = true,
}

local PUNCTUATION: { [string]: boolean } = {
	["("] = true, [")"] = true, ["{"] = true, ["}"] = true,
	["["] = true, ["]"] = true, [","] = true, [";"] = true,
	[":"] = true, ["."] = true,
}

local function lexOp(s: LexerState): string
	local four = peekStr(s, 4)
	if OPERATORS[four] then
		for _ = 1, 4 do advance(s) end
		return four
	end
	local three = peekStr(s, 3)
	if OPERATORS[three] then
		for _ = 1, 3 do advance(s) end
		return three
	end
	local two = peekStr(s, 2)
	if OPERATORS[two] then
		advance(s) advance(s)
		return two
	end
	return advance(s)
end

function Lexer.tokenize(src: string): {Token}
	local s = makeState(src)

	while s.pos <= s.len do
		local startPos  = s.pos
		local startLine = s.line
		local startCol  = s.col
		local c = peek(s)

		if c == " " or c == "\t" or c == "\r" or c == "\n" then
			local ws = ""
			while s.pos <= s.len and (peek(s) == " " or peek(s) == "\t" or peek(s) == "\r" or peek(s) == "\n") do
				ws ..= advance(s)
			end
			push(s, "whitespace", ws, startPos, startLine, startCol)

		elseif c == "-" and peek(s, 1) == "-" then
			local buf = "--"
			advance(s) advance(s)
			if peek(s) == "[" then
				local savedPos = s.pos
				advance(s)
				local level = 0
				while peek(s) == "=" do level += 1 advance(s) end
				if peek(s) == "[" then
					advance(s)
					local content, _ = skipLongString(s)
					buf = "--[" .. string.rep("=", level) .. "[" .. content .. "]" .. string.rep("=", level) .. "]"
				else
					s.pos = savedPos
					while s.pos <= s.len and peek(s) ~= "\n" do buf ..= advance(s) end
				end
			else
				while s.pos <= s.len and peek(s) ~= "\n" do buf ..= advance(s) end
			end
			push(s, "comment", buf, startPos, startLine, startCol)

		elseif c == "[" and (peek(s, 1) == "[" or peek(s, 1) == "=") then
			local savedPos  = s.pos
			local savedLine = s.line
			local savedCol  = s.col
			advance(s)
			if peek(s) == "[" or peek(s) == "=" then
				local content, ok = skipLongString(s)
				if ok then
					push(s, "string", content, startPos, startLine, startCol)
				else
					s.pos  = savedPos
					s.line = savedLine
					s.col  = savedCol
					push(s, "punctuation", advance(s), startPos, startLine, startCol)
				end
			else
				s.pos  = savedPos
				s.line = savedLine
				s.col  = savedCol
				push(s, "punctuation", advance(s), startPos, startLine, startCol)
			end

		elseif c == '"' or c == "'" then
			advance(s)
			local str = lexString(s, c)
			push(s, "string", c .. str, startPos, startLine, startCol)

		elseif isDigit(c) or (c == "." and isDigit(peek(s, 1))) then
			local num = lexNumber(s)
			push(s, "number", num, startPos, startLine, startCol)

		elseif isAlpha(c) then
			local ident = ""
			while s.pos <= s.len and isAlNum(peek(s)) do ident ..= advance(s) end
			local kind: TokenKind = KEYWORDS[ident] and "keyword" or "identifier"
			push(s, kind, ident, startPos, startLine, startCol)

		elseif PUNCTUATION[c] then
			push(s, "punctuation", advance(s), startPos, startLine, startCol)

		else
			local op = lexOp(s)
			local kind: TokenKind = OPERATORS[op] and "operator" or "unknown"
			push(s, kind, op, startPos, startLine, startCol)
		end
	end

	table.insert(s.tokens, {
		kind   = "eof",
		value  = "",
		start  = s.pos,
		finish = s.pos,
		line   = s.line,
		col    = s.col,
	})

	return s.tokens
end

function Lexer.stripTrivia(tokens: {Token}): {Token}
	local out: {Token} = {}
	for _, tok in tokens do
		if tok.kind ~= "whitespace" and tok.kind ~= "comment" then
			table.insert(out, tok)
		end
	end
	return out
end

function Lexer.tokenAtPos(tokens: {Token}, cursorPos: number): (Token?, number)
	for i, tok in tokens do
		if tok.start <= cursorPos and tok.finish >= cursorPos then
			return tok, i
		end
	end
	local last = tokens[#tokens]
	return last, #tokens
end

function Lexer.lineTokens(tokens: {Token}, line: number): {Token}
	local out: {Token} = {}
	for _, tok in tokens do
		if tok.line == line then
			table.insert(out, tok)
		elseif tok.line > line then
			break
		end
	end
	return out
end

return Lexer
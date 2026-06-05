--!strict

local Shared = require(script.Parent.Shared)

local Types = {}

export type TypeDefModifiers = {
	nullable   : boolean?,
	default    : any?,
	unions     : { TypeDef }?,
	intersects : { TypeDef }?,
	nots       : { TypeDef }?,
	where      : ((value: any) -> boolean)?,
	literal    : any?,
	enum       : { any }?,
	min        : number?,
	max        : number?,
	step       : number?,
	minLength  : number?,
	maxLength  : number?,
	pattern    : string?,
	minSize    : number?,
	maxSize    : number?,
	tag        : string?,
	describe   : string?,
}

export type TypeDef = TypeDefModifiers & {
	_type      : string,
	_mask      : string?,
	_validate  : ((value: any) -> boolean)?,
	_fields    : { [string]: TypeDef }?,
	_element   : TypeDef?,
	_keyType   : TypeDef?,
	_valueType : TypeDef?,
	_items     : { TypeDef }?,
	_lazy      : (() -> TypeDef)?,
	_exact     : boolean?,

	or_        : (self: TypeDef, other: TypeDef) -> TypeDef,
	also       : (self: TypeDef, other: TypeDef) -> TypeDef,
	not_       : (self: TypeDef, other: TypeDef) -> TypeDef,
	nullable   : (self: TypeDef) -> TypeDef,
	default    : (self: TypeDef, value: any) -> TypeDef,
	where      : (self: TypeDef, fn: (value: any) -> boolean) -> TypeDef,
	literal    : (self: TypeDef, value: any) -> TypeDef,
	enum       : (self: TypeDef, values: { any }) -> TypeDef,
	min        : (self: TypeDef, n: number) -> TypeDef,
	max        : (self: TypeDef, n: number) -> TypeDef,
	bet        : (self: TypeDef, min: number, max: number) -> TypeDef,
	step       : (self: TypeDef, n: number) -> TypeDef,
	minLength  : (self: TypeDef, n: number) -> TypeDef,
	maxLength  : (self: TypeDef, n: number) -> TypeDef,
	pattern    : (self: TypeDef, str: string) -> TypeDef,
	minSize    : (self: TypeDef, n: number) -> TypeDef,
	maxSize    : (self: TypeDef, n: number) -> TypeDef,
	tag        : (self: TypeDef, str: string) -> TypeDef,
	describe   : (self: TypeDef, str: string) -> TypeDef,
}

export type ValidationError = {
	path    : string,
	message : string,
}

export type ValidationResult = {
	ok     : boolean,
	errors : { ValidationError },
}

export type CustomTypeConfig = {
	Mask     : TypeDef,
	Validate : (value: any) -> boolean,
}

local function makeTypeDef(typeName: string): TypeDef
	local self: TypeDef = {
		_type      = typeName,
		_mask      = nil,
		_validate  = nil,
		_fields    = nil,
		_element   = nil,
		_keyType   = nil,
		_valueType = nil,
		_items     = nil,
		_lazy      = nil,
		_exact     = nil,
		nullable   = nil :: any,
		default    = nil :: any,
		unions     = nil,
		intersects = nil,
		nots       = nil,
		where      = nil :: any,
		literal    = nil,
		enum       = nil,
		min        = nil :: any,
		max        = nil :: any,
		step       = nil :: any,
		minLength  = nil :: any,
		maxLength  = nil :: any,
		pattern    = nil :: any,
		minSize    = nil :: any,
		maxSize    = nil :: any,
		tag        = nil :: any,
		describe   = nil :: any,
	}

	function self:or_(other: TypeDef): TypeDef
		self.unions = self.unions or {}
		table.insert(self.unions :: { TypeDef }, other)
		return self
	end

	function self:also(other: TypeDef): TypeDef
		self.intersects = self.intersects or {}
		table.insert(self.intersects :: { TypeDef }, other)
		return self
	end

	function self:not_(other: TypeDef): TypeDef
		self.nots = self.nots or {}
		table.insert(self.nots :: { TypeDef }, other)
		return self
	end

	function self:nullable(): TypeDef
		self.nullable = true :: any
		return self
	end

	function self:default(value: any): TypeDef
		self.default = value :: any
		return self
	end

	function self:where(fn: (value: any) -> boolean): TypeDef
		self.where = fn :: any
		return self
	end

	function self:literal(value: any): TypeDef
		self.literal = value
		return self
	end

	function self:enum(values: { any }): TypeDef
		self.enum = values :: any
		return self
	end

	function self:min(n: number): TypeDef
		self.min = n :: any
		return self
	end

	function self:max(n: number): TypeDef
		self.max = n :: any
		return self
	end

	function self:bet(minVal: number, maxVal: number): TypeDef
		self.min = minVal :: any
		self.max = maxVal :: any
		return self
	end

	function self:step(n: number): TypeDef
		self.step = n :: any
		return self
	end

	function self:minLength(n: number): TypeDef
		self.minLength = n :: any
		return self
	end

	function self:maxLength(n: number): TypeDef
		self.maxLength = n :: any
		return self
	end

	function self:pattern(str: string): TypeDef
		self.pattern = str :: any
		return self
	end

	function self:minSize(n: number): TypeDef
		self.minSize = n :: any
		return self
	end

	function self:maxSize(n: number): TypeDef
		self.maxSize = n :: any
		return self
	end

	function self:tag(str: string): TypeDef
		self.tag = str :: any
		return self
	end

	function self:describe(str: string): TypeDef
		self.describe = str :: any
		return self
	end

	return self
end

local function validate(typeDef: TypeDef, value: any, path: string): { ValidationError }
	local errors: { ValidationError } = {}

	local function addError(msg: string)
		table.insert(errors, { path = path, message = msg })
	end

	if value == nil then
		if typeDef.nullable then
			return errors
		end
		if typeDef.default ~= nil then
			return errors
		end
		addError("expected value, got nil")
		return errors
	end

	local baseType = typeDef._type

	local typeChecks: { [string]: (any) -> boolean } = {
		string    = function(v) return type(v) == "string" end,
		number    = function(v) return type(v) == "number" end,
		float32   = function(v) return type(v) == "number" end,
		float64   = function(v) return type(v) == "number" end,
		uint8     = function(v) return type(v) == "number" and v >= 0 and v <= 255 and math.floor(v) == v end,
		uint16    = function(v) return type(v) == "number" and v >= 0 and v <= 65535 and math.floor(v) == v end,
		uint32    = function(v) return type(v) == "number" and v >= 0 and v <= 4294967295 and math.floor(v) == v end,
		int8      = function(v) return type(v) == "number" and v >= -128 and v <= 127 and math.floor(v) == v end,
		int16     = function(v) return type(v) == "number" and v >= -32768 and v <= 32767 and math.floor(v) == v end,
		int32     = function(v) return type(v) == "number" and v >= -2147483648 and v <= 2147483647 and math.floor(v) == v end,
		bool      = function(v) return type(v) == "boolean" end,
		buff      = function(v) return type(v) == "buffer" end,
		any       = function(_) return true end,
		never     = function(_) return false end,
		unknown   = function(_) return true end,
		nil_      = function(v) return v == nil end,
		Vector2   = function(v) return typeof(v) == "Vector2" end,
		Vector3   = function(v) return typeof(v) == "Vector3" end,
		vec2      = function(v) return typeof(v) == "Vector2" end,
		vec3      = function(v) return typeof(v) == "Vector3" end,
		vec2int16 = function(v) return typeof(v) == "Vector2int16" end,
		cframe    = function(v) return typeof(v) == "CFrame" end,
		color3    = function(v) return typeof(v) == "Color3" end,
		udim      = function(v) return typeof(v) == "UDim" end,
		udim2     = function(v) return typeof(v) == "UDim2" end,
		rect      = function(v) return typeof(v) == "Rect" end,
		region3   = function(v) return typeof(v) == "Region3" end,
		numberRange    = function(v) return typeof(v) == "NumberRange" end,
		numberSequence = function(v) return typeof(v) == "NumberSequence" end,
		colorSequence  = function(v) return typeof(v) == "ColorSequence" end,
		tweenInfo      = function(v) return typeof(v) == "TweenInfo" end,
		enumItem       = function(v) return typeof(v) == "EnumItem" end,
		inst           = function(v) return typeof(v) == "Instance" end,
	}

	if baseType == "struct" or baseType == "shape" then
		if type(value) ~= "table" then
			addError(string.format("expected table, got %s", type(value)))
			return errors
		end
		if baseType == "shape" then
			for k in value do
				if typeDef._fields and typeDef._fields[k] == nil then
					addError(string.format("unexpected field '%s'", k))
				end
			end
		end
		if typeDef._fields then
			for k, fieldDef in typeDef._fields do
				local fieldErrors = validate(fieldDef, value[k], path .. "." .. k)
				for _, e in fieldErrors do table.insert(errors, e) end
			end
		end
	elseif baseType == "array" then
		if type(value) ~= "table" then
			addError(string.format("expected array, got %s", type(value)))
			return errors
		end
		if typeDef._element then
			for i, item in value do
				local itemErrors = validate(typeDef._element, item, path .. "[" .. i .. "]")
				for _, e in itemErrors do table.insert(errors, e) end
			end
		end
		if typeDef.minSize and #value < (typeDef.minSize :: number) then
			addError(string.format("array length %d below minSize %d", #value, typeDef.minSize :: number))
		end
		if typeDef.maxSize and #value > (typeDef.maxSize :: number) then
			addError(string.format("array length %d above maxSize %d", #value, typeDef.maxSize :: number))
		end
	elseif baseType == "map" then
		if type(value) ~= "table" then
			addError(string.format("expected map, got %s", type(value)))
			return errors
		end
		for k, v in value :: { [any]: any } do
			if typeDef._keyType then
				local kErrors = validate(typeDef._keyType, k, path .. ".key")
				for _, e in kErrors do table.insert(errors, e) end
			end
			if typeDef._valueType then
				local vErrors = validate(typeDef._valueType, v, path .. "[" .. tostring(k) .. "]")
				for _, e in vErrors do table.insert(errors, e) end
			end
		end
	elseif baseType == "record" then
		if type(value) ~= "table" then
			addError(string.format("expected record, got %s", type(value)))
			return errors
		end
		if typeDef._valueType then
			for k, v in value :: { [any]: any } do
				if type(k) ~= "string" then
					addError(string.format("record key must be string, got %s", type(k)))
				end
				local vErrors = validate(typeDef._valueType, v, path .. "." .. tostring(k))
				for _, e in vErrors do table.insert(errors, e) end
			end
		end
	elseif baseType == "tuple" then
		if type(value) ~= "table" then
			addError(string.format("expected tuple, got %s", type(value)))
			return errors
		end
		if typeDef._items then
			for i, itemDef in typeDef._items do
				local itemErrors = validate(itemDef, value[i], path .. "[" .. i .. "]")
				for _, e in itemErrors do table.insert(errors, e) end
			end
		end
	elseif baseType == "lazy" then
		if typeDef._lazy then
			local resolved = typeDef._lazy()
			local lazyErrors = validate(resolved, value, path)
			for _, e in lazyErrors do table.insert(errors, e) end
		end
	elseif baseType == "custom" then
		if typeDef._validate and not typeDef._validate(value) then
			addError(typeDef.describe :: string or "custom type validation failed")
		end
	elseif baseType == "inst" then
		if typeof(value) ~= "Instance" then
			addError(string.format("expected Instance, got %s", typeof(value)))
		elseif typeDef._mask and not value:IsA(typeDef._mask) then
			addError(string.format("expected Instance of class %s", typeDef._mask))
		end
	else
		local check = typeChecks[baseType]
		if check then
			if not check(value) then
				addError(string.format("expected %s, got %s", baseType, typeof(value)))
			end
		end
	end

	if typeDef.unions then
		local anyPassed = false
		for _, unionDef in typeDef.unions :: { TypeDef } do
			local unionErrors = validate(unionDef, value, path)
			if #unionErrors == 0 then
				anyPassed = true
				break
			end
		end
		if not anyPassed then
			addError("value does not satisfy any union type")
		end
	end

	if typeDef.intersects then
		for _, intersectDef in typeDef.intersects :: { TypeDef } do
			local intersectErrors = validate(intersectDef, value, path)
			for _, e in intersectErrors do table.insert(errors, e) end
		end
	end

	if typeDef.nots then
		for _, notDef in typeDef.nots :: { TypeDef } do
			local notErrors = validate(notDef, value, path)
			if #notErrors == 0 then
				addError("value must not satisfy negated type")
			end
		end
	end

	if typeDef.literal ~= nil and value ~= typeDef.literal then
		addError(string.format("expected literal %s, got %s", tostring(typeDef.literal), tostring(value)))
	end

	if typeDef.enum then
		local found = false
		for _, enumVal in typeDef.enum :: { any } do
			if value == enumVal then found = true break end
		end
		if not found then
			addError(string.format("value not in enum"))
		end
	end

	if type(value) == "number" then
		if typeDef.min ~= nil and value < (typeDef.min :: number) then
			addError(string.format("value %d below min %d", value, typeDef.min :: number))
		end
		if typeDef.max ~= nil and value > (typeDef.max :: number) then
			addError(string.format("value %d above max %d", value, typeDef.max :: number))
		end
		if typeDef.step ~= nil and value % (typeDef.step :: number) ~= 0 then
			addError(string.format("value %d not a multiple of step %d", value, typeDef.step :: number))
		end
	end

	if type(value) == "string" then
		if typeDef.minLength ~= nil and #value < (typeDef.minLength :: number) then
			addError(string.format("string length %d below minLength %d", #value, typeDef.minLength :: number))
		end
		if typeDef.maxLength ~= nil and #value > (typeDef.maxLength :: number) then
			addError(string.format("string length %d above maxLength %d", #value, typeDef.maxLength :: number))
		end
		if typeDef.pattern ~= nil and not string.match(value, typeDef.pattern :: string) then
			addError(string.format("string does not match pattern '%s'", typeDef.pattern :: string))
		end
	end

	if typeDef.where ~= nil and not (typeDef.where :: (any) -> boolean)(value) then
		addError(typeDef.describe :: string or "custom predicate failed")
	end

	return errors
end

local function validateParse(typeDef: TypeDef, value: any): (boolean, string?)
	if value == nil and typeDef.nullable then
		return true, nil
	end
	if value == nil and typeDef.default ~= nil then
		return true, nil
	end
	local errors = validate(typeDef, value, "root")
	if #errors == 0 then
		return true, nil
	end
	local messages: { string } = {}
	for _, e in errors do
		table.insert(messages, string.format("[%s] %s", e.path, e.message))
	end
	return false, table.concat(messages, "; ")
end

local function applyDefaults(typeDef: TypeDef, value: any): any
	if value == nil and typeDef.default ~= nil then
		return typeDef.default
	end
	if type(value) == "table" and typeDef._fields then
		local result = table.clone(value)
		for k, fieldDef in typeDef._fields do
			result[k] = applyDefaults(fieldDef, result[k])
		end
		return result
	end
	return value
end

Types.validate      = validateParse
Types.applyDefaults = applyDefaults
Types.makeTypeDef   = makeTypeDef

Types.string    = function(): TypeDef return makeTypeDef("string")    end
Types.number    = function(): TypeDef return makeTypeDef("number")    end
Types.float32   = function(): TypeDef return makeTypeDef("float32")   end
Types.float64   = function(): TypeDef return makeTypeDef("float64")   end
Types.uint8     = function(): TypeDef return makeTypeDef("uint8")     end
Types.uint16    = function(): TypeDef return makeTypeDef("uint16")    end
Types.uint32    = function(): TypeDef return makeTypeDef("uint32")    end
Types.int8      = function(): TypeDef return makeTypeDef("int8")      end
Types.int16     = function(): TypeDef return makeTypeDef("int16")     end
Types.int32     = function(): TypeDef return makeTypeDef("int32")     end
Types.bool      = function(): TypeDef return makeTypeDef("bool")      end
Types.buff      = function(): TypeDef return makeTypeDef("buff")      end
Types.any       = function(): TypeDef return makeTypeDef("any")       end
Types.never     = function(): TypeDef return makeTypeDef("never")     end
Types.unknown   = function(): TypeDef return makeTypeDef("unknown")   end
Types.nil_      = function(): TypeDef return makeTypeDef("nil_")      end
Types.vec2      = function(): TypeDef return makeTypeDef("vec2")      end
Types.vec3      = function(): TypeDef return makeTypeDef("vec3")      end
Types.vec2int16 = function(): TypeDef return makeTypeDef("vec2int16") end
Types.cframe    = function(): TypeDef return makeTypeDef("cframe")    end
Types.color3    = function(): TypeDef return makeTypeDef("color3")    end
Types.udim      = function(): TypeDef return makeTypeDef("udim")      end
Types.udim2     = function(): TypeDef return makeTypeDef("udim2")     end
Types.rect      = function(): TypeDef return makeTypeDef("rect")      end
Types.region3   = function(): TypeDef return makeTypeDef("region3")   end

Types.numberRange    = function(): TypeDef return makeTypeDef("numberRange")    end
Types.numberSequence = function(): TypeDef return makeTypeDef("numberSequence") end
Types.colorSequence  = function(): TypeDef return makeTypeDef("colorSequence")  end
Types.tweenInfo      = function(): TypeDef return makeTypeDef("tweenInfo")      end
Types.enumItem       = function(): TypeDef return makeTypeDef("enumItem")       end

Types.inst = function(className: string?): TypeDef
	local t = makeTypeDef("inst")
	t._mask = className
	return t
end

Types.struct = function(fields: { [string]: TypeDef }): TypeDef
	Shared.expect(fields, "fields", "table")
	local t = makeTypeDef("struct")
	t._fields = fields
	return t
end

Types.shape = function(fields: { [string]: TypeDef }): TypeDef
	Shared.expect(fields, "fields", "table")
	local t = makeTypeDef("shape")
	t._fields = fields
	t._exact  = true
	return t
end

Types.array = function(element: TypeDef): TypeDef
	Shared.expectNotNil(element, "element")
	local t = makeTypeDef("array")
	t._element = element
	return t
end

Types.map = function(keyType: TypeDef, valueType: TypeDef): TypeDef
	Shared.expectNotNil(keyType, "keyType")
	Shared.expectNotNil(valueType, "valueType")
	local t = makeTypeDef("map")
	t._keyType   = keyType
	t._valueType = valueType
	return t
end

Types.record = function(valueType: TypeDef): TypeDef
	Shared.expectNotNil(valueType, "valueType")
	local t = makeTypeDef("record")
	t._valueType = valueType
	return t
end

Types.tuple = function(...: TypeDef): TypeDef
	local items: { TypeDef } = { ... }
	local t = makeTypeDef("tuple")
	t._items = items
	return t
end

Types.lazy = function(fn: () -> TypeDef): TypeDef
	Shared.expect(fn, "fn", "function")
	local t = makeTypeDef("lazy")
	t._lazy = fn
	return t
end

Types.partial = function(structDef: TypeDef): TypeDef
	assert(structDef._type == "struct" or structDef._type == "shape", "[Mandy] partial requires a struct or shape TypeDef")
	local fields: { [string]: TypeDef } = {}
	if structDef._fields then
		for k, v in structDef._fields do
			local copy = Shared.deepCopy(v)
			copy.nullable = true :: any
			fields[k]     = copy
		end
	end
	return Types.struct(fields)
end

Types.pick = function(structDef: TypeDef, keys: { string }): TypeDef
	assert(structDef._type == "struct" or structDef._type == "shape", "[Mandy] pick requires a struct or shape TypeDef")
	local fields: { [string]: TypeDef } = {}
	if structDef._fields then
		for _, k in keys do
			if structDef._fields[k] then
				fields[k] = structDef._fields[k]
			end
		end
	end
	return Types.struct(fields)
end

Types.omit = function(structDef: TypeDef, keys: { string }): TypeDef
	assert(structDef._type == "struct" or structDef._type == "shape", "[Mandy] omit requires a struct or shape TypeDef")
	local fields: { [string]: TypeDef } = {}
	if structDef._fields then
		for k, v in structDef._fields do
			if not Shared.includes(keys, k) then
				fields[k] = v
			end
		end
	end
	return Types.struct(fields)
end

Types.merge = function(a: TypeDef, b: TypeDef): TypeDef
	assert(
		(a._type == "struct" or a._type == "shape") and (b._type == "struct" or b._type == "shape"),
		"[Mandy] merge requires two struct or shape TypeDefs"
	)
	local fields: { [string]: TypeDef } = {}
	if a._fields then for k, v in a._fields do fields[k] = v end end
	if b._fields then for k, v in b._fields do fields[k] = v end end
	return Types.struct(fields)
end

Types.defineType = function(config: CustomTypeConfig): () -> TypeDef
	Shared.expectNotNil(config, "config")
	Shared.expectNotNil(config.Mask, "config.Mask")
	Shared.expect(config.Validate, "config.Validate", "function")

	return function(): TypeDef
		local t = makeTypeDef("custom")
		t._mask     = config.Mask._type
		t._validate = config.Validate
		return t
	end
end

Types.none = {} :: any

return Types
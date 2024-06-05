local codegen = require "codegen"
local idl = codegen.idl "bgfx.idl"

local beef_template = [[

{
	"typedefs": {
		"ViewId": "uint16"
	},
	"types": [
		$types
	],
	"functions": [
		$funcs
	]
}
]]

local substructs = {}

local function isempty(s)
	return s == nil or s == ''
end

local function hasPrefix(str, prefix)
	return prefix == "" or str:sub(1, #prefix) == prefix
end

local function hasSuffix(str, suffix)
	return suffix == "" or str:sub(-#suffix) == suffix
end

local function convert_type_0(arg)

	-- if hasPrefix(arg.ctype, "uint64_t") then
	-- 	return arg.ctype:gsub("uint64_t", "uint64")
	-- elseif hasPrefix(arg.ctype, "int64_t") then
	-- 	return arg.ctype:gsub("int64_t", "int64")
	-- elseif hasPrefix(arg.ctype, "uint32_t") then
	-- 	return arg.ctype:gsub("uint32_t", "uint32")
	-- elseif hasPrefix(arg.ctype, "int32_t") then
	-- 	return arg.ctype:gsub("int32_t", "int")
	-- elseif hasPrefix(arg.ctype, "uint16_t") then
	-- 	return arg.ctype:gsub("uint16_t", "uint16")
	-- elseif hasPrefix(arg.ctype, "uint8_t") then
	-- 	return arg.ctype:gsub("uint8_t", "uint8")
	-- elseif hasPrefix(arg.ctype, "uintptr_t") then
	-- 	return arg.ctype:gsub("uintptr_t", "void*")
	-- elseif arg.ctype == "const char*" then
	-- 	return "char8*"
	-- elseif hasPrefix(arg.ctype, "char") then
	-- 	return arg.ctype:gsub("char", "char8")
	-- elseif hasPrefix(arg.ctype, "byte") then
	-- 	return arg.ctype:gsub("byte", "uint8")
	-- elseif arg.ctype == "va_list"
	-- 	or arg.fulltype == "bx::AllocatorI*"
	-- 	or arg.fulltype == "CallbackI*"
	-- 	or arg.fulltype == "ReleaseFn" then
	-- 	return "void*"
	-- end

	return arg.fulltype
end

local function convert_type(arg)
	local ctype = convert_type_0(arg)
	-- ctype = ctype:gsub("::Enum", "")
	-- ctype = ctype:gsub("const ", "")
	-- ctype = ctype:gsub(" &", "*")
	-- ctype = ctype:gsub("&", "*")
	
	if substructs[arg.type] ~= nil then
		ctype = substructs[arg.type]
	end

	return ctype
end

local function convert_struct_type(arg)
	local ctype = convert_type(arg)
	-- if hasPrefix(arg.ctype, "bool") then
	-- 	ctype = ctype:gsub("bool", "uint8")
	-- end
	return ctype
end

local function convert_ret_type(arg)
	local ctype = convert_type(arg)
	return ctype
end

local converter = {}
local yield = coroutine.yield
local indent = ""

local gen = {}

function gen.gen()
	local r = beef_template:gsub("$(%l+)", function(what)
		local tmp = {}
		for _, object in ipairs(idl[what]) do
			local co = coroutine.create(converter[what])
			local any
			while true do
				local ok, v = coroutine.resume(co, object)
				assert(ok, debug.traceback(co, v))
				if not v then
					break
				end
				table.insert(tmp, v)
				any = true
			end
			if any and tmp[#tmp] ~= "" then
				table.insert(tmp, "")
			end
		end
		return table.concat(tmp, "\n\t")
	end)
	return r
end

local combined = { "State", "Stencil", "Buffer", "Texture", "Sampler", "Reset" }

for _, v in ipairs(combined) do
	combined[v] = {}
end

local lastCombinedFlag

local function FlagBlock(typ)
	local format = "0x%08x"
	local enumType = "uint32"
	if typ.bits == 64 then
		format = "0x%016x"
		enumType = "uint64"
	elseif typ.bits == 16 then
		format = "0x%04x"
		enumType = "uint16"
	end

    -- yield("[AllowDuplicates]")
    yield("{")
	yield('"name": "' .. typ.name .. 'Flags",')
	yield('"type": "bits",') 
	yield('"data_type": "' .. enumType .. '",')
	
	yield('"values": [')
	for idx, flag in ipairs(typ.flag) do

		yield("{")
		if flag.comment ~= nil then
			-- yield("\t/// <summary>")
			local com = ""
			for cdx, comment in ipairs(flag.comment) do
				com = com .. comment
				if cdx ~= #flag.comment then
					com = com .. "\\n"
				end
			end
			-- yield("\t/// </summary>")
			yield('"comment": "' .. com .. '",')
		end

		local flagName = flag.name:gsub("_", "")

		yield('"name" : "' .. flagName .. '",')
		yield('"value": "' .. string.format(flag.format or format, flag.value) .. '"')
		yield("}")

		if idx ~= #typ.flag then
			yield(",")
		end
	end
	

	if typ.shift then
		yield("\t"
			.. "Shift"
			.. string.rep(" ", 22 - #("Shift"))
			.. " = "
			.. flag.shift
			)
	end

	-- generate Mask
	if typ.mask then
		yield("\t"
			.. "Mask"
			.. string.rep(" ", 22 - #("Mask"))
			.. " = "
			.. string.format(format, flag.mask)
			)
	end
	yield("]")

	yield("},")
end

local function lastCombinedFlagBlock()
	if lastCombinedFlag then
		local typ = combined[lastCombinedFlag]
		if typ then
			FlagBlock(combined[lastCombinedFlag])
			yield("")
		end
		lastCombinedFlag = nil
	end
end

local enum = {}

local function convert_array(member)
	if string.find(member.array, "::") then
		return string.format("[%d]", enum[member.array])
	else
		return member.array
	end
end

local function convert_struct_member(member)
	if member.array then
		return convert_struct_type(member) .. convert_array(member)
	else
		return convert_struct_type(member)
	end
end

local namespace = ""

function converter.types(typ)
	if typ.handle then
		lastCombinedFlagBlock()
		-- yield("[CRepr]")
		-- yield("public struct " .. typ.name .. " {")
        -- yield("    public uint16 idx;")
        -- yield("    public bool Valid => idx != uint16.MaxValue;")
        -- yield("}")

        yield('{')
        yield('"name": "'.. typ.name .. '",')
        yield('"cname": "'.. typ.cname .. '",')
        yield('"type": "handle",')
        yield('"members": [')
        yield('{"name": "idx", "data_type": "uint16"}')
        yield(']')
        yield('},')

	elseif hasSuffix(typ.name, "::Enum") then
		lastCombinedFlagBlock()
      	
		yield("{")

		yield('"name": "' .. typ.typename .. '",')
		yield('"type": "enum",')
		yield('"cname": "' .. typ.cname .. '",')
		yield('"data_type": "uint32",')

		yield('"values": [')
		for idx, enum in ipairs(typ.enum) do

			yield("{")
			if enum.comment ~= nil then
				local com = ""
				for cdx, comment in ipairs(enum.comment) do
					com = com .. comment
					if cdx ~= #enum.comment then
						com = com .. "\\n"
					end
				end
				yield('"comment": "' .. com .. '",')
			end
			yield('"native": "BGFX_' .. typ.cname:gsub("bgfx_(.*)_t", typ.cname.upper) .. '_' .. enum.name:upper() .. '",')
			yield('"name" : "' .. enum.name .. '"')
			yield("},")

			-- if idx ~= #typ.enum then
			-- 	yield(",")
			-- end

		end

		yield("{")
		yield('"native": "'.. typ.cname .. "::" .. 'BGFX_' .. typ.cname:gsub("bgfx_(.*)_t", typ.cname.upper) .. '_COUNT",')
		yield('"name" : "Count"')
		yield("}")

		yield("]")
		yield("},")

		enum["[" .. typ.typename .. "::Count]"] = #typ.enum

	elseif typ.bits ~= nil then
		local prefix, name = typ.name:match "(%u%l+)(.*)"
		if prefix ~= lastCombinedFlag then
			lastCombinedFlagBlock()
			lastCombinedFlag = prefix
		end
		local combinedFlag = combined[prefix]
		if combinedFlag then
			combinedFlag.bits = typ.bits
			combinedFlag.name = prefix
			local flags = combinedFlag.flag or {}
			combinedFlag.flag = flags
			local lookup = combinedFlag.lookup or {}
			combinedFlag.lookup = lookup
			for _, flag in ipairs(typ.flag) do
				local flagName = name .. flag.name:gsub("_", "")
				local value = flag.value
				if value == nil then
					-- It's a combined flag
					value = 0
					for _, v in ipairs(flag) do
						value = value | assert(lookup[name .. v], v .. " is not defined for " .. flagName)
					end
				end
				lookup[flagName] = value
				table.insert(flags, {
					name = flagName,
					value = value,
					comment = flag.comment,
				})
			end

			if typ.shift then
				table.insert(flags, {
					name = name .. "Shift",
					value = typ.shift,
					format = "%d",
					comment = typ.comment,
				})
			end

			if typ.mask then
				-- generate Mask
				table.insert(flags, {
					name = name .. "Mask",
					value = typ.mask,
					comment = typ.comment,
				})
				lookup[name .. "Mask"] = typ.mask
			end
		else
			FlagBlock(typ)
		end
	elseif typ.struct ~= nil then


		yield('{')

        local skip = false
        local curName = typ.name

		if typ.namespace ~= nil then
			if namespace ~= typ.namespace then
				curName = typ.namespace .. typ.name
				substructs[typ.name] = curName
			end
		elseif namespace ~= "" then
			namespace = ""
			skip = true
		end

		if not skip then
			yield('"name": "'.. curName .. '",')
			yield('"cname": "' .. typ.cname .. '",')
        	yield('"type": "struct",')
		end

		yield('"members": [')
		for mdx, member in ipairs(typ.struct) do
			-- yield(
			-- 	indent .. "\tpublic " .. convert_struct_member(member) .. ";"
			-- 	)
			yield('{')
			yield('"name": "' .. member.name .. '",')
			yield('"data_type": "' .. convert_struct_member(member) .. '"')
			

			yield('}')
			if mdx ~= #typ.struct then
				yield(",")
			end
		end
		yield(']')

		yield('},')
	end
end

function converter.funcs(func)

	-- if func.cpponly then
	-- 	return
	-- elseif func.cppinline and not func.conly then
	-- 	return
	-- end

	-- if func.comments ~= nil then
	-- 	yield("/// <summary>")
	-- 	for _, line in ipairs(func.comments) do
	-- 		yield("/// " .. line)
	-- 	end
	-- 	yield("/// </summary>")
	-- 	yield("///")

	-- 	local hasParams = false

	-- 	for _, arg in ipairs(func.args) do
	-- 		if arg.comment ~= nil then
	-- 			local comment = table.concat(arg.comment, " ")

	-- 			yield("/// <param name=\""
	-- 				.. arg.name
	-- 				.. "\">"
	-- 				.. comment
	-- 				.. "</param>"
	-- 				)

	-- 			hasParams = true
	-- 		end
	-- 	end

	-- 	if hasParams then
	-- 		yield("///")
	-- 	end
	-- end

	-- yield("[LinkName(\"bgfx_" .. func.cname .. "\")]")

	-- local args = {}
	-- if func.this ~= nil then
	-- 	args[1] = func.this_type.type .. "* _this"
	-- end
	-- for _, arg in ipairs(func.args) do
	-- 	table.insert(args, convert_type(arg) .. " " .. arg.name)
	-- end
	-- yield("public static extern " .. convert_ret_type(func.ret) .. " " .. func.cname
	-- 	.. "(" .. table.concat(args, ", ") .. ");")



	yield('{')
	yield('"name": "' .. func.cname:gsub("_(.)", func.cname.upper) .. '",')	
	yield('"cname": "bgfx_' .. func.cname .. '",')
	yield('"return_type": "' .. convert_ret_type(func.ret) .. '",')

	if func.comments ~= nil then
		local com = ""
		for cdx, comment in ipairs(func.comments) do
			com = com .. comment:gsub('"', '\\"')
			if cdx ~= #func.comments then
				com = com .. "\\n"
			end
		end
		yield('"comment": "' .. com .. '",')
	end

	local args = {}
	local argNames = {}

	yield('"arguments": [')
	if func.this ~= nil then
		args[1] = {
			name= "_this",
			fulltype= func.this_type.type .. "*"
		}
	end
	for adx, arg in ipairs(func.args) do
		local argName = arg.name
		table.insert(args, arg)
	end

	for adx, arg in ipairs(args) do
		yield('{')
			if arg.comment ~= nil then
				local com = ""
				for cdx, comment in ipairs(arg.comment) do

					com = com .. comment:gsub('"', '\\\\"')
					if cdx ~= #arg.comment then
						com = com .. "\\n"
					end
				end
				yield('"comment": "' .. com .. '",')
			end
			yield('"cname": "' .. arg.name .. '",')
			yield('"data_type": "' .. convert_type(arg) .. '"')
		yield('}')
		if adx ~= #args then
			yield(",")
		end
	end


	yield(']')
	yield('},')
end

-- printtable("idl types", idl.types)
-- printtable("idl funcs", idl.funcs)

function gen.write(codes, outputfile)
	local out = assert(io.open(outputfile, "wb"))
	out:write(codes)
	out:close()
	print("Generating: " .. outputfile)
end

if (...) == nil then
	-- run `lua bindings-bf.lua` in command line
	print(gen.gen())
end

return gen

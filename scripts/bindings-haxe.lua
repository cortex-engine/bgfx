local codegen = require "codegen"
local idl = codegen.idl "bgfx.idl"

local print_comments = false

local haxe_template = [[
/*
 * Copyright 2011-2024 Branimir Karadzic, Michael Bickel. All rights reserved.
 * License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
 */

/*
 *
 * AUTO GENERATED! DO NOT EDIT!
 *
 */

package bgfx;

typedef Native_ViewId = cpp.UInt16;
typedef ViewId = Native_ViewId;

$types

@:headerCode('#include <Dynamic2.h>')
@:include("linc_bgfx.h")
@:build(linc.Linc.touch())
@:build(linc.Linc.xml("bgfx"))
extern class Native_Bgfx {
	@:include("linc_bgfx.h")
	@:native('linc_bgfx::getBgfxCallback')
	extern public static function getCallback():cpp.Star<cpp.Void>;

$funcs
}

// #if (scriptable || cppia)
//    @:build(linc.LincCppia.wrapMainExtern('Native_Bgfx'))
//    class Bgfx {} 
//    typedef BgfxCpp = Native_Bgfx; // allow explicit cpp use in scriptable host
// #else
    typedef Bgfx = Native_Bgfx;
    typedef BgfxCpp = Native_Bgfx;
// #end

]]

local function isempty(s)
	return s == nil or s == ''
end

local function hasPrefix(str, prefix)
	return prefix == "" or str:sub(1, #prefix) == prefix
end

local function hasSuffix(str, suffix)
	return suffix == "" or str:sub(- #suffix) == suffix
end

local enum = {}

local function convert_array(member, type)
	if string.find(member.array, "::") then
		-- return string.format("[%d]", enum[member.array])
		return 'Array<'.. type .. '>; // ' .. string.format("[%d]", enum[member.array])
	else
		-- return member.array
		return ''
	end
end

local function gisub(s, pat, repl, n)
	pat = string.gsub(pat, '(%a)', function(v)
		return '[' .. string.upper(v) .. string.lower(v) .. ']'
	end)
	if n then
		return string.gsub(s, pat, repl, n)
	else
		return string.gsub(s, pat, repl)
	end
end

local function convert_type_0(arg)

	if hasPrefix(arg.ctype, "bool") then
		return arg.ctype:gsub("bool", "Bool")
	elseif hasPrefix(arg.ctype, "uint64_t") then
		return arg.ctype:gsub("uint64_t", "cpp.UInt64")
	elseif hasPrefix(arg.ctype, "int64_t") then
		return arg.ctype:gsub("int64_t", "cpp.Int64")
	elseif hasPrefix(arg.ctype, "uint32_t") then
		return arg.ctype:gsub("uint32_t", "cpp.UInt32")
	elseif hasPrefix(arg.ctype, "int32_t") then
		return arg.ctype:gsub("int32_t", "cpp.Int32")
	elseif hasPrefix(arg.ctype, "uint16_t") then
		return arg.ctype:gsub("uint16_t", "cpp.UInt16")
	elseif hasPrefix(arg.ctype, "uint8_t") then
		return arg.ctype:gsub("uint8_t", "cpp.UInt8")
	elseif hasPrefix(arg.ctype, "uintptr_t") then
		return arg.ctype:gsub("uintptr_t", "cpp.Star<cpp.Void>")
	elseif arg.ctype == "const char*" then
		return "cpp.ConstCharStar"
	elseif hasPrefix(arg.ctype, "char") then
		return arg.ctype:gsub("char", "cpp.Char")
	elseif hasPrefix(arg.ctype, "byte") then
		return arg.ctype:gsub("byte", "cpp.UInt8")
	elseif arg.ctype == "va_list"
		or arg.fulltype == "bx::AllocatorI*"
		or arg.fulltype == "CallbackI*"
		or arg.fulltype == "ReleaseFn" then
		return "cpp.Star<cpp.Void>"
	end

	return arg.fulltype
end

local substructs = {}

local function convert_type(arg)
	local ctype = convert_type_0(arg)
	has_const = hasPrefix(ctype, "const")
	ctype = ctype:gsub("void", "cpp.Void")
	ctype = ctype:gsub("::Enum", "")
	ctype = ctype:gsub(" &", "*")
	ctype = ctype:gsub("&", "*")
	ctype = ctype:gsub("const char%*", "cpp.ConstCharStar")
	ctype = ctype:gsub("const ", "")
	ctype = ctype:gsub("char", "cpp.Char")
	ctype = ctype:gsub("float", "cpp.Float32")
	ctype = ctype:gsub("const void%*", "cpp.Star<cpp.Void>")
	ctype = ctype:gsub("Encoder%*", "cpp.Star<Encoder>")

	if hasSuffix(ctype, "Handle") then
		ctype = 'Native_'..ctype
	elseif hasSuffix(ctype, "void*") then
		ctype = ctype:gsub("void%*", "cpp.Star<cpp.Void>");
	elseif hasSuffix(ctype, "*") then
		if (hasPrefix(ctype, "cpp") or hasPrefix(ctype, "Bool")) then
			ctype = "cpp.Star<" .. ctype:gsub("*", "") .. ">"
		elseif has_const then
			ctype = "cpp.ConstStar<Native_" .. ctype:gsub("*", "") .. ">"
		else
			ctype = "cpp.Star<Native_" .. ctype:gsub("*", "") .. ">"
		end
	end

	if arg.array ~= nil then
		ctype = ctype:gsub("const ", "")
		ctype = convert_array(arg, ctype) .. ctype
	end

	if substructs[arg.type] ~= nil then
		ctype = substructs[arg.type]
	end

	return ctype
end

local function convert_struct_type(arg)
	local ctype = convert_type(arg)
	if hasPrefix(ctype, "Void") == false and 
		hasPrefix(ctype, "Bool") == false and 
		hasPrefix(ctype, "Array") == false and
		hasPrefix(ctype, "cpp") == false and 
		hasPrefix(ctype, "Native_") == false then
		ctype = 'Native_'..ctype
	end
	return ctype
end

local function convert_ret_type(arg)
	return convert_type(arg)
end

local function wrap_simple_func(func, args, argNames)
	local hxFunc = {}
	-- local hxFuncTemplate = [[inline public static function $func($params):$ret { return $cfunc($args); }]]
	local hxFuncTemplate = [[@:native("$cfunc") extern public static function $func($params):$ret;]]

	-- transform name to camelCase from snake_case
	hxFunc.func = func.cname:gsub("_(.)", func.cname.upper)
	-- make 2d/3d upper case 2D/3D
	hxFunc.func = hxFunc.func:gsub("%dd", hxFunc.func.upper);
	hxFunc.params = table.concat(args, ", ")
	hxFunc.ret = convert_ret_type(func.ret)
	hxFunc.cfunc = "bgfx_" .. func.cname
	hxFunc.args = table.concat(argNames, ", ")
	return hxFuncTemplate:gsub("$(%l+)", hxFunc)
end

local function wrap_method(func, type, args, argNames, indent)
	local hxFunc = {}
	local hxFuncTemplate = [[%sinline public function $func($params):$ret {
    %sreturn Bgfx.$cfunc($args);
%s}]]

	hxFuncTemplate = string.format(hxFuncTemplate, indent, indent, indent);

	-- transform name to camelCase from snake_case
	hxFunc.func = func.cname:gsub("_(.)", func.cname.upper)
	-- remove type from name
	hxFunc.func = gisub(hxFunc.func, type, "");
	-- make first letter lowercase
	hxFunc.func = hxFunc.func:gsub("^%L", string.lower)
	-- make 2d/3d upper case 2D/3D
	hxFunc.func = hxFunc.func:gsub("%dd", hxFunc.func.upper);
	if argNames[1] == 'this' then
		local first = table.remove(args, 1)
		hxFunc.params = table.concat(args, ", ")
		table.insert(args, 1, first)
	else
		hxFunc.params = table.concat(args, ", ")
		-- hxFunc.params = table.remove(argNames, 1)
	end
	hxFunc.ret = convert_ret_type(func.ret)
	-- remove C API Star [*c] for fluent interfaces
	if hxFunc.ret == ("[*c]" .. type) then
		hxFunc.ret = hxFunc.ret:gsub("%[%*c%]", "*")
	end
	hxFunc.cfunc = "bgfx_" .. func.cname
	hxFunc.args = table.concat(argNames, ", ")
	return hxFuncTemplate:gsub("$(%l+)", hxFunc)
end

local converter = {}
local yield = coroutine.yield
local gen = {}

local indent = ""

function gen.gen()
	-- find the functions that have `this` first argument
	-- these belong to a type (struct) and we need to add them when converting structures
	local methods = {}
	for _, func in ipairs(idl["funcs"]) do
		if func.this ~= nil then
			if methods[func.this_type.type] == nil then
				methods[func.this_type.type] = {}
			end
			table.insert(methods[func.this_type.type], func)
		end
	end

	local r = haxe_template:gsub("$(%l+)", function(what)
		local tmp = {}
		for _, object in ipairs(idl[what]) do
			local co = coroutine.create(converter[what])
			local any
			-- we're pretty confident there are no types that have the same name with a func
			local funcs = methods[object.name]
			while true do
				local ok, v = coroutine.resume(co, {
					obj = object,
					funcs = funcs
				})
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
		return table.concat(tmp, "\n")
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
	local enumType = " : Int"
	if typ.bits == 64 then
		format = "0x%016x"
		enumType = " : cpp.Int64"
	elseif typ.bits == 16 then
		format = "0x%04x"
		enumType = " : cpp.Int16"
	end

	yield("class " .. typ.name .. "Flags")-- .. enumType)
	yield("{")

	for idx, flag in ipairs(typ.flag) do

		if print_comments == true then
			if flag.comment ~= nil then
				if idx ~= 1 then
					yield("")
				end

				yield("\t/// <summary>")
				for _, comment in ipairs(flag.comment) do
					yield("\t/// " .. comment)
				end
				yield("\t/// </summary>")
			end
		end

		local flagName = flag.name:gsub("_", "")
		if typ.bits == 64 then
			yield("\t"
				.. "public static var " .. flagName .. enumType
				.. string.rep(" ", 22 - #(flagName))
				.. " = "
				.. string.format(flag.format or format, flag.value)
				.. "i64;"
			)
		else
			yield("\t"
				.. "public static var " .. flagName .. enumType
				.. string.rep(" ", 22 - #(flagName))
				.. " = "
				.. string.format(flag.format or format, flag.value)
				.. ";"
			)
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

	yield("}")
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

local function convert_struct_member(member)
	return "public var " .. member.name .. ": " .. convert_struct_type(member)
end

local namespace = ""

function converter.types(params)
	local typ = params.obj
	local funcs = params.funcs
	if typ.handle then
		lastCombinedFlagBlock()

		yield("@:structAccess")
		yield("@:unreflective")
		yield("@:include('bgfx/c99/bgfx.h')")

		yield("@:native(\"".. typ.cname .. "\")")
		yield("@:lincCppiaDef('" .. typ.name .. "', 'struct')")

		yield("extern class Native_" .. typ.name .. " {")
		yield("    public function new();")
        yield("    public var idx:cpp.UInt16;")
        yield("    inline public function valid():Bool return idx != 0xffff;")
        yield("}")
        yield("// #if (scriptable || cppia)")
		yield("//     @:build(linc.LincCppia.wrapStructExtern('Native_" .. typ.name .. "'))")
		yield("//     class " .. typ.name .. " {}")
		yield("// #else")
		yield("    typedef " .. typ.name .. " = Native_" .. typ.name .. ";")
		yield("// #end")

	elseif hasSuffix(typ.name, "::Enum") then
		lastCombinedFlagBlock()

		-- yield('@:include("bgfx/c99/bgfx.h")')
		-- yield('@:native("'.. typ.cname .. '")')
		-- yield("class " .. typ.typename .. "{")
		yield("@:unreflective")
		yield("extern enum abstract Native_" .. typ.typename .. "(Native_" .. typ.typename .. "Impl) {")
		for idx, enum in ipairs(typ.enum) do

			if print_comments == true then
				if enum.comment ~= nil then
					if idx ~= 1 then
						yield("")
					end

					yield("\t/// <summary>")
					for _, comment in ipairs(enum.comment) do
						yield("\t/// " .. comment)
					end
					yield("\t/// </summary>")
				end
			end

			-- TODO: fix names here
			yield('\t@:native("' .. typ.cname .. "::" .. 'BGFX_' .. typ.cname:gsub("bgfx_(.*)_t", typ.cname.upper) .. '_' .. enum.name:upper() .. '")')
			yield("\tvar " .. enum.name .. ";")
		end
		yield("");
		yield("\t@:native('".. typ.cname .. "::" .. 'BGFX_' .. typ.cname:gsub("bgfx_(.*)_t", typ.cname.upper) .. "_COUNT')")
		yield("\tvar Count" .. ";")
		yield("}")

		-- yield('@:native("cpp::Struct<'.. typ.cname ..', cpp::EnumHandler>")')
		-- yield('extern class ' .. typ.typename .. 'Impl { }')

		yield("@:unreflective")
		yield("@:native('".. typ.cname .."')")
		yield("@:lincCppiaDef('"..typ.typename.."', 'enum')")
		yield("extern class Native_"..typ.typename.."Impl { }")

		yield("// #if (scriptable || cppia)")
		yield("//     @:build(linc.LincCppia.wrapEnumExtern('Native_"..typ.typename.."'))")
		yield("//     enum abstract "..typ.typename.."(Int) from Int to Int {}")
		yield("// #else")
		yield("    typedef "..typ.typename.." = Native_"..typ.typename..";")
		yield("// #end")


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
					comment = flag.comment
				})
			end

			if typ.shift then
				table.insert(flags, {
					name = name .. "Shift",
					value = typ.shift,
					format = "%d",
					comment = typ.comment
				})
			end

			if typ.mask then
				-- generate Mask
				table.insert(flags, {
					name = name .. "Mask",
					value = typ.mask,
					comment = typ.comment
				})
				lookup[name .. "Mask"] = typ.mask
			end
		else
			FlagBlock(typ)
		end
	elseif typ.struct ~= nil then
		local skip = false
		indent = "    "

		local curName = typ.name

		if typ.namespace ~= nil then
			if namespace ~= typ.namespace then
			-- 	yield("1. pub const " .. typ.namespace .. " = extern struct {")
			-- 	namespace = typ.namespace
			-- 	indent = "    "
				curName = typ.namespace .. typ.name
				substructs[typ.name] = curName
			end
		elseif namespace ~= "" then
			indent = "    "
			namespace = ""
			skip = true
		end

		if not skip then			
			-- yield("@:include(\"bgfx/c99/bgfx.h\")")
			-- yield("@:structAccess")
			-- yield("@:unreflective")
			-- yield("@:native(\"".. typ.cname .. "\")")
			-- yield("extern class " .. curName .. " {")

			yield("@:structAccess")
			yield("@:unreflective")
			yield("@:include('bgfx/c99/bgfx.h')")

			yield("@:lincCppiaDef('" .. curName .. "', 'struct')")
			yield("@:native(\"".. typ.cname .. "\")")

			yield("extern class Native_" .. curName .. " {")
		end

		yield(indent .. "public function new();")

		for _, member in ipairs(typ.struct) do
			yield(indent .. convert_struct_member(member) .. ";")
		end
		if funcs ~= nil then
			for _, func in ipairs(funcs) do
				converter.funcs({
					obj = func,
					asMethod = true
				})
			end
		end

		yield("}")
        yield("// #if (scriptable || cppia)")
		yield("//     @:build(linc.LincCppia.wrapStructExtern('Native_" .. curName .. "'))")
		yield("//     class " .. curName .. " {}")
		yield("// #else")
		yield("    typedef " .. curName .. " = Native_" .. curName .. ";")
		yield("// #end")

		-- yield('@:native("cpp::Struct<'.. curName ..', cpp::DefaultHandler>")')
		-- yield('typedef ' .. curName .. ' = cpp.Struct<_' .. curName .. '>;')
	end
end

function converter.funcs(params)
	local func = params.obj
	if func.cpponly then
		return
	elseif func.cppinline and not func.conly then
		return
	end

	-- skip for now, don't know how to handle variadic functions
	if func.cname == "dbg_text_printf" or func.cname == "dbg_text_vprintf" then
		return
	end

	local func_indent = (params.asMethod == true and indent or "    ")

	if func.comments ~= nil then
		yield("")
		if print_comments then
			for _, line in ipairs(func.comments) do
				yield(func_indent .. "/// " .. line)
			end
		end

		local hasParams = false

		for _, arg in ipairs(func.args) do
			if print_comments then
				if arg.comment ~= nil then
					local comment = table.concat(arg.comment, " ")

					yield(func_indent .. "/// <param name=\"" .. arg.name .. "\">" .. comment .. "</param>")

					hasParams = true
				end
			end
		end
	end

	local args = {}
	local argNames = {}

	if func.this ~= nil then
		local ptr = "cpp.Star<"
		if params.asMethod == true then
			ptr = "*"
		end
		-- print("Function " .. func.name .. " has this: " .. func.this_type.type)
		-- if func.const ~= nil then
		-- 	ptr = ptr .. "const "
		-- end

		if func.this_type.type == "Encoder" then
			ptr = "cpp.Star<"
		end

		if hasPrefix(func.this_type.type, "cpp") == false then
			ptr = "cpp.Star<Native_"
		end

		args[1] = "self: " .. ptr .. func.this_type.type .. '>'
		argNames[1] = "this"
	end
	for _, arg in ipairs(func.args) do
		local argName = arg.name
		-- local argName = arg.name:gsub("_", "")
		-- argName = argName:gsub("enum", "enumeration")
		-- argName = argName:gsub("type_", '@"type"')
		if not isempty(argName) then
			table.insert(argNames, argName)
			table.insert(args, argName .. ": " .. convert_type(arg))
		else
			table.insert(args, convert_type(arg))
		end
	end

	if (params.asMethod == true) then
		yield(wrap_method(func, func.this_type.type, args, argNames, func_indent))
	else
		if func.this == nil then
			yield(func_indent .. wrap_simple_func(func, args, argNames))
		end
		yield(
			func_indent .. "@:nocompletion\n" ..
			func_indent .. "@:native(\"bgfx_".. func.cname.."\")\n" ..
			func_indent .. "extern public static function bgfx_" .. func.cname .. "(" .. table.concat(args, ", ") .. "):" .. convert_ret_type(func.ret) ..
			";")
	end
end

function gen.write(codes, outputfile)
	local out = assert(io.open(outputfile, "wb"))
	out:write(codes)
	out:close()
	print("Generating: " .. outputfile)
end

if (...) == nil then
	-- run `lua bindings-zig.lua` in command line
	print(gen.gen())
end

return gen


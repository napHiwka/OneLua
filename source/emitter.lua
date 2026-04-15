-- Generates the final bundle file

local Annotations = require("source.annotations")
local Lexer = require("source.lexer")

local Emitter = {}

local function indent(src, spaces)
	local pad = string.rep(" ", spaces)
	return (src:gsub("([^\n]+)", function(line)
		return pad .. line
	end))
end

local function trim_trailing(s)
	return (s:gsub("%s+$", ""))
end

local function banner(text, width)
	width = width or 72
	local dashes = string.rep("-", width)
	return "--" .. dashes .. "\n-- " .. text .. "\n--" .. dashes
end

local function serialize_aliases(aliases)
	if not aliases or not next(aliases) then
		return "{}"
	end
	local parts = {}
	for from, to in pairs(aliases) do
		parts[#parts + 1] = string.format("   [%q] = %q", from, to)
	end
	table.sort(parts)
	return "{\n" .. table.concat(parts, ",\n") .. "\n}"
end

local function prepare_source(src, cfg)
	local mode = cfg.strip
	if not mode or mode == false then
		return src
	elseif mode == "all" then
		return Lexer.strip(src, { keep_annotations = false, keep_module = true })
	elseif mode == "non_ann" then
		return Lexer.strip(src, { keep_annotations = true, keep_module = true })
	else
		error("unknown strip value: " .. tostring(mode), 2)
	end
end

local RUNTIME = [[
local __modules__ = {}
local __loaders__  = {}
local __aliases__  = __ALIASES__

local function __require__(name)
   name = __aliases__[name] or name
   if not __modules__[name] then
      local loader = __loaders__[name]
      if not loader then
         error("[bundle] unknown module: " .. tostring(name), 2)
      end
      __modules__[name] = loader(name:match("^(.-)%.[^%.]+$") or "")
   end
   return __modules__[name]
end

local _G_require = require
---@diagnostic disable-next-line: lowercase-global
local require = function(name)
   name = __aliases__[name] or name
   if __loaders__[name] then return __require__(name) end
   return _G_require(name)
end
]]

---@param cfg table
---@param files table[] each entry must have .name .path .src
---@return string
function Emitter.generate(cfg, files)
	local modules = {}
	for _, f in ipairs(files) do
		modules[#modules + 1] = {
			name = f.name,
			path = f.path,
			src = f.src,
			body = prepare_source(f.src, cfg),
		}
	end

	local out = {}

	local timestamp = os.date and os.date("!%Y-%m-%dT%H:%M:%SZ") or "unknown"
	out[#out + 1] = string.format("--[[ LuaOne | entry: %s | modules: %d | %s ]]", cfg.entry, #modules, timestamp)

	-- Type annotations
	local ann_lines = Annotations.collect(modules)
	if #ann_lines > 0 then
		out[#out + 1] = ""
		out[#out + 1] = banner("TYPE ANNOTATIONS")
		out[#out + 1] = "-- Extracted from source modules."
		out[#out + 1] = "-- Hoisted to top level so lua-language-server can index them."
		out[#out + 1] = "-- Regenerate by re-running the bundler."
		out[#out + 1] = "--"
		for _, line in ipairs(ann_lines) do
			out[#out + 1] = line
		end
	end

	-- Runtime
	out[#out + 1] = ""
	out[#out + 1] = banner("RUNTIME")
	out[#out + 1] = (RUNTIME:gsub("__ALIASES__", function()
		return serialize_aliases(cfg.aliases)
	end))

	-- Module loaders
	out[#out + 1] = banner("MODULES")
	out[#out + 1] = ""

	for _, mod in ipairs(modules) do
		local body = trim_trailing(mod.body)
		out[#out + 1] = "-- " .. mod.name .. "  <-  " .. mod.path
		out[#out + 1] = string.format("__loaders__[%q] = function(...)", mod.name)
		out[#out + 1] = indent(body, 3)
		out[#out + 1] = "end\n"
	end

	out[#out + 1] = banner("ENTRY")
	out[#out + 1] = ""
	out[#out + 1] = string.format("---@module '%s'", cfg.entry)

	local name = cfg.name or cfg.entry:match("[^%.]+$") or "lib"
	out[#out + 1] = string.format("local %s = __require__(%q)", name, cfg.entry)
	out[#out + 1] = string.format("return %s", name)

	return table.concat(out, "\n")
end

return Emitter

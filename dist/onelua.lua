--[[ LuaOne | entry: bundler | modules: 7 | 2026-04-17T11:33:46Z ]]

--------------------------------------------------------------------------
-- TYPE ANNOTATIONS
--------------------------------------------------------------------------
-- Extracted from source modules.
-- Hoisted to top level so lua-language-server can index them.
-- Regenerate by re-running the bundler.
--
---@class BundlerConfig
---@field entry string Module name to use as the entry point (required).
---@field src string? Base source directory. Default: `"./"`
---@field out string? Output file path. Default: `"./bundle.lua"`
---@field name string? Exported local name in the bundle. Defaults to the entry basename.
---@field extra string[]? Additional module names to force-include regardless of discovery.
---@field skip_extra_files_requires boolean? When `true`, `extra` modules are included without scanning their own `require()` calls.
---@field aliases table<string,string>? Require aliases applied at runtime: `{ [from] = to }`.
---@field strip "all"|"non_ann"|false? Strip mode. `"all"` removes all comments; `"non_ann"` keeps `---@` annotation lines.
---@field compact boolean? Collapse consecutive blank lines in stripped output.
---@field resolve boolean? Rewrite statically-detectable dynamic `require()` calls before bundling.
---@field debug boolean? Print verbose discovery and rewrite output.
---@field verify boolean? Load the bundle after writing to verify it executes cleanly.

--------------------------------------------------------------------------
-- RUNTIME
--------------------------------------------------------------------------
local __modules__ = {}
local __loaders__ = {}
local __aliases__ = {}

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
	if __loaders__[name] then
		return __require__(name)
	end
	return _G_require(name)
end

--------------------------------------------------------------------------
-- MODULES
--------------------------------------------------------------------------

-- source.lexer <- ./source/lexer.lua
__loaders__["source.lexer"] = function(...)
	local Lexer = {}
	Lexer.T = {
		IDENT = "IDENT",
		STRING = "STRING",
		LPAREN = "LPAREN",
		RPAREN = "RPAREN",
		CONCAT = "CONCAT",
		OTHER = "OTHER",
	}
	local T = Lexer.T
	local REQUIRE_KEYWORD = "require"
	local function char_at(src, i, n, off)
		local j = i + (off or 0)
		return (j >= 1 and j <= n) and src:sub(j, j) or ""
	end
	local function long_bracket_span(src, pos, n)
		local eq = 0
		local j = pos
		while j <= n and src:sub(j, j) == "=" do
			eq = eq + 1
			j = j + 1
		end
		if j > n or src:sub(j, j) ~= "[" then
			return nil
		end
		local cs = j + 1
		local close = "]" .. string.rep("=", eq) .. "]"
		local s, e = src:find(close, cs, true)
		return cs, s and (s - 1) or n, s and (e + 1) or (n + 1), s ~= nil
	end
	local function scan_short_string(src, i, n, quote)
		local parts = {}
		while i <= n do
			local c = src:sub(i, i)
			if c == "\\" then
				local esc = (i + 1 <= n) and src:sub(i + 1, i + 1) or ""
				if esc == "z" then
					i = i + 2
					while i <= n do
						local w = src:sub(i, i)
						if w == " " or w == "\t" or w == "\r" or w == "\n" then
							i = i + 1
						else
							break
						end
					end
				else
					parts[#parts + 1] = "\\" .. esc
					i = i + 2
				end
			elseif c == quote then
				return parts, i + 1, true
			elseif c == "\n" or c == "\r" then
				return parts, i, false
			else
				parts[#parts + 1] = c
				i = i + 1
			end
		end
		return parts, i, false
	end
	function Lexer.tokenize(src)
		local tokens = {}
		local i, n, line = 1, #src, 1
		local function ch(off)
			return char_at(src, i, n, off)
		end
		local function skip(k)
			for _ = 1, k or 1 do
				if src:sub(i, i) == "\n" then
					line = line + 1
				end
				i = i + 1
			end
		end
		local function advance_to(target)
			while i < target do
				if src:sub(i, i) == "\n" then
					line = line + 1
				end
				i = i + 1
			end
		end
		local function push(typ, value)
			tokens[#tokens + 1] = { type = typ, value = value, line = line }
		end
		while i <= n do
			local c = ch()
			if c:match("^%s$") then
				skip()
			elseif c == "-" and ch(1) == "-" then
				local is_block = false
				if ch(2) == "[" then
					local cs, _, next_pos, closed = long_bracket_span(src, i + 3, n)
					if cs then
						if not closed then
							print("[lexer]: unclosed block comment at line " .. line)
						end
						advance_to(next_pos)
						is_block = true
					end
				end
				if not is_block then
					while i <= n and ch() ~= "\n" do
						skip()
					end
				end
			elseif c == "[" and (ch(1) == "[" or ch(1) == "=") then
				local cs, ce, next_pos, closed = long_bracket_span(src, i + 1, n)
				if cs then
					if not closed then
						print("[lexer]: unclosed long string at line " .. line)
					end
					push(T.STRING, src:sub(cs, ce))
					advance_to(next_pos)
				else
					push(T.OTHER, "[")
					skip()
				end
			elseif c == '"' or c == "'" then
				local q = c
				skip()
				local parts, new_i = scan_short_string(src, i, n, q)
				i = new_i
				push(T.STRING, table.concat(parts))
			elseif c == "." then
				if ch(1) == "." then
					if ch(2) == "." then
						push(T.OTHER, "...")
						skip(3)
					else
						push(T.CONCAT, "..")
						skip(2)
					end
				else
					push(T.OTHER, ".")
					skip()
				end
			elseif c == "(" then
				push(T.LPAREN, "(")
				skip()
			elseif c == ")" then
				push(T.RPAREN, ")")
				skip()
			elseif c:match("^%d$") then
				if c == "0" and (ch(1) == "x" or ch(1) == "X") then
					skip(2)
					while i <= n and ch():match("^%x$") do
						skip()
					end
					if ch() == "." then
						skip()
						while i <= n and ch():match("^%x$") do
							skip()
						end
					end
					if ch():match("^[pP]$") then
						skip()
						if ch():match("^[%+%-]$") then
							skip()
						end
						while i <= n and ch():match("^%d$") do
							skip()
						end
					end
				else
					while i <= n and ch():match("^%d$") do
						skip()
					end
					if ch() == "." and ch(1):match("^%d$") then
						skip()
						while i <= n and ch():match("^%d$") do
							skip()
						end
					end
					if ch():match("^[eE]$") then
						skip()
						if ch():match("^[%+%-]$") then
							skip()
						end
						while i <= n and ch():match("^%d$") do
							skip()
						end
					end
				end
				push(T.OTHER, "<num>")
			elseif c:match("^[%a_]$") then
				local s = i
				while i <= n and ch():match("^[%w_]$") do
					skip()
				end
				push(T.IDENT, src:sub(s, i - 1))
			else
				push(T.OTHER, c)
				skip()
			end
		end
		return tokens
	end
	function Lexer.find_requires(tokens)
		local results = {}
		local n = #tokens
		local req_idents = { [REQUIRE_KEYWORD] = true }
		for j = 1, n - 3 do
			local ta = tokens[j]
			local tb = tokens[j + 1]
			local tc = tokens[j + 2]
			local td = tokens[j + 3]
			if
				ta.type == T.IDENT
				and ta.value == "local"
				and tb.type == T.IDENT
				and tc.type == T.OTHER
				and tc.value == "="
				and td.type == T.IDENT
				and req_idents[td.value]
			then
				local te = tokens[j + 4]
				if not (te and te.type == T.LPAREN) then
					req_idents[tb.value] = true
				end
			end
		end
		local function fold_strings(j)
			local start = j
			local depth = 0
			while tokens[j] and tokens[j].type == T.LPAREN do
				depth = depth + 1
				j = j + 1
			end
			if not (tokens[j] and tokens[j].type == T.STRING) then
				return nil, start
			end
			local parts = { tokens[j].value }
			j = j + 1
			while tokens[j] and tokens[j].type == T.CONCAT and tokens[j + 1] and tokens[j + 1].type == T.STRING do
				parts[#parts + 1] = tokens[j + 1].value
				j = j + 2
			end
			for _ = 1, depth do
				if not (tokens[j] and tokens[j].type == T.RPAREN) then
					return nil, start
				end
				j = j + 1
			end
			return table.concat(parts), j
		end
		local i = 1
		while i <= n do
			local tk = tokens[i]
			if tk.type == T.IDENT and req_idents[tk.value] then
				local req_line = tk.line
				local next1 = tokens[i + 1]
				if next1 and next1.type == T.STRING then
					results[#results + 1] = { kind = "static", value = next1.value, line = req_line }
					i = i + 2
				elseif next1 and next1.type == T.LPAREN then
					local arg_start = i + 2
					local value, next_j = fold_strings(arg_start)
					if value and tokens[next_j] and tokens[next_j].type == T.RPAREN then
						results[#results + 1] = { kind = "static", value = value, line = req_line }
						i = next_j + 1
					else
						local j = arg_start
						local rdepth = 1
						local first_str, last_str = nil, nil
						local arg_seq = {}
						while j <= n do
							local t = tokens[j]
							if t.type == T.LPAREN then
								rdepth = rdepth + 1
								arg_seq[#arg_seq + 1] = t
							elseif t.type == T.RPAREN then
								rdepth = rdepth - 1
								if rdepth == 0 then
									break
								end
								arg_seq[#arg_seq + 1] = t
							else
								arg_seq[#arg_seq + 1] = t
								if t.type == T.STRING then
									first_str = first_str or t.value
									last_str = t.value
								end
							end
							j = j + 1
						end
						local rewrite_as = nil
						if #arg_seq == 3 then
							local a, b, c = arg_seq[1], arg_seq[2], arg_seq[3]
							if b.type == T.CONCAT then
								if a.type == T.IDENT and c.type == T.STRING then
									rewrite_as = c.value
								elseif a.type == T.STRING and c.type == T.IDENT then
									rewrite_as = a.value
								end
							end
						end
						results[#results + 1] = {
							kind = "dynamic",
							hint = first_str,
							hint_trail = (last_str ~= first_str) and last_str or nil,
							rewrite_as = rewrite_as,
							line = req_line,
						}
						i = j + 1
					end
				else
					i = i + 1
				end
			else
				i = i + 1
			end
		end
		return results
	end
	local function compact_lines(src)
		local lines = {}
		local pending = false
		for line, nl in src:gmatch("([^\n]*)(\n?)") do
			if line == "" and nl == "" then
				break
			end
			line = line:gsub("[ \t]+$", "")
			if line ~= "" then
				if pending and #lines > 0 then
					lines[#lines + 1] = "\n"
				end
				lines[#lines + 1] = line
				pending = nl == "\n"
			elseif nl ~= "" then
				pending = pending or (#lines > 0)
			end
		end
		return table.concat(lines)
	end
	function Lexer.strip(src, opts)
		opts = opts or {}
		local keep_ann = opts.keep_annotations or false
		local keep_module = opts.keep_module or false
		local compact = opts.compact or false
		local out = {}
		local i, n = 1, #src
		local function ch(off)
			return char_at(src, i, n, off)
		end
		local function emit(s)
			out[#out + 1] = s
		end
		local function adv(k)
			i = i + (k or 1)
		end
		local function copy_short_string()
			local q = ch()
			emit(q)
			adv()
			local parts, new_i, closed = scan_short_string(src, i, n, q)
			for _, p in ipairs(parts) do
				emit(p)
			end
			if closed then
				emit(q)
			end
			i = new_i
		end
		while i <= n do
			local c = ch()
			if c == "-" and ch(1) == "-" then
				local is_block = false
				if ch(2) == "[" then
					local cs, _, next_pos, closed = long_bracket_span(src, i + 3, n)
					if cs then
						if not closed then
							print("[lexer]: unclosed block comment")
						end
						local nl_count = 0
						for _ in src:sub(i, next_pos - 1):gmatch("\n") do
							nl_count = nl_count + 1
						end
						if nl_count > 0 then
							emit(string.rep("\n", nl_count))
						end
						i = next_pos
						is_block = true
					end
				end
				if not is_block then
					local ls = i
					while i <= n and src:sub(i, i) ~= "\n" do
						i = i + 1
					end
					local comment = src:sub(ls, i - 1)
					if
						(keep_ann and comment:match("^%-%-%-%s*@"))
						or (keep_module and comment:match("^%-%-%-%s*@module"))
					then
						emit(comment)
					end
				end
			elseif c == "[" and (ch(1) == "[" or ch(1) == "=") then
				local cs, _, next_pos, closed = long_bracket_span(src, i + 1, n)
				if cs then
					if not closed then
						print("[lexer]: unclosed long string")
					end
					emit(src:sub(i, next_pos - 1))
					i = next_pos
				else
					emit(c)
					adv()
				end
			elseif c == '"' or c == "'" then
				copy_short_string()
			else
				emit(c)
				adv()
			end
		end
		local result = table.concat(out)
		if compact then
			return compact_lines(result)
		end
		return (result:gsub("\n\n\n+", "\n\n"))
	end
	function Lexer.rewrite_requires(src, reqs)
		local line_map = {}
		for _, r in ipairs(reqs) do
			if r.rewrite_as then
				line_map[r.line] = r.rewrite_as
			end
		end
		if not next(line_map) then
			return src, 0
		end
		local total = 0
		local out = {}
		local ln = 0
		for line in (src .. "\n"):gmatch("([^\n]*)\n") do
			ln = ln + 1
			local target = line_map[ln]
			if target then
				local pat_esc = target:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1")
				local repl_raw = 'require("' .. target .. '")'
				local repl = repl_raw:gsub("%%", "%%%%")
				local n1, n2
				line, n1 = line:gsub("require%s*%(%s*[%w_][%w_%.]-%s*%.%.%s*[\"']" .. pat_esc .. "[\"']%s*%)", repl)
				line, n2 = line:gsub("require%s*%(%s*[\"']" .. pat_esc .. "[\"']%s*%.%.%s*[%w_][%w_%.]+%s*%)", repl)
				total = total + n1 + n2
			end
			out[#out + 1] = line
		end
		if out[#out] == "" then
			out[#out] = nil
		end
		return table.concat(out, "\n"), total
	end
	return Lexer
end

-- source.resolver <- ./source/resolver.lua
__loaders__["source.resolver"] = function(...)
	local Resolver = {}
	local function ensure_dir(path)
		local dir = path:match("^(.*)[/\\][^/\\]+$")
		if not dir or dir == "" then
			return
		end
		local sep = package.config:sub(1, 1)
		if sep == "\\" then
			os.execute('mkdir "' .. dir:gsub("/", "\\") .. '" 2>nul')
		else
			os.execute('mkdir -p "' .. dir .. '"')
		end
	end
	local function normalize_dir(dir)
		if dir == "" then
			return "./"
		end
		return dir:match("[/\\]$") and dir or dir .. "/"
	end
	local function name_to_path(name)
		return name:gsub("%.", "/")
	end
	local function normalize_slashes(path)
		return (path:gsub("\\", "/"))
	end
	local function trim_lua_extension(name)
		return (name:gsub("%.lua$", ""))
	end
	local function trim_leading_current_dir(path)
		return (path:gsub("^%./", ""))
	end
	local function starts_with(text, prefix)
		return text:sub(1, #prefix) == prefix
	end
	local function path_to_module_name(path)
		path = normalize_slashes(path)
		path = trim_leading_current_dir(path)
		path = trim_lua_extension(path)
		path = path:gsub("/init$", "")
		path = path:gsub("^/", "")
		return (path:gsub("/", "."))
	end
	local function try_open(path)
		local f = io.open(path, "r")
		if f then
			f:close()
			return path
		end
	end
	function Resolver.resolve(name, src)
		local base = normalize_dir(src) .. name_to_path(name)
		return try_open(base .. ".lua") or try_open(base .. "/init.lua")
	end
	function Resolver.normalize_module_name(spec, src)
		local normalized = normalize_slashes(spec)
		local src_prefix = trim_leading_current_dir(normalize_slashes(normalize_dir(src)))
		normalized = trim_leading_current_dir(normalized)
		normalized = trim_lua_extension(normalized)
		if src_prefix ~= "" and starts_with(normalized, src_prefix) then
			normalized = normalized:sub(#src_prefix + 1)
		end
		if normalized:match("[/\\]") then
			normalized = path_to_module_name(normalized)
		end
		return normalized
	end
	function Resolver.read(path)
		local f, err = io.open(path, "r")
		if not f then
			error("cannot open: " .. path .. (err and ("\n  " .. err) or ""), 2)
		end
		local src = f:read("*a")
		f:close()
		return (src:gsub("\r\n", "\n"):gsub("\r", "\n"))
	end
	function Resolver.write(path, content)
		ensure_dir(path)
		local f, err = io.open(path, "w")
		if not f then
			error("cannot write: " .. path .. (err and ("\n  " .. err) or ""), 2)
		end
		f:write(content)
		f:close()
	end
	return Resolver
end

-- source.discover <- ./source/discover.lua
__loaders__["source.discover"] = function(...)
	local Lexer = require("source.lexer")
	local Resolver = require("source.resolver")
	local Discover = {}
	function Discover.run(entry, src, opts)
		opts = opts or {}
		local hint_shown = false
		local debug_mode = opts.debug or false
		local visited = {}
		local resolved = {}
		local warned_lines = {}
		local files = {}
		local warnings = {}
		local function log(msg)
			if debug_mode then
				print("[discover] " .. msg)
			end
		end
		local function note_warn(msg)
			warnings[#warnings + 1] = msg
			print("WARN: " .. msg)
		end
		local function resolve_local(name)
			if resolved[name] == nil then
				resolved[name] = Resolver.resolve(name, src) or false
			end
			return resolved[name] or nil
		end
		local function visit(name, follow_requires)
			if visited[name] then
				log("skip (already visited): " .. name)
				return
			end
			visited[name] = true
			log("processing: " .. name)
			local path = resolve_local(name)
			if not path then
				error("module not found: '" .. name .. "'  (searched in " .. src .. ")", 0)
			end
			local file_src = Resolver.read(path)
			local tokens = Lexer.tokenize(file_src)
			if follow_requires then
				local reqs = Lexer.find_requires(tokens)
				local src_lines = {}
				for ln in (file_src .. "\n"):gmatch("([^\n]*)\n") do
					src_lines[#src_lines + 1] = ln
				end
				for _, req in ipairs(reqs) do
					if req.kind == "static" then
						local resolved_path = resolve_local(req.value)
						if resolved_path then
							visit(req.value, true)
						else
							log("external (skipping): " .. req.value)
						end
					else
						local warning_key = path .. ":" .. tostring(req.line)
						if not warned_lines[warning_key] then
							warned_lines[warning_key] = true
							if not hint_shown then
								log("dynamic require(s) found; use 'extra' or 'aliases' in config")
								hint_shown = true
							end
							local snippet = (src_lines[req.line] or "?"):match("^%s*(.-)%s*$")
							local hints = ""
							if req.hint then
								hints = hints .. '  lead:"' .. req.hint .. '"'
							end
							if req.hint_trail then
								hints = hints .. '  trail:"' .. req.hint_trail .. '"'
							end
							note_warn("dynamic require at " .. path .. ":" .. req.line .. hints .. " -> " .. snippet)
						end
					end
				end
			end
			files[#files + 1] = {
				name = name,
				path = path,
				src = file_src,
			}
			log("added: " .. name)
		end
		visit(entry, true)
		for _, name in ipairs(opts.extra_names or {}) do
			local path = resolve_local(name)
			if not path then
				note_warn("extra module '" .. name .. "' not found in " .. src)
			else
				visit(name, not opts.skip_extra_files_requires)
			end
		end
		return files, warnings
	end
	return Discover
end

-- source.annotations <- ./source/annotations.lua
__loaders__["source.annotations"] = function(...)
	local Annotations = {}
	local DEFINITION_TAGS = {
		["@class"] = true,
		["@alias"] = true,
		["@enum"] = true,
	}
	local QUALIFIER_TAGS = {
		["@field"] = true,
		["@operator"] = true,
	}
	local function tag_of(line)
		return line:match("^%s*%-%-%-%s*(@%a+)")
	end
	function Annotations.extract(src)
		local lines = {}
		local result = {}
		local in_def = false
		for line in (src):gmatch("([^\n]*)\n") do
			lines[#lines + 1] = line
		end
		for _, line in ipairs(lines) do
			local tag = tag_of(line)
			if tag then
				local stripped = line:match("^%s*(.-)%s*$")
				if DEFINITION_TAGS[tag] then
					in_def = true
					result[#result + 1] = stripped
				elseif in_def and QUALIFIER_TAGS[tag] then
					result[#result + 1] = stripped
				else
					in_def = false
				end
			else
				in_def = false
			end
		end
		return result
	end
	function Annotations.collect(modules)
		local seen = {}
		local result = {}
		for _, mod in ipairs(modules) do
			if mod.src then
				for _, line in ipairs(Annotations.extract(mod.src)) do
					if not seen[line] then
						seen[line] = true
						result[#result + 1] = line
					end
				end
			end
		end
		return result
	end
	function Annotations.infer_return_class(src)
		local last_class = nil
		for line in src:gmatch("[^\n]+") do
			local cls = line:match("^%s*%-%-%-%s*@class%s+([%w_%.]+)")
			if cls then
				last_class = cls
			end
		end
		return last_class
	end
	return Annotations
end

-- source.emitter <- ./source/emitter.lua
__loaders__["source.emitter"] = function(...)
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
	local function prepare_source(name, src, cfg)
		local resolve = cfg.resolve
		if resolve then
			local tokens = Lexer.tokenize(src)
			local reqs = Lexer.find_requires(tokens)
			local count
			src, count = Lexer.rewrite_requires(src, reqs)
			if count > 0 and cfg.debug then
				print(string.format("[emitter] rewrote %d dynamic require(s) in `%s`", count, name))
			end
		end
		local mode = cfg.strip
		if not mode or mode == false then
			return src
		end
		if mode ~= "all" and mode ~= "non_ann" then
			error("unknown strip value: " .. tostring(mode), 2)
		end
		return Lexer.strip(src, {
			keep_annotations = (mode == "non_ann"),
			keep_module = true,
			compact = cfg.compact,
		})
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
	function Emitter.generate(cfg, files)
		local modules = {}
		for _, f in ipairs(files) do
			modules[#modules + 1] = {
				name = f.name,
				path = f.path,
				src = f.src,
				body = prepare_source(f.name, f.src, cfg),
			}
		end
		local out = {}
		local timestamp = os.date and os.date("!%Y-%m-%dT%H:%M:%SZ") or "unknown"
		out[#out + 1] = string.format("--[[ LuaOne | entry: %s | modules: %d | %s ]]", cfg.entry, #modules, timestamp)
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
		out[#out + 1] = ""
		out[#out + 1] = banner("RUNTIME")
		out[#out + 1] = (RUNTIME:gsub("__ALIASES__", function()
			return serialize_aliases(cfg.aliases)
		end))
		out[#out + 1] = banner("MODULES")
		out[#out + 1] = ""
		for _, mod in ipairs(modules) do
			local body = trim_trailing(mod.body)
			out[#out + 1] = "-- " .. mod.name .. " <- " .. mod.path
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
end

-- source.cli <- ./source/cli.lua
__loaders__["source.cli"] = function(...)
	local DEFAULT_CONFIG = "bundler.config.lua"
	local FALLBACK_CONFIG = "_bundler.config.lua"
	local CLI = {}
	local HELP = table.concat({
		"OneLua - bundle a Lua project into a single file",
		"",
		"Usage:",
		"  lua bundler.lua [options]",
		"",
		"Options:",
		'  --entry   <module>   Entry module or file path      e.g. "main" or "src/main.lua"',
		'  --src     <dir>      Source directory               default: "./"',
		'  --out     <file>     Output bundle path             default: "./bundle.lua"',
		"  --name    <ident>    Exported variable name         default: entry basename",
		"  --config  <file>     Config file path               default: bundler.config.lua",
		"  --strip   <mode>     Strip comments from output",
		"                        all      remove all comments (keeps ---@module for LSP)",
		"                        non_ann  remove non-annotation comments (keeps ---@...)",
		"  --compact            Enable compact output",
		"  --resolve            Resolve possible dynamic dependencies",
		"  --debug              Verbose dependency-discovery logging",
		"  --verify             Load the bundle after writing to confirm it runs",
		"  --help               Show this help",
		"",
		"Config file (bundler.config.lua) is detected automatically when present in",
		"working directory. CLI flags override config-file values when both are present.",
		"",
		"Examples:",
		"  lua bundler.lua --entry main --src src/ --out dist/app.lua",
		"  lua bundler.lua --config my_project.config.lua --debug --verify",
		"  lua bundler.lua --config release.config.lua --strip all --out dist/lib.lua",
	}, "\n")
	local function parse_args(args)
		local flags = {}
		local i = 1
		while i <= #args do
			local a = args[i]
			if a == "--help" or a == "-h" then
				flags.help = true
			elseif a == "--debug" then
				flags.debug = true
			elseif a == "--verify" then
				flags.verify = true
			elseif a == "--resolve" then
				flags.resolve = true
			elseif a == "--compact" then
				flags.compact = true
			elseif a == "--entry" then
				i = i + 1
				flags.entry = args[i]
			elseif a == "--src" then
				i = i + 1
				flags.src = args[i]
			elseif a == "--out" then
				i = i + 1
				flags.out = args[i]
			elseif a == "--name" then
				i = i + 1
				flags.name = args[i]
			elseif a == "--strip" then
				i = i + 1
				local mode = args[i]
				if mode ~= "all" and mode ~= "non_ann" then
					return nil, "--strip must be 'all' or 'non_ann'"
				end
				flags.strip = mode
			elseif a == "--config" then
				i = i + 1
				flags.config_path = args[i]
			else
				return nil, "unknown option: " .. tostring(a)
			end
			i = i + 1
		end
		return flags
	end
	local function merge(base, overrides)
		local result = {}
		for k, v in pairs(base or {}) do
			result[k] = v
		end
		for k, v in pairs(overrides or {}) do
			if v ~= nil then
				result[k] = v
			end
		end
		return result
	end
	local function load_config(path)
		local chunk, err = loadfile(path)
		if not chunk then
			if err and err:match("cannot open") then
				return nil
			end
			error("config error in '" .. path .. "':\n  " .. (err or "unknown"), 0)
		end
		local cfg = chunk()
		if type(cfg) ~= "table" then
			error("config file '" .. path .. "' must return a table", 0)
		end
		return cfg
	end
	local function detect_config_path(preferred)
		if preferred then
			local cfg = load_config(preferred)
			if not cfg then
				error("config file not found: " .. preferred, 0)
			end
			return preferred, cfg
		end
		local candidates = { DEFAULT_CONFIG, FALLBACK_CONFIG }
		for _, path in ipairs(candidates) do
			local cfg = load_config(path)
			if cfg then
				return path, cfg
			end
		end
	end
	function CLI.parse(args)
		local flags, parse_msg = parse_args(args)
		if not flags then
			error(parse_msg .. "\n  run with --help for usage", 0)
		end
		if flags.help then
			print(HELP)
			return nil
		end
		local config_path, file_cfg = detect_config_path(flags.config_path)
		if config_path then
			print("[bundler] using config: " .. config_path)
		end
		file_cfg = file_cfg or {}
		local cfg = merge(file_cfg, {
			entry = flags.entry,
			src = flags.src,
			out = flags.out,
			name = flags.name,
			strip = flags.strip,
			compact = flags.compact,
			debug = flags.debug,
			verify = flags.verify,
			resolve = flags.resolve,
		})
		cfg.src = cfg.src or "./"
		cfg.out = cfg.out or "./bundle.lua"
		cfg.compact = cfg.compact or false
		cfg.debug = cfg.debug or false
		cfg.verify = cfg.verify or false
		cfg.resolve = cfg.resolve or false
		if #args == 0 and not config_path then
			print(HELP)
			return nil
		end
		return cfg
	end
	return CLI
end

-- bundler <- ./bundler.lua
__loaders__["bundler"] = function(...)
	local SELF_DIR = ((debug.getinfo(1, "S").source:sub(2)):match("^(.*[/\\])") or "./")
	package.path = SELF_DIR .. "?.lua;" .. SELF_DIR .. "?/init.lua;" .. package.path
	local Discover = require("source.discover")
	local Emitter = require("source.emitter")
	local Resolver = require("source.resolver")
	local Cli = require("source.cli")
	local Bundler = {}
	Bundler.Cli = Cli
	local function verify_bundle(out)
		local dir = out:match("^(.*[/\\])") or "./"
		local name = out:match("([^/\\]+)%.lua$")
		if not name then
			print("[bundler] verify: skipped (cannot extract module name)")
			return
		end
		local prev_path = package.path
		package.path = dir .. "?.lua;" .. prev_path
		package.loaded[name] = nil
		local old_arg = _G.arg
		_G.arg = nil
		print("[bundler] verifying...")
		local ok, result = pcall(require, name)
		_G.arg = old_arg
		package.path = prev_path
		package.loaded[name] = nil
		if not ok then
			error("verify failed: " .. tostring(result), 0)
		end
		print("[bundler] verify OK: " .. tostring(result))
		if type(result) == "table" then
			local keys = {}
			for k in pairs(result) do
				keys[#keys + 1] = tostring(k)
			end
			table.sort(keys)
			print("[bundler] exported: " .. table.concat(keys, ", "))
		end
	end
	function Bundler.bundle(cfg)
		assert(type(cfg.entry) == "string" and cfg.entry ~= "", "cfg.entry must be a non-empty string")
		cfg.src = cfg.src or "./"
		cfg.out = cfg.out or "./bundle.lua"
		cfg.entry = Resolver.normalize_module_name(cfg.entry, cfg.src)
		print(string.format("[bundler] entry:`%s` src:`%s` out:`%s`", cfg.entry, cfg.src, cfg.out))
		local files, warnings = Discover.run(cfg.entry, cfg.src, {
			debug = cfg.debug,
			extra_names = cfg.extra,
			skip_extra_files_requires = cfg.skip_extra_files_requires,
		})
		print(string.format("[bundler] found %d module(s):", #files))
		for _, f in ipairs(files) do
			print(string.format(" [+] `%s` -> `%s`", f.name, f.path))
		end
		if #warnings > 0 then
			print(string.format("[bundler] %d dynamic require(s) detected", #warnings))
		end
		local content = Emitter.generate(cfg, files)
		Resolver.write(cfg.out, content)
		print("[bundler] written: " .. cfg.out)
		if cfg.verify then
			verify_bundle(cfg.out)
		end
		return true
	end
	function Bundler.run_cli(args)
		local cfg = Cli.parse(args or {})
		if not cfg then
			return
		end
		local ok, err = pcall(Bundler.bundle, cfg)
		if not ok then
			error("[bundler] fatal: " .. tostring(err) .. "\n")
		end
	end
	if arg and arg[0] == debug.getinfo(1, "S").source:sub(2) then
		Bundler.run_cli(arg or {})
	end
	return Bundler
end

--------------------------------------------------------------------------
-- ENTRY
--------------------------------------------------------------------------

---@module 'bundler'
local bundler = __require__("bundler")
return bundler

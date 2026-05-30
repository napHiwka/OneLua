-- Discovers all local dependencies for a given entry module with lexer

local Lexer = require("source.lexer")
local Resolver = require("source.resolver")

local Discover = {}

--- Walks the dependency graph starting from `entry`, resolving `require()`
--- calls recursively within `src_dir`. Files are returned in depth-first
--- order (dependencies before dependents).
---@param entry string Entry module name.
---@param src_dir string Root source directory.
---@param opts? table
---@return table files
---@return table warnings
function Discover.run(entry, src_dir, opts)
	opts = opts or {}

	local debug_mode = opts.debug or false
	local visited = {} -- name -> true, prevents re-processing
	local resolved = {} -- name -> path|false, caches Resolver.resolve results
	local warned = {} -- "path:line" -> true, deduplicates dynamic-require warnings
	local files = {}
	local warnings = {}
	local hint_shown = false

	local function log(msg)
		if debug_mode then
			print("[discover] " .. msg)
		end
	end

	local function warn(msg)
		warnings[#warnings + 1] = msg
		print("WARN: " .. msg)
	end

	local function resolve_cached(name)
		if resolved[name] == nil then
			resolved[name] = Resolver.resolve(name, src_dir) or false
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

		local path = resolve_cached(name)
		if not path then
			error("module not found: '" .. name .. "'  (searched in " .. src_dir .. ")", 0)
		end

		local src = Resolver.read(path)
		local tokens = Lexer.tokenize(src)

		if follow_requires then
			local reqs = Lexer.find_requires(tokens)
			-- Build a line-indexed table for warning snippets
			local src_lines = {}
			for ln in (src .. "\n"):gmatch("([^\n]*)\n") do
				src_lines[#src_lines + 1] = ln
			end

			for _, req in ipairs(reqs) do
				if req.kind == "static" then
					if resolve_cached(req.value) then
						visit(req.value, true)
					else
						log("external (skipping): " .. req.value)
					end
				else
					local key = path .. ":" .. tostring(req.line)
					if not warned[key] then
						warned[key] = true
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
						warn("dynamic require at " .. path .. ":" .. req.line .. hints .. " -> " .. snippet)
					end
				end
			end
		end
		files[#files + 1] = { name = name, path = path, src = src }
		log("added: " .. name)
	end

	visit(entry, true)
	for _, name in ipairs(opts.extra_names or {}) do
		if not resolve_cached(name) then
			warn("extra module '" .. name .. "' not found in " .. src_dir)
		else
			visit(name, not opts.skip_extra_files_requires)
		end
	end
	return files, warnings
end

return Discover

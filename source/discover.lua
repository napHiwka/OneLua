-- Discovers all local dependencies for a given entry module with lexer

local Lexer = require("source.lexer")
local Resolver = require("source.resolver")

local Discover = {}

---Returns files in depth-first order (deps before dependents).
---Each entry: { name, path, src }.
---@param entry string
---@param src string
---@param opts table?
---@return table files
---@return table warnings
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

		-- Build line map; append "\n" so the final line (if unterminated) is captured.
		local src_lines = {}
		for ln in (file_src .. "\n"):gmatch("([^\n]*)\n") do
			src_lines[#src_lines + 1] = ln
		end

		if follow_requires then
			local reqs = Lexer.find_requires(tokens)

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
			note_warn("extra_file '" .. name .. "' not found in " .. src)
		else
			visit(name, not opts.skip_extra_files_requires)
		end
	end

	return files, warnings
end

return Discover

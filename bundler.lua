-- OneLua: bundle a Lua project into a single distributable file.
--
-- Library usage:
--   local Bundler = require("bundler")
--   Bundler.bundle({ entry="main", src="src/", out="dist/bundle.lua" })
--
-- CLI usage:
--   lua bundler.lua --entry main --src src/ --out dist/bundle.lua
--   lua bundler.lua --config bundler.config.lua
--   lua bundler.lua --help

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

	-- isolate CLI triggers
	local old_arg = _G.arg
	_G.arg = nil

	print("[bundler] verifying...")
	local ok, result = pcall(require, name)

	-- restore
	_G.arg = old_arg
	package.path = prev_path
	package.loaded[name] = nil

	if not ok then
		print("[bundler] verify failed: " .. tostring(result))
		return
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

-- Duplicated for LSP support

--- Bundle a Lua project. Config fields:
---  1. entry | string (required) | module name to use as entry
---  2. src | string | base directory (default: "./")
---  3. out | string | output file   (default: "./bundle.lua")
---  4. name | string | exported name (default: entry basename)
---  5. extra | string[] | additional modules to force-include
---  6. skip_extra_files_requires | boolean | include `extra` modules as-is without scanning their local require() calls
---  7. aliases | table { [from] = to } | require aliases
---  8. strip | string|boolean | false | "all" | "non_ann"
---  9. compact | boolean | compact output
---  10. resolve | boolean | resolve possible dynamic dependencies
---  11. debug | boolean | verbose discovery output
---  12. verify | boolean | load bundle after writing
---@param cfg table
---@return boolean
function Bundler.bundle(cfg)
	assert(type(cfg.entry) == "string" and cfg.entry ~= "", "cfg.entry must be a non-empty string")

	cfg.src = cfg.src or "./"
	cfg.out = cfg.out or "./bundle.lua"
	cfg.entry = Resolver.normalize_module_name(cfg.entry, cfg.src)

	print(string.format("[bundler] entry: `%s`  src: `%s`  out: `%s`", cfg.entry, cfg.src, cfg.out))

	local files, warnings = Discover.run(cfg.entry, cfg.src, {
		debug = cfg.debug,
		extra_names = cfg.extra,
		skip_extra_files_requires = cfg.skip_extra_files_requires,
	})

	print(string.format("[bundler] found %d module(s):", #files))
	for _, f in ipairs(files) do
		print(string.format(" [+] %s -> %s", f.name, f.path))
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
		error("fatal: " .. tostring(err) .. "\n", 0)
	end
end

if arg and arg[0] == debug.getinfo(1, "S").source:sub(2) then
	Bundler.run_cli(arg or {})
end

return Bundler

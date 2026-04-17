-- OneLua: bundle a Lua project into a single distributable file.
--
-- Library usage:
--   local Bundler = require("onelua")
--   Bundler.bundle({ entry="main", src="src/", out="dist/bundle.lua" })
--
-- CLI usage:
--   lua onelua.lua --entry main --src src/ --out dist/bundle.lua
--   lua onelua.lua --config bundler.config.lua
--   lua onelua.lua --help

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
---@param cfg BundlerConfig
---@return boolean
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

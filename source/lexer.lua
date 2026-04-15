-- Dumb lexer for static require analysis character-by-character
-- It's not the most effective, but it gets the job done
-- There will be a lot of comments

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

-- Returns the character at position (i + off) in src, or "" if out of bounds.
local function char_at(src, i, n, off)
	local j = i + (off or 0)
	return (j >= 1 and j <= n) and src:sub(j, j) or ""
end

-- Locates a long-bracket body in `src`.
-- `pos` must point to the character immediately AFTER the first opening `[`
-- (i.e. the start of the optional `=` run).
--
-- Returns 4 values on success:
--   content_start – first index of the bracket body
--   content_end   – last  index of the bracket body
--   next_pos      – first index after the closing bracket
--   closed        – false when no matching closer was found before EOF
--
-- Returns nil when the sequence at `pos` is not a valid long-bracket opener
-- (e.g. a bare `[` that is not followed by `=*[`).
local function long_bracket_span(src, pos, n)
	-- Count the run of `=` characters between the two `[` chars.
	local eq = 0
	local j = pos
	while j <= n and src:sub(j, j) == "=" do
		eq = eq + 1
		j = j + 1
	end

	-- A second `[` is required to close the opener.
	if j > n or src:sub(j, j) ~= "[" then
		return nil
	end

	local cs = j + 1 -- first content character
	local close = "]" .. string.rep("=", eq) .. "]" -- matching closing sequence
	local s, e = src:find(close, cs, true) -- plain-text search, no patterns

	-- When the closing bracket is absent we report the span as running to EOF
	-- and flag it so callers can emit a diagnostic.
	return cs, s and (s - 1) or n, s and (e + 1) or (n + 1), s ~= nil -- xD
end

-- Walks past a short-quoted string, starting at the character AFTER the
-- opening quote.  Returns three values:
--   parts  - table of raw content pieces (backslash escapes preserved verbatim)
--   new_i  – position after the closing quote, or after the last consumed
--             character if the string was unterminated
--   closed – true iff a matching closing quote was found
--
-- Escape sequences are kept intact (backslash + the following character), so
-- neither the tokeniser nor the stripper needs to interpret Lua's escape rules.
-- Lua 5.2+ sequences like \z, \xNN, \u{NNNN} pass through correctly because
-- we always consume exactly one character after the backslash.
--
-- On encountering a bare newline (illegal inside a short string) the walk stops
-- WITHOUT consuming it, leaving it for the outer loop to handle so that line
-- counters stay accurate.
local function scan_short_string(src, i, n, quote)
	local parts = {}
	while i <= n do
		local c = src:sub(i, i)
		if c == "\\" then
			-- Consume the backslash and the very next character as a single unit.
			local esc = (i + 1 <= n) and src:sub(i + 1, i + 1) or ""
			parts[#parts + 1] = "\\" .. esc
			i = i + 2
		elseif c == quote then
			return parts, i + 1, true -- closing quote consumed; string is done
		elseif c == "\n" or c == "\r" then
			return parts, i, false -- bare newline: unterminated short string
		else
			parts[#parts + 1] = c
			i = i + 1
		end
	end
	return parts, i, false -- reached EOF without a closing quote
end

function Lexer.tokenize(src)
	local tokens = {}
	local i, n, line = 1, #src, 1

	-- Thin closure so call sites read as ch() / ch(1) / ch(-1) etc.,
	-- rather than char_at(src, i, n, ...) everywhere.
	local function ch(off)
		return char_at(src, i, n, off)
	end

	-- Advance i by k characters, incrementing `line` at every newline crossed.
	-- Use when you know exactly how many source characters to consume.
	local function skip(k)
		for _ = 1, k or 1 do
			if src:sub(i, i) == "\n" then
				line = line + 1
			end
			i = i + 1
		end
	end

	-- Advance i up to (but not including) `target`, tracking newlines.
	-- Use after long_bracket_span returns a next_pos value.
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

		-- Whitespace
		if c:match("^%s$") then
			skip()

		-- Comments: --comment or --[[ block ]]
		elseif c == "-" and ch(1) == "-" then
			-- Peek two positions ahead: if we see "[" it might be a block-comment
			-- opener.  We call long_bracket_span without advancing i first; the
			-- offset +3 skips past the "--[" prefix arithmetically.
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
				-- If long_bracket_span returned nil then "--[" was not followed
				-- by a valid opener (e.g. "--[x"), so fall through to line comment.
			end
			if not is_block then
				-- Line comment: consume everything up to (not including) the newline.
				while i <= n and ch() ~= "\n" do
					skip()
				end
			end

		-- Long strings:  [[ ... ]]  or  [=[ ... ]=]  etc.
		elseif c == "[" and (ch(1) == "[" or ch(1) == "=") then
			-- Pass i+1 so long_bracket_span sees what follows the opening "[".
			-- We do NOT advance i before the call, which eliminates the
			-- save/restore of (i, line) that was previously needed.
			local cs, ce, next_pos, closed = long_bracket_span(src, i + 1, n)
			if cs then
				if not closed then
					print("[lexer]: unclosed long string at line " .. line)
				end
				push(T.STRING, src:sub(cs, ce)) -- content only, no bracket delimiters
				advance_to(next_pos)
			else
				-- Not a valid long-bracket opener; treat the bare "[" as OTHER.
				push(T.OTHER, "[")
				skip()
			end

		-- Short strings:  "..."  or  '...'
		elseif c == '"' or c == "'" then
			local q = c
			skip() -- consume the opening quote
			local parts, new_i = scan_short_string(src, i, n, q)
			-- Short strings cannot contain raw newlines, so we assign i directly
			-- instead of going through advance_to.  If the string was unterminated
			-- (new_i points at a newline), the outer loop handles it next iteration.
			i = new_i
			push(T.STRING, table.concat(parts))

		-- Dot family:  .  ..  ...
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

		-- Parentheses
		elseif c == "(" then
			push(T.LPAREN, "(")
			skip()
		elseif c == ")" then
			push(T.RPAREN, ")")
			skip()

		-- Numeric literals
		elseif c:match("^%d$") then
			if c == "0" and (ch(1) == "x" or ch(1) == "X") then
				-- Hexadecimal literal (0x… / 0X…).
				-- NOTE: we do not verify that at least one hex digit follows the
				-- prefix; an invalid input like `0x,` is silently accepted.
				-- We assume the source is valid Lua.
				skip(2) -- consume "0x" / "0X"
				while i <= n and ch():match("^%x$") do
					skip()
				end
			else
				-- Decimal: integer part.
				while i <= n and ch():match("^%d$") do
					skip()
				end
				-- Optional fractional part.  We require a digit after "." to
				-- avoid consuming the ".." concat operator.
				if ch() == "." and ch(1):match("^%d$") then
					skip()
					while i <= n and ch():match("^%d$") do
						skip()
					end
				end
				-- Optional exponent part.
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

		-- Identifiers and keywords
		elseif c:match("^[%a_]$") then
			local s = i
			while i <= n and ch():match("^[%w_]$") do
				skip()
			end
			push(T.IDENT, src:sub(s, i - 1))

		-- Anything else (operators, punctuation, …)
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

	---------------------------------------------------------------------------
	-- Pre-pass: build the set of identifiers that are aliases of `require`.
	--
	-- Recognises the pattern:  local X = require
	-- (without a following "(", which would mean require is being *called* and
	-- X receives its return value rather than the function itself.)
	--
	-- Limitation: only textually-prior, top-level assignments are detected.
	-- Aliases created inside conditionals or after a require call site will be
	-- missed.
	---------------------------------------------------------------------------
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
			-- Exclude `local x = require(...)` where require is being called
			-- and x receives the module, not the function.
			-- tokens[j+4] may be nil (past end of stream); Lua's `and`
			-- short-circuits so the nil index is safe without an explicit
			-- bounds check.
			local te = tokens[j + 4]
			if not (te and te.type == T.LPAREN) then
				req_idents[tb.value] = true
			end
		end
	end

	---------------------------------------------------------------------------
	-- fold_strings: collapse a (possibly parenthesised) static string
	-- concatenation starting at token index j into a single string.
	--
	-- Handles:
	--   "a"          -> "a"
	--   "a" .. "b"   -> "ab"
	--   ("a" .. "b") -> "ab"
	--
	-- Returns (value, next_j) on success, or (nil, start_j) when the
	-- expression is not fully static (contains variables, function calls, …).
	---------------------------------------------------------------------------
	local function fold_strings(j)
		local start = j
		local inner = tokens[j] and tokens[j].type == T.LPAREN

		if inner then
			j = j + 1
		end

		if not (tokens[j] and tokens[j].type == T.STRING) then
			return nil, start
		end

		local parts = { tokens[j].value }
		j = j + 1

		-- Consume any number of  `.. "more"`  continuations.
		while tokens[j] and tokens[j].type == T.CONCAT and tokens[j + 1] and tokens[j + 1].type == T.STRING do
			parts[#parts + 1] = tokens[j + 1].value
			j = j + 2
		end

		if inner then
			if not (tokens[j] and tokens[j].type == T.RPAREN) then
				return nil, start -- mismatched parentheses in expression
			end
			j = j + 1
		end

		return table.concat(parts), j
	end

	-- Main scan
	local i = 1
	while i <= n do
		local tk = tokens[i]

		if tk.type == T.IDENT and req_idents[tk.value] then
			local req_line = tk.line
			local next1 = tokens[i + 1]

			if next1 and next1.type == T.STRING then
				-- require "str"  (call without parentheses)
				results[#results + 1] = { kind = "static", value = next1.value, line = req_line }
				i = i + 2
			elseif next1 and next1.type == T.LPAREN then
				local arg_start = i + 2
				local value, next_j = fold_strings(arg_start)

				if value and tokens[next_j] and tokens[next_j].type == T.RPAREN then
					-- Fully static: require("mod"), require("a" .. "b"), require(("mod")), …
					results[#results + 1] = { kind = "static", value = value, line = req_line }
					i = next_j + 1
				else
					-- Dynamic argument: scan forward to the matching ")" and
					-- collect any string literals found as diagnostic hints.
					local j = arg_start
					local depth = 1
					-- first_str – first string literal in the argument
					-- last_str  – last string literal in the argument
					local first_str = nil
					local last_str = nil

					while j <= n do
						local t = tokens[j]
						if t.type == T.LPAREN then
							depth = depth + 1
						elseif t.type == T.RPAREN then
							depth = depth - 1
							if depth == 0 then
								break
							end
						elseif t.type == T.STRING then
							first_str = first_str or t.value
							last_str = t.value
						end
						j = j + 1
					end

					results[#results + 1] = {
						kind = "dynamic",
						hint = first_str,
						-- Only record hint_trail when it differs from hint.
						hint_trail = (last_str ~= first_str) and last_str or nil,
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
	local pending = false -- true when a blank-line gap follows the last emitted line

	-- The pattern "([^\n]*)(\n?)" splits src into (line-content, newline) pairs.
	-- It produces one extra empty-pair at EOF; we break out of the loop there.
	for line, nl in src:gmatch("([^\n]*)(\n?)") do
		if line == "" and nl == "" then
			break
		end

		line = line:gsub("[ \t]+$", "") -- strip trailing whitespace

		if line ~= "" then
			-- If at least one blank line preceded this non-blank line (and we
			-- have already emitted something), insert a single blank separator.
			if pending and #lines > 0 then
				lines[#lines + 1] = "\n"
			end
			lines[#lines + 1] = line
			-- A newline after this line means the *next* thing might be blank.
			pending = nl == "\n"
		elseif nl ~= "" then
			-- Blank line: mark a pending gap, but only after at least one
			-- non-blank line has been emitted to avoid leading blank lines.
			pending = pending or (#lines > 0)
		end
	end

	return table.concat(lines)
end

function Lexer.strip(src, opts)
	opts = opts or {}
	local keep_ann = opts.keep_annotations or false
	local keep_module = opts.keep_module or false
	local compact = opts.compact ~= false -- TODO: wire through config

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

	-- Emit a short-quoted string verbatim, including surrounding quotes.
	local function copy_short_string()
		local q = ch()
		emit(q) -- opening quote
		adv() -- consume it
		local parts, new_i, closed = scan_short_string(src, i, n, q)
		for _, p in ipairs(parts) do
			emit(p)
		end
		if closed then
			emit(q)
		end -- matching closing quote
		i = new_i
	end

	while i <= n do
		local c = ch()

		-- Comments
		if c == "-" and ch(1) == "-" then
			-- Check for a block comment.  Offset +3 positions past "--["
			-- without mutating i.
			local is_block = false
			if ch(2) == "[" then
				local cs, _, next_pos, closed = long_bracket_span(src, i + 3, n)
				if cs then
					if not closed then
						print("[lexer]: unclosed block comment")
					end

					-- The comment body is dropped, but we must preserve its
					-- newline count so that subsequent line numbers stay accurate.
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
				-- If long_bracket_span returned nil then "--[" was not a valid
				-- opener, so fall through to the line-comment path below.
			end

			if not is_block then
				-- Line comment: consume to (not including) the newline, then
				-- decide whether to retain it based on annotation options.
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
				-- Otherwise the comment is silently dropped.
			end

		-- Long strings
		elseif c == "[" and (ch(1) == "[" or ch(1) == "=") then
			local cs, _, next_pos, closed = long_bracket_span(src, i + 1, n)
			if cs then
				if not closed then
					print("[lexer]: unclosed long string")
				end
				-- Long strings are content, not comments; copy verbatim
				-- including the surrounding bracket delimiters.
				emit(src:sub(i, next_pos - 1))
				i = next_pos
			else
				-- Not a valid opener; emit "[" literally.
				emit(c)
				adv()
			end

		-- Short strings
		elseif c == '"' or c == "'" then
			copy_short_string()

		-- Everything else: pass through as-is
		else
			emit(c)
			adv()
		end
	end

	local result = table.concat(out)
	return compact and compact_lines(result) or result
end

return Lexer

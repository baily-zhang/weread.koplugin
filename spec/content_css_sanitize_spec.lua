package.path = "./?.lua;./?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message or ("check " .. checks .. " failed")) end
end

package.preload["logger"] = function()
    return {
        info = function() end,
        warn = function() end,
        err = function() end,
        dbg = function() end,
    }
end
package.preload["weread.lib.crypto"] = function() return {} end
package.preload["weread.lib.reader_state"] = function() return {} end
package.preload["weread.lib.protocol"] = function() return {} end
package.preload["weread.lib.thoughts"] = function() return {} end

local Content = require("weread/lib/content")

-- The hostile rule observed in real WeRead e_2 shards: crengine honors the
-- root-element zero sizing and p{font-size:1rem} then collapses the whole book.
local hostile = "html,\nbody {\n  margin: 0;\n  padding: 0;\n  font-size: 0;\n  }"
local cleaned, count = Content.sanitize_book_css(hostile)
expect(count == 1, "the single font-size:0 declaration must be reported as one removal")
expect(not cleaned:find("font%-size"), "font-size:0 declaration survived sanitization")
expect(cleaned:find("{", 1, true) and cleaned:find("}", 1, true),
    "sanitization must keep the rule braces intact")
expect(cleaned:find("margin: 0;", 1, true) and cleaned:find("padding: 0;", 1, true),
    "sibling margin/padding declarations must survive sanitization")

cleaned, count = Content.sanitize_book_css(".a{font-size: 0 !important;color:red}")
expect(count == 1 and not cleaned:find("font%-size"),
    "!important zero font-size was not removed")
expect(cleaned:find("color:red", 1, true),
    "declaration after the removed !important rule was damaged")

cleaned, count = Content.sanitize_book_css("p{font-size: 0px}h1{font-size: 0%;}")
expect(count == 2 and not cleaned:find("font%-size"),
    "zero font-size with px/% units was not fully removed")

cleaned, count = Content.sanitize_book_css(".fs05 { font-size: 0.5rem; }")
expect(count == 0 and cleaned == ".fs05 { font-size: 0.5rem; }",
    "fractional font-size must stay untouched")

cleaned, count = Content.sanitize_book_css("p { font-size: 1rem; }")
expect(count == 0 and cleaned == "p { font-size: 1rem; }",
    "non-zero font-size must stay untouched")

cleaned, count = Content.sanitize_book_css("{ color: #000; font-size: 0\n}")
expect(count == 1, "trailing font-size:0 without semicolon was not detected")
expect(cleaned:sub(-1) == "}", "removal must keep the closing brace of the block")
expect(cleaned:find("color: #000;", 1, true), "sibling color declaration was damaged")

local passthrough, passthrough_count = Content.sanitize_book_css(nil)
expect(passthrough == nil and passthrough_count == 0,
    "nil input must pass through unchanged with count 0")
passthrough, passthrough_count = Content.sanitize_book_css("")
expect(passthrough == "" and passthrough_count == 0,
    "empty input must pass through unchanged with count 0")

-- Integration-style: sanitizing an already-sanitized shard changes nothing.
local combined = table.concat({
    hostile,
    ".a{font-size: 0 !important;color:red}",
    "p{font-size: 0px}h1{font-size: 0%;}",
    "{ color: #000; font-size: 0\n}",
}, "\n")
local once, first_count = Content.sanitize_book_css(combined)
local twice, second_count = Content.sanitize_book_css(once)
expect(first_count == 5, "combined shard should lose five zero font-size declarations")
expect(second_count == 0 and twice == once, "sanitization must be idempotent")

-- Adjacent zero declarations: each pass consumes one boundary character, so
-- the sanitizer must iterate to a fixpoint instead of keeping the second one.
cleaned, count = Content.sanitize_book_css("p{font-size:0;font-size:0}")
expect(count == 2, "adjacent zero declarations must both be removed")
expect(not cleaned:find("font%-size"), "adjacent removal left a hostile declaration behind")
expect(cleaned:find("^p%{.*%}$"), "block structure was damaged by adjacent removal")

cleaned, count = Content.sanitize_book_css("p{font-size:0 ;font-size:0 ;color:red}")
expect(count == 2 and cleaned:find("color:red", 1, true),
    "spaced adjacent zeros must be removed while siblings survive")

cleaned, count = Content.sanitize_book_css("html,body{font-size:0vh}")
expect(count == 1 and not cleaned:find("font%-size"),
    "zero with any letter unit (0vh) is a zero length and must be removed")

-- A CSS comment carrying the exact declaration may lose its interior, but the
-- stylesheet structure around it must survive and the result stays idempotent.
local commented = "p{ /* font-size: 0 ; old */ color:blue }"
cleaned, count = Content.sanitize_book_css(commented)
local open_braces = select(2, cleaned:gsub("%{", ""))
local close_braces = select(2, cleaned:gsub("}", ""))
expect(cleaned:find("color:blue", 1, true) and open_braces == close_braces,
    "comment rewrite must keep the block structurally valid")
local _, recount = Content.sanitize_book_css(cleaned)
expect(recount == 0, "sanitization after comment rewrite must be idempotent")

print(("content_css_sanitize_spec: %d checks"):format(checks))

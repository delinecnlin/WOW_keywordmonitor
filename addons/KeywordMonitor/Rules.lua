WOWKeywordMonitor = WOWKeywordMonitor or {}
local WKM = WOWKeywordMonitor

local Rules = {}
WKM.Rules = Rules

local cache = {}

local function mergeTerms(a, b)
    local out, seen = {}, {}
    for _, list in ipairs({ a or {}, b or {} }) do
        for _, term in ipairs(list) do
            local key = tostring(term):lower()
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = term
            end
        end
    end
    return out
end

local function evaluate(node, text)
    if node.kind == "term" then
        if text:find(node.value:lower(), 1, true) then
            return true, { node.value }
        end
        return false, {}
    end

    if node.kind == "not" then
        local matched = evaluate(node.child, text)
        return not matched, {}
    end

    if node.kind == "and" then
        local leftOK, leftTerms = evaluate(node.left, text)
        if not leftOK then return false, {} end
        local rightOK, rightTerms = evaluate(node.right, text)
        if not rightOK then return false, {} end
        return true, mergeTerms(leftTerms, rightTerms)
    end

    if node.kind == "or" then
        local leftOK, leftTerms = evaluate(node.left, text)
        local rightOK, rightTerms = evaluate(node.right, text)
        if not leftOK and not rightOK then return false, {} end
        return true, mergeTerms(leftOK and leftTerms or {}, rightOK and rightTerms or {})
    end

    return false, {}
end

function Rules.Validate(expression)
    local _, err = WKM.Parser.Parse(expression or "")
    return err == nil, err
end

function Rules.ClearCache()
    for key in pairs(cache) do cache[key] = nil end
end

function Rules.Match(rule, message)
    if not rule or not rule.expression or not message then return false, {} end
    local key = tostring(rule.id or "?") .. ":" .. rule.expression
    local tree = cache[key]
    if not tree then
        local err
        tree, err = WKM.Parser.Parse(rule.expression)
        if not tree then return false, {}, err end
        cache[key] = tree
    end
    return evaluate(tree, message:lower())
end

function Rules.Sanitize(message)
    local text = tostring(message or "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

function Rules.Highlight(message, terms)
    local text = Rules.Sanitize(message)
    if not terms or #terms == 0 then return text end

    local lower = text:lower()
    local spans = {}

    for _, term in ipairs(terms) do
        local needle = tostring(term or ""):lower()
        if needle ~= "" then
            local from = 1
            while true do
                local s, e = lower:find(needle, from, true)
                if not s then break end
                spans[#spans + 1] = { s = s, e = e }
                from = e + 1
            end
        end
    end

    table.sort(spans, function(a, b)
        if a.s == b.s then return a.e > b.e end
        return a.s < b.s
    end)

    local chosen, lastEnd = {}, 0
    for _, span in ipairs(spans) do
        if span.s > lastEnd then
            chosen[#chosen + 1] = span
            lastEnd = span.e
        end
    end

    if #chosen == 0 then return text end

    local out, cursor = {}, 1
    for _, span in ipairs(chosen) do
        if span.s > cursor then
            out[#out + 1] = text:sub(cursor, span.s - 1)
        end
        out[#out + 1] = "|cff00ff88" .. text:sub(span.s, span.e) .. "|r"
        cursor = span.e + 1
    end
    if cursor <= #text then out[#out + 1] = text:sub(cursor) end

    return table.concat(out)
end

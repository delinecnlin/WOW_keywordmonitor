WOWKeywordMonitor = WOWKeywordMonitor or {}
local WKM = WOWKeywordMonitor

local Parser = {}
WKM.Parser = Parser

local function tokenize(expr)
    local tokens, i, n = {}, 1, #(expr or "")
    while i <= n do
        local c = expr:sub(i, i)
        if c:match("%s") then
            i = i + 1
        elseif c == "(" then
            tokens[#tokens + 1] = { type = "LPAREN" }
            i = i + 1
        elseif c == ")" then
            tokens[#tokens + 1] = { type = "RPAREN" }
            i = i + 1
        elseif c == "!" then
            tokens[#tokens + 1] = { type = "NOT" }
            i = i + 1
        elseif expr:sub(i, i + 1) == "&&" then
            tokens[#tokens + 1] = { type = "AND" }
            i = i + 2
        elseif expr:sub(i, i + 1) == "||" then
            tokens[#tokens + 1] = { type = "OR" }
            i = i + 2
        elseif c == "\"" or c == "'" then
            local quote, parts = c, {}
            i = i + 1
            while i <= n and expr:sub(i, i) ~= quote do
                parts[#parts + 1] = expr:sub(i, i)
                i = i + 1
            end
            if i > n then return nil, "引号未闭合" end
            i = i + 1
            local value = table.concat(parts)
            if value == "" then return nil, "关键词不能为空" end
            tokens[#tokens + 1] = { type = "TERM", value = value }
        else
            local start = i
            while i <= n do
                local x = expr:sub(i, i)
                if x:match("%s") or x == "(" or x == ")" or x == "!" then break end
                if expr:sub(i, i + 1) == "&&" or expr:sub(i, i + 1) == "||" then break end
                i = i + 1
            end
            local word = expr:sub(start, i - 1)
            local upper = word:upper()
            if upper == "AND" then
                tokens[#tokens + 1] = { type = "AND" }
            elseif upper == "OR" then
                tokens[#tokens + 1] = { type = "OR" }
            elseif upper == "NOT" then
                tokens[#tokens + 1] = { type = "NOT" }
            elseif word ~= "" then
                tokens[#tokens + 1] = { type = "TERM", value = word }
            end
        end
    end
    tokens[#tokens + 1] = { type = "EOF" }
    return tokens
end

function Parser.Parse(expr)
    local tokens, err = tokenize(expr)
    if not tokens then return nil, err end
    if #tokens == 1 then return nil, "规则不能为空" end

    local pos = 1
    local function peek() return tokens[pos] end
    local function take(kind)
        if peek() and peek().type == kind then
            local t = peek()
            pos = pos + 1
            return t
        end
    end
    local function startsPrimary(t)
        return t and (t.type == "TERM" or t.type == "LPAREN" or t.type == "NOT")
    end

    local parseOr, parseAnd, parseUnary, parsePrimary

    parsePrimary = function()
        local term = take("TERM")
        if term then return { kind = "term", value = term.value } end
        if take("LPAREN") then
            local node, e = parseOr()
            if not node then return nil, e end
            if not take("RPAREN") then return nil, "缺少右括号 )" end
            return node
        end
        return nil, "此处需要关键词或左括号"
    end

    parseUnary = function()
        if take("NOT") then
            local child, e = parseUnary()
            if not child then return nil, e end
            return { kind = "not", child = child }
        end
        return parsePrimary()
    end

    parseAnd = function()
        local left, e = parseUnary()
        if not left then return nil, e end
        while true do
            if take("AND") then
                local right, re = parseUnary()
                if not right then return nil, re or "AND 后缺少条件" end
                left = { kind = "and", left = left, right = right }
            elseif startsPrimary(peek()) then
                local right, re = parseUnary()
                if not right then return nil, re end
                left = { kind = "and", left = left, right = right }
            else
                break
            end
        end
        return left
    end

    parseOr = function()
        local left, e = parseAnd()
        if not left then return nil, e end
        while take("OR") do
            local right, re = parseAnd()
            if not right then return nil, re or "OR 后缺少条件" end
            left = { kind = "or", left = left, right = right }
        end
        return left
    end

    local tree, parseErr = parseOr()
    if not tree then return nil, parseErr end
    if peek() and peek().type ~= "EOF" then return nil, "规则末尾有无法解析的内容" end
    return tree
end

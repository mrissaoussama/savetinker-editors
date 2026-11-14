-- Reads JSON text into a tree that remembers where each value sits, so edits can replace
-- just that value and leave the rest of the file untouched.
local scan = {}

local function fail(pos, message)
    error({ scan = true, message = message .. " at byte " .. pos }, 0)
end

local function skip(text, pos)
    return text:find("[^ \t\r\n]", pos) or #text + 1
end

local value

local function stringEnd(text, pos)
    local i = pos + 1
    while true do
        local stop = text:find('["\\]', i)
        if not stop then fail(pos, "unterminated string") end
        if text:sub(stop, stop) == '"' then return stop end
        i = stop + 2
    end
end

local function object(text, pos)
    local node = { kind = "object", start = pos, children = {} }
    pos = skip(text, pos + 1)
    if text:sub(pos, pos) == "}" then node.stop = pos return node, pos + 1 end
    while true do
        if text:sub(pos, pos) ~= '"' then fail(pos, "expected a key") end
        local keyEnd = stringEnd(text, pos)
        local key = st.json.decode(text:sub(pos, keyEnd))
        pos = skip(text, keyEnd + 1)
        if text:sub(pos, pos) ~= ":" then fail(pos, "expected ':'") end
        local child
        child, pos = value(text, skip(text, pos + 1))
        node.children[#node.children + 1] = { key = key, node = child }
        pos = skip(text, pos)
        local c = text:sub(pos, pos)
        if c == "}" then node.stop = pos return node, pos + 1 end
        if c ~= "," then fail(pos, "expected ',' or '}'") end
        pos = skip(text, pos + 1)
    end
end

local function array(text, pos)
    local node = { kind = "array", start = pos, children = {} }
    pos = skip(text, pos + 1)
    if text:sub(pos, pos) == "]" then node.stop = pos return node, pos + 1 end
    while true do
        local child
        child, pos = value(text, pos)
        node.children[#node.children + 1] = { key = #node.children, node = child }
        pos = skip(text, pos)
        local c = text:sub(pos, pos)
        if c == "]" then node.stop = pos return node, pos + 1 end
        if c ~= "," then fail(pos, "expected ',' or ']'") end
        pos = skip(text, pos + 1)
    end
end

function value(text, pos)
    local c = text:sub(pos, pos)
    if c == "{" then return object(text, pos) end
    if c == "[" then return array(text, pos) end
    local stop
    local kind
    if c == '"' then
        stop, kind = stringEnd(text, pos), "string"
    else
        local literal = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
        if literal and #literal > 0 then
            stop, kind = pos + #literal - 1, "number"
        else
            for word, wordKind in pairs({ ["true"] = "bool", ["false"] = "bool", ["null"] = "null" }) do
                if text:sub(pos, pos + #word - 1) == word then stop, kind = pos + #word - 1, wordKind end
            end
        end
    end
    if not stop then fail(pos, "unexpected character") end
    local raw = text:sub(pos, stop)
    local node = { kind = kind, start = pos, stop = stop }
    if kind ~= "null" then
        local ok, decoded = pcall(st.json.decode, raw)
        if ok then node.value = decoded
        elseif kind == "string" then node.kind, node.value = "binary", raw
        else fail(pos, "bad " .. kind) end
    end
    node.float = kind == "number" and raw:find("[.eE]") ~= nil
    return node, stop + 1
end

-- Returns the tree, or nil and a reason.
function scan.parse(text)
    local first = skip(text, text:sub(1, 3) == "\239\187\191" and 4 or 1)
    local c = text:sub(first, first)
    if c ~= "{" and c ~= "[" then return nil, "not JSON" end
    local ok, tree, pos = pcall(value, text, first)
    if not ok then
        if type(tree) == "table" and tree.scan then return nil, tree.message end
        error(tree, 0)
    end
    if skip(text, pos) <= #text then return nil, "text after the JSON value" end
    return tree
end

-- Finds a value again after an edit moved things, following the same keys.
function scan.find(tree, path)
    local node = tree
    for _, key in ipairs(path) do
        local found
        for _, child in ipairs(node.children or {}) do
            if child.key == key then found = child.node break end
        end
        if not found then return nil end
        node = found
    end
    return node
end

return scan

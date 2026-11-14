local scan = require("scan")

local MAX_ROWS = 400
local MAX_SIZE = 4 * 1024 * 1024

local function jsonFiles(save)
    local found = {}
    for _, name in ipairs(save:files()) do
        local file = save:file(name)
        if file:size() > 0 and file:size() <= MAX_SIZE and scan.parse(file:content()) then
            found[#found + 1] = name
        end
    end
    return found
end

function detect(save)
    if #jsonFiles(save) == 0 then return false, "No file in this save is plain JSON text." end
    return true
end

local function encode(node, value)
    if node.kind == "bool" then return value and "true" or "false" end
    if node.kind == "number" and not node.float then return string.format("%d", math.tointeger(value) or math.floor(value)) end
    return st.json.encode(value)
end

-- Each edit parses the current text again and replaces only the bytes of that value.
local function binding(file, path, node)
    return st.bind(function() return node.value end, function(value)
        local current = scan.find(scan.parse(file:content()), path)
        if not current then error("the value moved, reopen the editor") end
        file:splice(current.start - 1, current.stop - current.start + 1, encode(current, value))
    end)
end

local function childPath(path, key)
    local copy = { table.unpack(path) }
    copy[#copy + 1] = key
    return copy
end

local function label(key)
    return type(key) == "number" and "[" .. key .. "]" or key
end

local function describe(node)
    local count = #node.children
    return node.kind == "array" and count .. " items" or count .. " fields"
end

local fill

local function widget(page, file, key, path, node)
    local id = table.concat(path, "/")
    local name = label(key)
    if node.kind == "object" or node.kind == "array" then
        page:page({ title = name .. "  (" .. describe(node) .. ")", key = id }, function(sub) fill(sub, file, path, node) end)
    elseif node.kind == "bool" then
        page:toggle{ label = name, key = id, bind = binding(file, path, node) }
    elseif node.kind == "number" then
        local spec = { label = name, key = id, bind = binding(file, path, node) }
        if node.float then page:float(spec) else page:int(spec) end
    elseif node.kind == "string" then
        page:text{ label = name, key = id, bind = binding(file, path, node), max_length = math.max(256, #node.value * 2) }
    elseif node.kind == "binary" then
        page:label{ label = name, key = id, value = node.value, help = "Not valid UTF-8 text, shown as stored" }
    else
        page:label{ label = name, key = id, value = "null" }
    end
end

function fill(page, file, path, node)
    if #node.children == 0 then page:note("Empty.") end
    for i, child in ipairs(node.children) do
        if i > MAX_ROWS then
            page:note((#node.children - MAX_ROWS) .. " more entries are not shown.")
            break
        end
        widget(page, file, child.key, childPath(path, child.key), child.node)
    end
end

function build(ui, save)
    local names = jsonFiles(save)
    for _, name in ipairs(names) do
        local file = save:file(name)
        local tree = scan.parse(file:content())
        ui:page({ title = name, key = name }, function(page)
            page:note("Keys and formatting stay as they are; only the values you change are rewritten.")
            fill(page, file, {}, tree)
        end)
    end
end

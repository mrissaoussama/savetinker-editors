local scan = require("scan")
local codec = require("codec")

local PARAMS = { "Max HP", "Max MP", "Attack", "Defense", "M. Attack", "M. Defense", "Agility", "Luck" }

local function join(path, ...)
    local result = { table.unpack(path) }
    for _, key in ipairs({ ... }) do result[#result + 1] = key end
    return result
end

local function saveFiles(save)
    local found = {}
    for _, name in ipairs(save:files()) do
        local base = name:match("[^/]+$"):lower()
        if codec.kind(name) and base ~= "config.rpgsave" and base ~= "config.rmmzsave"
            and base ~= "global.rpgsave" and base ~= "global.rmmzsave" then
            found[#found + 1] = name
        end
    end
    table.sort(found, function(a, b)
        local x, y = tonumber(a:match("(%d+)%.")), tonumber(b:match("(%d+)%."))
        if x and y then return x < y end
        return a < b
    end)
    return found
end

-- Decoding is cached by file content: the screen is rebuilt after every change.
local cache = {}

local function load(file, name)
    local raw = file:content()
    local hit = cache[name]
    if hit and hit.raw == raw then return hit end
    local text, format = codec.decode(name, raw)
    if not text then return nil, format end
    local tree, reason = scan.parse(text)
    if not tree then return nil, reason end
    hit = { raw = raw, text = text, format = format, tree = tree }
    cache[name] = hit
    return hit
end

local function store(file, doc, text)
    file:setContent(codec.encode(text, doc.format))
end

local function encodeValue(node, value)
    if type(value) == "boolean" then return value and "true" or "false" end
    if type(value) == "number" and (math.type(value) == "integer" or (not node.float and value == math.floor(value))) then
        return string.format("%d", math.floor(value))
    end
    return st.json.encode(value)
end

local function bind(file, name, path, fallback)
    return st.bind(function()
        local doc = load(file, name)
        local node = doc and scan.find(doc.tree, path)
        if not node or node.value == nil then return fallback end
        return node.value
    end, function(value)
        local doc = assert(load(file, name))
        local node = scan.find(doc.tree, path)
        if not node then error("this value is no longer in the save") end
        store(file, doc, doc.text:sub(1, node.start - 1) .. encodeValue(node, value) .. doc.text:sub(node.stop + 1))
    end)
end

-- Newer MV versions write some arrays as {"@a": [...]}.
local function child(node, path, key)
    local found = node and scan.find(node, { key })
    if not found then return nil end
    local nextPath = { table.unpack(path) }
    nextPath[#nextPath + 1] = key
    local inner = found.kind == "object" and scan.find(found, { "@a" })
    if inner then
        nextPath[#nextPath + 1] = "@a"
        found = inner
    end
    return found, nextPath
end

local function gameList(file)
    local ok, text = pcall(st.game_data.read, file, true)
    if not ok or not text then return nil end
    local ok2, value = pcall(st.json.decode, text)
    return ok2 and value or nil
end

local function names(file)
    local list = gameList(file)
    local result = {}
    if type(list) ~= "table" then return result end
    for index, entry in pairs(list) do
        if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then result[index - 1] = entry.name end
    end
    return result
end

local data
local function gameData()
    if data then return data end
    local system = gameList("System.json") or {}
    local function indexed(list)
        local result = {}
        for i, value in ipairs(type(list) == "table" and list or {}) do
            if type(value) == "string" and value ~= "" then result[i - 1] = value end
        end
        return result
    end
    data = {
        title = system.gameTitle, currency = system.currencyUnit,
        switches = indexed(system.switches), variables = indexed(system.variables),
        items = names("Items.json"), weapons = names("Weapons.json"), armors = names("Armors.json"), classes = names("Classes.json"),
    }
    return data
end

function detect(save)
    for _, name in ipairs(saveFiles(save)) do
        if load(save:file(name), name) then return true end
    end
    return false, "No RPG Maker MV or MZ save file (file1.rpgsave, file1.rmmzsave)."
end

local function insertEntry(file, name, path, key, value)
    local doc = assert(load(file, name))
    local node = scan.find(doc.tree, path)
    if not node or node.kind ~= "object" then error("cannot add here") end
    local entry = st.json.encode(tostring(key)) .. ":" .. value
    if #node.children > 0 then entry = "," .. entry end
    store(file, doc, doc.text:sub(1, node.stop - 1) .. entry .. doc.text:sub(node.stop))
end

local function inventory(page, ctx, title, key, labels, kindName)
    local node, path = child(ctx.party, ctx.partyPath, key)
    if not node or node.kind ~= "object" then return end
    page:section({ title = title .. " (" .. #node.children .. ")", key = key }, function(section)
        local owned = {}
        for _, entry in ipairs(node.children) do
            local id = tonumber(entry.key)
            owned[entry.key] = true
            section:int{ label = labels[id] or (kindName .. " " .. entry.key), key = key .. "/" .. entry.key,
                         bind = bind(ctx.file, ctx.name, join(path, entry.key), 0), min = 0, max = 9999 }
        end
        local options = {}
        for id, label in pairs(labels) do
            if not owned[tostring(id)] then options[#options + 1] = { value = id, label = label } end
        end
        table.sort(options, function(a, b) return a.value < b.value end)
        if #options > 0 then
            local pick = ctx.state(key .. "-pick", options[1].value)
            section:dropdown{ label = "New " .. kindName:lower(), key = key .. "/pick", bind = pick, options = options,
                actions = { { label = "Add", run = function() insertEntry(ctx.file, ctx.name, path, pick:get(), "1") end } } }
        end
    end)
end

local function actorPage(page, ctx, actor, path)
    local d = gameData()
    local function field(key) return join(path, key) end
    local function value(key)
        local node = scan.find(actor, { key })
        return node and node.value
    end
    local classId = value("_classId")
    page:section({ title = tostring(value("_name") or "Actor"), key = table.concat(path, "/") }, function(s)
        s:text{ label = "Name", key = "name", bind = bind(ctx.file, ctx.name, field("_name"), ""), max_length = 64 }
        s:text{ label = "Nickname", key = "nick", bind = bind(ctx.file, ctx.name, field("_nickname"), ""), max_length = 64 }
        if next(d.classes) and classId then
            local options = {}
            for id, label in pairs(d.classes) do options[#options + 1] = { value = id, label = label } end
            table.sort(options, function(a, b) return a.value < b.value end)
            s:dropdown{ label = "Class", key = "class", bind = bind(ctx.file, ctx.name, field("_classId"), 1), options = options }
        end
        s:int{ label = "Level", key = "level", bind = bind(ctx.file, ctx.name, field("_level"), 1), min = 1, max = 99 }
        if classId and scan.find(actor, { "_exp", tostring(classId) }) then
            s:int{ label = "Experience", key = "exp", bind = bind(ctx.file, ctx.name, join(path, "_exp", tostring(classId)), 0), min = 0 }
        end
        s:int{ label = "HP", key = "hp", bind = bind(ctx.file, ctx.name, field("_hp"), 0), min = 0 }
        s:int{ label = "MP", key = "mp", bind = bind(ctx.file, ctx.name, field("_mp"), 0), min = 0 }
        s:int{ label = "TP", key = "tp", bind = bind(ctx.file, ctx.name, field("_tp"), 0), min = 0, max = 100 }
        local plus = scan.find(actor, { "_paramPlus" })
        if plus and plus.kind == "array" then
            s:section({ title = "Bonus stats", key = "plus", collapsed = true }, function(bonus)
                for i, entry in ipairs(plus.children) do
                    bonus:int{ label = PARAMS[i] or ("Stat " .. i), key = "p" .. i,
                               bind = bind(ctx.file, ctx.name, join(path, "_paramPlus", entry.key), 0) }
                end
            end)
        end
    end)
end

local function flagList(page, ctx, key, labels, kindName, widget)
    local container, containerPath = child(ctx.root, {}, key)
    local list, path = child(container, containerPath, "_data")
    if not list or list.kind ~= "array" then
        page:note("No " .. kindName:lower() .. "es in this save.")
        return
    end
    local showAll = ctx.state(key .. "-all", not next(labels))
    page:toggle{ label = "Show unnamed", key = key .. "/all", bind = showAll }
    for _, entry in ipairs(list.children) do
        local index = entry.key
        local label = labels[index]
        if index > 0 and (label or showAll:get()) then
            widget(page, (label and (index .. "  " .. label)) or (kindName .. " " .. index), join(path, index), entry.node)
        end
    end
end

function build(ui, save)
    local files = saveFiles(save)
    local valid = {}
    for _, name in ipairs(files) do
        if load(save:file(name), name) then valid[#valid + 1] = name end
    end
    if #valid == 0 then return end
    local slot = ui:state("slot", valid[1])
    local name = slot:get()
    if not save:has(name) then name = valid[1] end
    local file = save:file(name)
    local doc = load(file, name)
    local d = gameData()
    local ctx = { file = file, name = name, root = doc.tree, state = function(key, default) return ui:state(key, default) end }
    ctx.party, ctx.partyPath = child(doc.tree, {}, "party")

    local function slotPicker(page)
        if #valid <= 1 then return end
        local options = {}
        for _, file in ipairs(valid) do options[#options + 1] = { value = file, label = file } end
        page:dropdown{ label = "Save file", key = "slot", bind = slot, options = options }
    end

    ui:page("Party", function(page)
        slotPicker(page)
        if d.title then page:label{ label = "Game", value = d.title } end
        if not ctx.party then
            page:warning("This save has no party data.")
            return
        end
        page:int{ label = "Gold" .. (d.currency and d.currency ~= "" and (" (" .. d.currency .. ")") or ""), key = "gold",
                  bind = bind(file, name, join(ctx.partyPath, "_gold"), 0), min = 0, max = 99999999, step = 100 }
        page:int{ label = "Steps", key = "steps", bind = bind(file, name, join(ctx.partyPath, "_steps"), 0), min = 0 }
        inventory(page, ctx, "Items", "_items", d.items, "Item")
        inventory(page, ctx, "Weapons", "_weapons", d.weapons, "Weapon")
        inventory(page, ctx, "Armor", "_armors", d.armors, "Armor")
        if not next(d.items) then page:note("Item names come from the game's data folder; add the game folder's save to see them.") end
    end)

    ui:page("Actors", function(page)
        slotPicker(page)
        local actors, actorsPath = child(doc.tree, {}, "actors")
        local list, path = child(actors, actorsPath, "_data")
        if not list then
            page:note("No actors in this save.")
            return
        end
        for _, entry in ipairs(list.children) do
            if entry.node.kind == "object" then actorPage(page, ctx, entry.node, join(path, entry.key)) end
        end
    end)

    ui:page("Switches", function(page)
        slotPicker(page)
        flagList(page, ctx, "switches", d.switches, "Switch", function(p, label, path, node)
            p:toggle{ label = label, key = "s" .. path[#path], bind = bind(file, name, path, false) }
        end)
    end)

    ui:page("Variables", function(page)
        slotPicker(page)
        flagList(page, ctx, "variables", d.variables, "Variable", function(p, label, path, node)
            local key = "v" .. path[#path]
            if node.kind == "string" then
                p:text{ label = label, key = key, bind = bind(file, name, path, ""), max_length = 256 }
            elseif node.kind == "number" and node.float then
                p:float{ label = label, key = key, bind = bind(file, name, path, 0) }
            elseif node.kind == "number" or node.kind == "null" then
                p:int{ label = label, key = key, bind = bind(file, name, path, 0) }
            else
                p:label{ label = label, key = key, value = node.kind }
            end
        end)
    end)

    ui:page("Other", function(page)
        slotPicker(page)
        local system, systemPath = child(doc.tree, {}, "system")
        local frames = system and scan.find(system, { "_framesOnSave" })
        if frames and frames.value then
            local seconds = frames.value // 60
            page:label{ label = "Play time", value = string.format("%d:%02d:%02d", seconds // 3600, seconds // 60 % 60, seconds % 60) }
        end
        if system and scan.find(system, { "_saveCount" }) then
            page:int{ label = "Times saved", key = "saves", bind = bind(file, name, join(systemPath, "_saveCount"), 0), min = 0 }
        end
        local map = child(doc.tree, {}, "map")
        local mapId = map and scan.find(map, { "_mapId" })
        if mapId then page:label{ label = "Map", value = tostring(mapId.value) } end
        page:note("Changes are written back in the same format the game used (MV or MZ).")
    end)
end

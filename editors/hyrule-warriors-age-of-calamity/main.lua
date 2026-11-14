-- Ported from Marc Robledo's Hyrule Warriors: Age of Calamity save editor (MIT):
-- https://github.com/marcrobledo/savegame-editors
local SAVE_SIZE = 1048576
local RUPEES = 0x2c3a4
local MATERIALS = 0x2c14e
local DISCOVERED = 0x2c2dd
local CHARACTERS = 0x2bcad
local CHARACTER_SIZE = 30

local tables = st.json.decode(st.data("data/tables.json"))

local function saveFile(save)
    for _, name in ipairs(save:files()) do
        if name:match("svdt$") and save:file(name):size() == SAVE_SIZE then return save:file(name) end
    end
end

function detect(save)
    return saveFile(save) ~= nil, "Expected an svdt save of 1 MB."
end

-- Adding a material the save has never seen also marks it as discovered, as the game would.
local function materialBinding(file, material)
    local at = MATERIALS + material.index * 2
    return st.bind(function() return file:u16(at) end, function(count)
        if file:u16(at) == 0 and count > 0 then file:set(DISCOVERED + material.index, "u8", 1) end
        file:set(at, "u16", count)
    end)
end

local function categories()
    local order, groups = {}, {}
    for _, material in ipairs(tables.materials) do
        if not groups[material.category] then
            groups[material.category] = {}
            order[#order + 1] = material.category
        end
        table.insert(groups[material.category], material)
    end
    return order, groups
end

function build(ui, save)
    local file = saveFile(save)

    ui:page("Rupees", function(page)
        page:int{ label = "Rupees", bind = file:field(RUPEES, "u32"), max = 9999999, step = 1000,
            actions = { { label = "Max", run = function() file:set(RUPEES, "u32", 9999999) end } } }
    end)

    ui:page("Materials", function(page)
        local order, groups = categories()
        for _, category in ipairs(order) do
            local list = groups[category]
            page:section({ title = category:sub(1, 1):upper() .. category:sub(2), key = category, collapsed = true, actions = {
                { label = "Set all to 999", run = function()
                    for _, material in ipairs(list) do materialBinding(file, material):set(math.min(999, material.cap or 999)) end
                end },
            } }, function(section)
                for _, material in ipairs(list) do
                    section:int{ label = material.label .. (material.dlc and " (DLC)" or ""), key = "m" .. material.index,
                        bind = materialBinding(file, material), max = material.cap or 999, step = 10 }
                end
            end)
        end
    end)

    ui:page("Characters", function(page)
        for _, character in ipairs(tables.characters) do
            local at = CHARACTERS + character.index * CHARACTER_SIZE
            page:int{ label = character.label, min = 1, max = 100, step = 1,
                bind = st.bind(function() return file:u8(at) + 1 end, function(level) file:set(at, "u8", level - 1) end) }
        end
    end)
end

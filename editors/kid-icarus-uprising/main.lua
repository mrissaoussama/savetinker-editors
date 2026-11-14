-- Ported from Marc Robledo's Kid Icarus: Uprising save editor (MIT): https://github.com/marcrobledo/savegame-editors
local SAVE_SIZE = 66296
local HEARTS, PALUTENA, VIRIDI = 0x01e8, 0x01ec, 0x01f0
local WEAPONS, WEAPON_SIZE, WEAPON_COUNT = 0x0670, 0x20, 1000
local STATS = 0x0101b8
local FLOAT_STATS = { [24] = true, [25] = true }
local MAX_WEAPON_VALUE = 350

local tables = st.json.decode(st.data("data/tables.json"))

local function saveFile(save)
    for _, name in ipairs(save:files()) do
        if save:file(name):size() == SAVE_SIZE then return save:file(name) end
    end
end

function detect(save)
    return saveFile(save) ~= nil, "Expected a 66296 byte save (0x.sav)."
end

-- Stars are shown as numbers: the original uses star glyphs most console fonts lack.
local function starLabel(index)
    if index == 0 then return "None" end
    if index <= 12 then return string.format("%g stars", index / 2) end
    return string.format("%g stars", -(index - 12) / 2)
end

local function weaponName(file, at)
    local signature = ((file:u8(at + 5) & 0xbc) << 8) + (file:u8(at + 6) & 0x07)
    for _, group in ipairs(tables.weapon_types) do
        for _, weapon in ipairs(group.weapons) do
            if weapon.bitmap == signature then return weapon.name, group.name end
        end
    end
    return "Unknown weapon", "?"
end

local function weaponValue(file, at)
    local value = 100
    for i = 0, 5 do value = value + (tables.modifier_values[file:u16(at + 0x14 + i * 2) + 1] or 0) end
    local ranged, melee = file:u16(at + 0x08), file:u16(at + 0x0a)
    value = value + (tables.star_ranged_values[ranged + 1] or 0)
    value = value + (tables.star_melee_values[(melee > 0 and melee - 0x10 or 0) + 1] or 0)
    return math.ceil(value)
end

local function weaponPage(page, file, slot)
    local at = WEAPONS + slot * WEAPON_SIZE
    local name, group = weaponName(file, at)
    page:page({ title = string.format("%d. %s", slot + 1, name), key = "weapon" .. slot }, function(weapon)
        weapon:label{ label = "Type", value = group }
        local value = weaponValue(file, at)
        if value > MAX_WEAPON_VALUE then
            weapon:warning(string.format("Value %d is above %d: the game treats this weapon as invalid.", value, MAX_WEAPON_VALUE))
        else
            weapon:label{ label = "Value", value = tostring(value) }
        end
        local ranged, melee = {}, { { value = 0, label = "None" } }
        for i = 0, #tables.stars - 1 do ranged[#ranged + 1] = { value = i, label = starLabel(i) } end
        for i = 1, #tables.stars - 1 do melee[#melee + 1] = { value = 0x10 + i, label = starLabel(i) } end
        weapon:dropdown{ label = "Ranged stars", bind = file:field(at + 0x08, "u16"), options = ranged }
        weapon:dropdown{ label = "Melee stars", bind = file:field(at + 0x0a, "u16"), options = melee }
        local modifiers = {}
        for i, text in ipairs(tables.modifiers) do modifiers[i] = { value = i - 1, label = text } end
        for i = 0, 5 do
            weapon:dropdown{ label = "Modifier " .. (i + 1), bind = file:field(at + 0x14 + i * 2, "u16"), options = modifiers }
        end
    end)
end

function build(ui, save)
    local file = saveFile(save)

    ui:page("Hearts", function(page)
        page:int{ label = "Hearts", bind = file:field(HEARTS, "u32"), max = 9999999, step = 1000,
            actions = { { label = "Max", run = function() file:set(HEARTS, "u32", 9999999) end } } }
        page:int{ label = "Offered to Palutena", bind = file:field(PALUTENA, "u32"), max = 9999999, step = 1000 }
        page:int{ label = "Offered to Viridi", bind = file:field(VIRIDI, "u32"), max = 9999999, step = 1000 }
    end)

    ui:page("Weapons", function(page)
        local count = 0
        for slot = 0, WEAPON_COUNT - 1 do
            local at = WEAPONS + slot * WEAPON_SIZE
            if file:u8(at + 5) ~= 0 or file:u8(at + 6) ~= 0 or file:u8(at + 7) ~= 0 then
                weaponPage(page, file, slot)
                count = count + 1
            end
        end
        if count == 0 then page:note("No weapons in this save.") end
    end)

    ui:page("Stats", function(page)
        for i, name in ipairs(tables.stats) do
            local at = STATS + (i - 1) * 4
            local label = name:gsub(" %*FLOAT%*", "")
            if FLOAT_STATS[i - 1] then
                page:float{ label = label, bind = file:field(at, "f32"), min = 0, max = 9 }
            elseif not name:match("^UNKNOWN") then
                page:int{ label = label, bind = file:field(at, "u32") }
            end
        end
    end)
end

-- Ported from Marc Robledo's Super Kirby Clash save editor (MIT): https://github.com/marcrobledo/savegame-editors
local SAVE_SIZE = 54344
local MISSION_UNLOCKED_NEW = 0x02

local missions = {
    { label = "Password missions", offset = 0x3a3c },
    { label = "eShop missions", offset = 0x3a44 },
}

local function saveFile(save)
    if save:has("savedata.dat") and save:file("savedata.dat"):size() == SAVE_SIZE then return save:file("savedata.dat") end
end

function detect(save)
    return saveFile(save) ~= nil, "Expected savedata.dat of 54344 bytes."
end

function build(ui, save)
    local file = saveFile(save)

    ui:page("Gem apples", function(page)
        page:int{ label = "Gem apples", bind = file:field(0x3ef0, "u32"), max = 99999, step = 100,
            actions = { { label = "Max", run = function() file:set(0x3ef0, "u32", 99999) end } } }
        page:int{ label = "Bought gem apples", bind = file:field(0x3f00, "u16"), max = 5000, step = 100 }
    end)

    ui:page("Fragments", function(page)
        for _, shard in ipairs({ { "Red", 0x3f20 }, { "Blue", 0x3f24 }, { "Yellow", 0x3f28 }, { "Rare", 0x3f2c } }) do
            page:int{ label = shard[1] .. " fragments", bind = file:field(shard[2], "u16"), max = 9999, step = 10 }
        end
    end)

    ui:page("Heroic missions", function(page)
        for _, mission in ipairs(missions) do
            local state = file:u8(mission.offset)
            if state > 0x01 then
                page:label{ label = mission.label, value = "Unlocked" }
            else
                page:button{ label = "Unlock " .. mission.label:lower(), run = function()
                    file:set(mission.offset, "u8", MISSION_UNLOCKED_NEW)
                end }
            end
        end
    end)
end

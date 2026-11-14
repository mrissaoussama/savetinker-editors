-- Ported from Marc Robledo's Mario Kart 7 save editor (MIT): https://github.com/marcrobledo/savegame-editors
local SAVE_SIZE = 20692
local CHECKSUM = SAVE_SIZE - 4

local offsets = {
    name = 0x22, coins = 0x4c28, streetpass = 0x4e24, wins = 0x4e34, losses = 0x4e38, vr = 0x4e3c,
}
local unlocks = {
    { label = "Cups", offset = 0x4e3f, bytes = "\x3f" },
    { label = "Characters", offset = 0x4e42, bytes = "\xff\x01\xff\x01" },
    { label = "Karts", offset = 0x4e48, bytes = "\xff\x3f" },
    { label = "Tires", offset = 0x4e4c, bytes = "\x7f" },
    { label = "Gliders", offset = 0x4e50, bytes = "\x3f" },
}

local function systemFiles(save)
    local files = {}
    for _, name in ipairs(save:files()) do
        if name:match("system%d%.dat$") and save:file(name):size() == SAVE_SIZE then files[#files + 1] = name end
    end
    return files
end

function detect(save)
    return #systemFiles(save) > 0
end

function before_save(save)
    for _, name in ipairs(systemFiles(save)) do
        local file = save:file(name)
        file:set(CHECKSUM, "u32", st.hash.crc32(file:bytes(0, CHECKSUM)))
    end
end

local function u24(file, offset)
    return st.bind(function() return file:u16(offset) | (file:u8(offset + 2) << 16) end,
        function(value)
            file:set(offset, "u16", value & 0xffff)
            file:set(offset + 2, "u8", (value >> 16) & 0xff)
        end)
end

function build(ui, save)
    local files = systemFiles(save)
    local options = {}
    for i, name in ipairs(files) do options[i] = { value = name, label = name } end
    local current = ui:state("file", files[1])
    if #files > 1 then ui:dropdown{ label = "Save file", bind = current, options = options } end
    local file = save:file(current:get())

    ui:page("Player", function(page)
        page:text{ label = "Name", bind = file:text(offsets.name, 10, "utf16le") }
        page:int{ label = "Coins", bind = u24(file, offsets.coins), max = 99999, step = 100,
            actions = { { label = "Max", run = function() u24(file, offsets.coins):set(99999) end } } }
        page:int{ label = "StreetPass tags", bind = u24(file, offsets.streetpass), max = 99999 }
    end)

    ui:page("Online", function(page)
        page:int{ label = "Wins", bind = file:field(offsets.wins, "u16"), max = 99999 }
        page:int{ label = "Losses", bind = file:field(offsets.losses, "u16"), max = 99999 }
        page:int{ label = "VR points", bind = file:field(offsets.vr, "u16"), max = 99999, step = 100 }
    end)

    ui:page("Unlocks", function(page)
        for _, unlock in ipairs(unlocks) do
            local done = file:bytes(unlock.offset, #unlock.bytes) == unlock.bytes
            page:label{ label = unlock.label, value = done and "All unlocked" or "Not all unlocked" }
        end
        page:button{ label = "Unlock everything", run = function()
            for _, unlock in ipairs(unlocks) do file:setBytes(unlock.offset, unlock.bytes) end
        end }
    end)
end

-- MV: lz-string base64 text. MZ: zlib data that the engine writes out as UTF-8 text, one character per byte.
local codec = {}

function codec.kind(name)
    if name:lower():match("%.rpgsave$") then return "mv" end
    if name:lower():match("%.rmmzsave$") then return "mz" end
end

local function unwrapBytes(text)
    if not utf8.len(text) then return nil end
    local bytes, count = {}, 0
    for _, code in utf8.codes(text) do
        if code > 255 then return nil end
        count = count + 1
        bytes[count] = string.char(code)
    end
    return table.concat(bytes)
end

local function wrapBytes(data)
    local chars = {}
    for i = 1, #data do chars[i] = utf8.char(data:byte(i)) end
    return table.concat(chars)
end

-- Returns the JSON text and how the file was stored, or nil and a reason.
function codec.decode(name, raw)
    local kind = codec.kind(name)
    if kind == "mv" then
        local ok, text = pcall(st.lzstring.decompress_base64, raw)
        if ok and text:sub(1, 1) == "{" then return text, { kind = kind } end
        return nil, "not an RPG Maker MV save"
    elseif kind == "mz" then
        local wrapped = unwrapBytes(raw)
        local tries = wrapped and { wrapped, raw } or { raw }
        for _, data in ipairs(tries) do
            local ok, text = pcall(st.zlib.decompress, data)
            if ok and text:sub(1, 1) == "{" then return text, { kind = kind, wrapped = data == wrapped } end
        end
        return nil, "not an RPG Maker MZ save"
    end
    return nil, "not an RPG Maker save"
end

function codec.encode(text, format)
    if format.kind == "mv" then return st.lzstring.compress_base64(text) end
    local data = st.zlib.compress(text, 1)
    return format.wrapped and wrapBytes(data) or data
end

return codec

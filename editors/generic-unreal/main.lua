local gvas = require("st.gvas")

local MAX_ROWS = 400

local function saves(save)
    local found = {}
    for _, name in ipairs(save:files()) do
        local file = save:file(name)
        if file:size() >= 4 and file:bytes(0, 4) == "GVAS" then found[#found + 1] = name end
    end
    return found
end

function detect(save)
    local names = saves(save)
    if #names == 0 then return false, "No Unreal save (GVAS) in this save data." end
    local parsed, reason = gvas.parse(save:file(names[1]))
    if not parsed then return false, reason end
    return true
end

local fill

local function widget(page, file, node, id)
    local binding = gvas.bind(file, node)
    if node.children then
        local count = #node.children
        page:page({ title = node.name .. "  (" .. (node.struct or node.type or "") .. ", " .. count .. ")", key = id },
            function(sub) fill(sub, file, node.children, id) end)
    elseif node.kind == "entry" then
        page:section({ title = node.name, key = id, collapsed = true }, function(section)
            widget(section, file, node.key, id .. "/k")
            widget(section, file, node.value, id .. "/v")
        end)
    elseif node.kind == "bool" then
        page:toggle{ label = node.name, key = id, bind = binding }
    elseif node.kind == "f32" or node.kind == "f64" then
        page:float{ label = node.name, key = id, bind = binding }
    elseif node.kind == "string" then
        page:text{ label = node.name, key = id, bind = binding, max_length = math.max(256, #node.value * 2) }
    elseif binding then
        page:int{ label = node.name, key = id, bind = binding }
    else
        page:label{ label = node.name, key = id, value = (node.type or "data") .. ", " .. (node.length or 0) .. " bytes" }
    end
end

function fill(page, file, nodes, prefix)
    for i, node in ipairs(nodes) do
        if i > MAX_ROWS then
            page:note((#nodes - MAX_ROWS) .. " more entries are not shown.")
            break
        end
        widget(page, file, node, prefix .. "/" .. i)
    end
end

function build(ui, save)
    for _, name in ipairs(saves(save)) do
        local file = save:file(name)
        ui:page({ title = name, key = name }, function(page)
            local parsed, reason = gvas.parse(file)
            if not parsed then
                page:warning(reason)
                return
            end
            page:label{ label = "Engine", value = parsed.header.engine }
            page:label{ label = "Save class", value = parsed.header.class }
            page:separator()
            fill(page, file, parsed.properties, name)
        end)
    end
end

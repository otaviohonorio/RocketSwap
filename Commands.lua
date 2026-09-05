-- RocketSwap | Commands.lua
local ADDON, ns = ...
local L = ns.L

local commands = {}

commands[""] = function()
    ns.UI.Toggle()
end

commands["load"] = function(rest)
    local wanted = rest and rest:match("^%s*(.-)%s*$")
    if not wanted or wanted == "" then
        ns.UI.Toggle()
        return
    end

    for _, preset in ipairs(ns.db.presets) do
        if preset.name:lower() == wanted:lower() then
            ns.db.last = preset.name
            ns.Data.Apply(preset, function(text, isError)
                ns.UI.SetStatus(text, isError)
                ns.Print(text)
            end)
            return
        end
    end
    ns.Print(L["no preset with that name."])
end

commands["list"] = function()
    if #ns.db.presets == 0 then
        ns.Print(L["No presets yet."])
        return
    end
    ns.Print(L["Presets"] .. ":")
    for _, preset in ipairs(ns.db.presets) do
        local mark = ns.Data.IsLoaded(preset) and "|cff40d878*|r " or "  "
        print("  " .. mark .. (preset.name ~= "" and preset.name or L["Unnamed"]))
    end
end

commands["help"] = function()
    ns.Print(L["commands:"])
    print("  /rs                 " .. L["opens the window"])
    print("  /rs load <nome>     " .. L["loads a preset by name"])
    print("  /rs list            " .. L["lists the presets"])
end

-- As globais SLASH_* precisam ser criadas em escopo de arquivo, nao dentro de evento.
SLASH_ROCKETSWAP1 = "/rs"
SLASH_ROCKETSWAP2 = "/rocketswap"

SlashCmdList["ROCKETSWAP"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    local handler = commands[cmd:lower()]
    if handler then
        handler(rest)
    else
        -- "/rs mitica" e atalho para "/rs load mitica": o caso comum nao merece verbo.
        commands["load"](msg)
    end
end

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
        ns.Print(L["No presets yet"])
        return
    end
    ns.Print(L["Presets"] .. ":")
    for _, preset in ipairs(ns.db.presets) do
        local mark = ns.Data.IsLoaded(preset) and "|cff40d878*|r " or "  "
        print("  " .. mark .. (preset.name ~= "" and preset.name or L["Unnamed"]))
    end
end

commands["warn"] = function()
    ns.db.warn = ns.db.warn == false
    ns.Print(ns.db.warn and L["gear warning on."] or L["gear warning off."])
end

commands["ready"] = function()
    ns.db.readyCheck = ns.db.readyCheck == false
    ns.Print(ns.db.readyCheck and L["ready check summary on."] or L["ready check summary off."])
end

commands["unmute"] = function()
    ns.db.muted, ns.db.mutedSlots = {}, {}
    ns.Print(L["all warnings re-enabled."])
end

-- Instrumentacao. A deteccao de peca de PvP depende de uma LINHA DE TOOLTIP casar com um
-- padrao montado a partir de uma string global — e isso pode falhar por idioma, por tooltip
-- nao carregada ou por a peca nao ter a linha. Sem este comando, a falha e silenciosa e
-- indistinguivel de "esta tudo certo".
commands["gear"] = function()
    ns.Print(L["what you are wearing:"] .. "  " .. ns.Alert.Summary())
    local contexto = ns.Alert.Context()
    print("  " .. L["context:"] .. " " .. (contexto or L["(open world)"]))

    for _, slot in ipairs(ns.Gear.SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link and not issecretvalue(link) then
            local isPvP = ns.Gear.IsPvPItem(slot)
            local marca = isPvP == true and "|cff40d878PvP|r"
                or isPvP == false and "|cffb8ac8aPvE|r"
                or "|cffff5555?|r"
            print(("  %-22s %s  %s"):format(ns.Gear.SlotName(slot), marca, link))
        end
    end
end

commands["help"] = function()
    ns.Print(L["commands:"])
    print("  /rs                 " .. L["opens the window"])
    print("  /rs load <nome>     " .. L["loads a preset by name"])
    print("  /rs list            " .. L["lists the presets"])
    print("  /rs gear            " .. L["shows what each slot is reading as"])
    print("  /rs warn            " .. L["turns the gear warning on or off"])
    print("  /rs ready           " .. L["turns the ready check summary on or off"])
    print("  /rs unmute          " .. L["re-enables warnings you silenced"])
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

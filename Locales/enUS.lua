-- RocketSwap | Locales/enUS.lua
-- The localization base. This file ALWAYS loads, in any client language.
--
-- The same structure as RocketMeter (standardized on 05/09/2026), in two layers:
--
--   1. THE KEY IS THE ENGLISH TEXT. Without a translation, the key itself shows on screen -- so
--      English is the automatic fallback of every language that does not have a file here yet.
--
--   2. `FROM_GAME` pulls from the client itself the labels Blizzard already translated, which holds
--      for the ~11 languages at once and uses **the word the player already reads in the interface**.
--
-- After this file the language's file loads (ptBR.lua), which overrides what it wants. The
-- final precedence is: our explicit choice > the game's word > the English key.
local ADDON, ns = ...

local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})

ns.L = L

--------------------------------------------------------------------------------
-- Labels the game already translated
--------------------------------------------------------------------------------
-- This table is short **on purpose**. This addon's vocabulary is almost all our own phrases
-- ("Nenhum conjunto ainda", "Trocando de especialização..."), and for the game's words that
-- looked like obvious candidates the evidence said stop. See the block of refusals below.
--
-- What this addon already did right before this table existed: `Gear.lua:177-190` reads the slot
-- names from `_G["HEADSLOT"]` and the like, with the slot number as the last resort. The 16 slots
-- of the gear warning already came out translated in every language.
local FROM_GAME = {
    ["Specialization"] = "SPECIALIZATION",
    ["Talents"]        = "TALENTS",
    ["Appearance"]     = "APPEARANCE_LABEL",
    ["Delete"]         = "DELETE",
    ["version"]        = "GAME_VERSION_LABEL",
}

-- What did NOT come in, and why -- all checked against build 12.1.0.69587:
--
--   "Ready check:"  READY_CHECK in pt-BR is **"Todos prontos?"**, a question. The label is a
--                   prefix ("Ready check: Gélido · SBA ST"), and it would give "Todos prontos?: ...".
--   "Gear"          No clean global, and it has the naming trap described in ptBR.lua: in
--                   pt-BR the game calls a **talent loadout** "equipamento" and an **item
--                   set** "conjunto". This addon avoids both on purpose, because
--                   it exists for whoever already confuses the two things.
--   "Load"          There is no `LOAD` global. `EQUIPSET_EQUIP` is "Equipar", and the button does
--                   more than equip -- it switches spec and talents too.
--   "(none)"        NONE is "Nenhum", without the parentheses our label uses.
--   "Warnings"      Only PING_TYPE_WARNING exists, singular ("Alerta"), from the ping system.

ns.FROM_GAME = FROM_GAME

--- Does this global serve as a label?
---
--- Three guards, each one against a different failure:
---
---  * **not a string** -> the global does not exist in this client. This guard **cannot** be
---    simplified: without it `text:find` receives `nil` and **raises an error at file load**.
---    Since `ns.L` is born here, the whole addon dies with it.
---  * **empty string** -> it exists but has no text; it would become a blank label.
---  * **has `%s`/`%d`** -> it is a sentence template, not a label, and would show raw on screen.
---
--- In all three cases the key is left alone and the English still holds.
--- @return string|nil text, string|nil reason for refusal
local function Usable(tag)
    local text = _G[tag]
    if type(text) ~= "string" then return nil, "ausente" end
    if text == "" then return nil, "vazia" end
    if text:find("%%") then return nil, "modelo de frase" end
    return text
end

--- Writes the game's labels into `L`. It runs **once**, when this file loads, before the
--- language file -- which overrides what it wants afterwards.
function ns.ApplyGameStrings()
    for key, tag in pairs(FROM_GAME) do
        local text = Usable(tag)
        if text then
            rawset(L, key, text)
        end
    end
end

--- The report for `/rs i18n`. **Read only** -- reapplying here would erase what the language file
--- wrote on top, with nobody understanding why.
--- @return table a list of { key, tag, text, why }, sorted by global
function ns.CheckGameStrings()
    local report = {}
    for key, tag in pairs(FROM_GAME) do
        local text, why = Usable(tag)
        report[#report + 1] = { key = key, tag = tag, text = text, why = why }
    end
    table.sort(report, function(a, b) return a.tag < b.tag end)
    return report
end

ns.ApplyGameStrings()

-- Painel flutuante de progresso da troca (0.29.0)
L["turns the swap progress panel on or off"] = "turns the swap progress panel on or off"
L["swap progress panel on."] = "swap progress panel on."
L["swap progress panel off."] = "swap progress panel off."

-- Item set with a lost piece (0.31.0)
L["%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."] = "%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."
L["You are already wearing the rest of it — use /rs fix to update the set."] = "You are already wearing the rest of it — use /rs fix to update the set."
L["Open the equipment manager, fix the set and save it, then switch."] = "Open the equipment manager, fix the set and save it, then switch."
L["%s updated with what you are wearing."] = "%s updated with what you are wearing."
L["nothing to fix: no gear set is missing items you are wearing."] = "nothing to fix: no gear set is missing items you are wearing."
L["updates a broken gear set with what you are wearing"] = "updates a broken gear set with what you are wearing"
L["%s: %d item(s) missing"] = "%s: %d item(s) missing"
L["Save set"] = "Save set"
L["Equipment Manager"] = "Equipment Manager"

-- Warning columns (0.34.0)
L["Turn on the wrong gear warning first."] = "Turn on the wrong gear warning first."

-- Colunas dos avisos por conteudo (0.35.0)
L["PvE"] = "PvE"
L["PvP"] = "PvP"

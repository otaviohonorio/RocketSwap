-- RocketSwap | Commands.lua
local ADDON, ns = ...
local L = ns.L

local commands = {}

-- The swap's floating panel. It can be turned off because whoever plays with the addon's window
-- open all the time already has the same information in the right column, and there it is repetition.
-- (!) `SaveEquipmentSet` writes what you are wearing OVER the set. That fixes the piece that went
-- missing -- and would wreck the whole set if you were wearing something else. So the command
-- checks `consertavel` first: it only acts when you are already wearing the whole set but what went
-- missing, the one case where "save" means "fix".
commands["fix"] = function()
    local presets = ns.db and ns.db.presets or {}
    local consertados = 0

    for _, preset in ipairs(presets) do
        if preset.gear then
            local problema = ns.Data.GearSetProblem(preset.gear)
            if problema and problema.consertavel then
                if ns.Data.SaveGearSet(preset.gear) then
                    consertados = consertados + 1
                    ns.Print(format(L["%s updated with what you are wearing."], problema.nome or "?"))
                end
            elseif problema then
                ns.Print(format(L["%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."],
                    problema.nome or "?", problema.perdidas))
                -- It TAKES you there, instead of explaining where it is. The player is in the middle of something else.
                ns.Print(L["Open the equipment manager, fix the set and save it, then switch."])
                ns.Data.OpenEquipmentManager()
            end
        end
    end

    if consertados == 0 then
        ns.Print(L["nothing to fix: no gear set is missing items you are wearing."])
    end
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

commands["progress"] = function()
    ns.db.hideProgress = not ns.db.hideProgress
    if ns.db.hideProgress and ns.Progress and ns.Progress.Frame() then
        ns.Progress.Frame():Hide()
    end
    ns.Print(ns.db.hideProgress
        and L["swap progress panel off."]
        or L["swap progress panel on."])
end

-- The command is in English like all the others (`warn`, `ready`, `queue`), but whoever plays in
-- Portuguese will type "progresso" -- and refusing over one letter would be nitpicking.
commands["progresso"] = function() commands["progress"]() end

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

-- `/rs macrobar`: what the addon sees of the action bars, in chat, right away -- for when a macro
-- was made but did not reach the bar. Diagnostic lines stay in English (they name frames).
commands["macrobar"] = function()
    local s = ns.Macro.Survey()
    ns.Print("macrobar: cursor=" .. tostring(s.cursor) .. "  empty visible slots=" .. #s.empty
        .. (s.empty[1] and (" (first: " .. s.empty[1] .. ")") or ""))
    for _, b in ipairs(s.bars) do
        print(string.format("    %-26s found %2d  usable %2d  empty %2d  no .action %2d",
            b.name, b.found, b.visible, b.empty, b.noAction))
    end
end

-- `/rs macro`: a macro (in this character's macros) for every named preset.
commands["macro"] = function()
    ns.Macro.All()
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

-- `/rs warn` turns the warning on/off; `/rs warn warmode` turns the War Mode one on/off, which
-- starts off. The same door for both because it is the same warning -- one is a slice of the other.
commands["warn"] = function(rest)
    local arg = (rest or ""):lower()
    if arg:find("warmode", 1, true) or arg:find("guerra", 1, true) then
        ns.db.warnWarMode = not (ns.db.warnWarMode == true)
        ns.Print(ns.db.warnWarMode and L["war mode warning on."] or L["war mode warning off."])
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
        return
    end

    -- `/rs warn` with no argument changes BOTH, which is what whoever types the short command expects.
    -- `/rs warn pve` and `/rs warn pvp` change one only.
    local qual = (rest or ""):lower():gsub("%s", "")
    if qual == "pve" then
        ns.db.warnPvE = ns.db.warnPvE == false
        ns.Print(ns.db.warnPvE and L["gear warning on."] or L["gear warning off."])
    elseif qual == "pvp" then
        ns.db.warnPvP = ns.db.warnPvP == false
        ns.Print(ns.db.warnPvP and L["gear warning on."] or L["gear warning off."])
    else
        local novo = not (ns.db.warnPvE ~= false and ns.db.warnPvP ~= false)
        ns.db.warnPvE, ns.db.warnPvP = novo, novo
        ns.Print(novo and L["gear warning on."] or L["gear warning off."])
    end
    if ns.UI and ns.UI.RefreshToggles then ns.UI.RefreshToggles() end
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

commands["ready"] = function()
    ns.db.readyCheck = ns.db.readyCheck == false
    ns.Print(ns.db.readyCheck and L["ready check summary on."] or L["ready check summary off."])
end

-- `/rs queue`: the same summary as the ready check, on the PvP queue's invite. A command of its own,
-- and not an argument of `/rs ready`, because they are two independent triggers -- some want only one.
commands["queue"] = function()
    ns.db.queuePop = ns.db.queuePop == false
    ns.Print(ns.db.queuePop and L["PvP queue pop summary on."] or L["PvP queue pop summary off."])
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

commands["unmute"] = function()
    ns.db.muted, ns.db.mutedSlots = {}, {}
    ns.Print(L["all warnings re-enabled."])
end

-- Instrumentation. Telling a PvP piece depends on a TOOLTIP LINE matching a pattern built from a
-- global string -- and that can fail by language, by a tooltip not loaded or by the piece not
-- having the line. Without this command, the failure is silent and cannot be told from
-- "all is fine".
-- ⚑ `/rs gear <slot>` DUMPS THE RAW LINES, and it was born from the print of 13/09: the chest shows
-- the PvP line in its tooltip ("aumenta o nível do item para um mínimo de 344 em Arenas...") and the
-- addon insists on calling it PvE -- even after switching characters, that is, with the cache
-- empty. The pattern matches that text (checked outside the game), so what is left is the
-- question only the client answers: **what is `C_TooltipInfo.GetInventoryItem` returning
-- for that slot?**
--
-- Without this dump, the guesses left (a line missing from the structure, text in `rightText`,
-- a secret value, a line split in two) cannot be told apart -- and each guess costs a trip to the game.
local function DumpSlot(slot)
    local link = GetInventoryItemLink("player", slot)
    ns.Print(("slot %d (%s):"):format(slot, ns.Gear.SlotName(slot)))
    print("   link: " .. (link and (not issecretvalue(link)) and link or "|cffff5555(nenhum ou secret)|r"))
    print("   padrão montado: " .. (ns.Gear.PatternReady() and "sim" or "|cffff5555não|r")
        .. "   |   padrão se prova: " .. (ns.Gear.PatternWorks() and "sim" or "|cffff5555não|r"))
    print("   leitura atual: " .. tostring(ns.Gear.IsPvPItem(slot)))

    if not C_TooltipInfo or not C_TooltipInfo.GetInventoryItem then
        print("   |cffff5555sem C_TooltipInfo neste cliente|r")
        return
    end

    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
    if not ok then
        print("   |cffff5555a leitura da tooltip estourou:|r " .. tostring(data))
        return
    end
    if type(data) ~= "table" or type(data.lines) ~= "table" then
        print("   |cffff5555a tooltip nao devolveu linhas|r (type=" .. type(data) .. ")")
        return
    end

    print(("   %d linha(s):"):format(#data.lines))
    for i, line in ipairs(data.lines) do
        -- The BARS ARE DOUBLED so the chat shows the raw text: without it a `|cff...` becomes colour and
        -- the line shows painted and cut, which is exactly hiding the evidence.
        local function mostrar(v)
            if v == nil then return "-" end
            if issecretvalue and issecretvalue(v) then return "|cffff5555(secret)|r" end
            if type(v) ~= "string" then return "(" .. type(v) .. ")" end
            return (v:gsub("|", "||"))
        end
        local esquerda = mostrar(line.leftText)
        local casa = ""
        if type(line.leftText) == "string" and not issecretvalue(line.leftText) then
            local padrao = ns.Gear.DebugPattern and ns.Gear.DebugPattern()
            if padrao and line.leftText:match(padrao) then casa = "  |cff40d878<< CASA|r" end
        end
        print(("   %2d  tipo=%s  %s%s"):format(i, tostring(line.type), esquerda, casa))
        if line.rightText ~= nil then
            print("        (direita) " .. mostrar(line.rightText))
        end
    end
end

commands["gear"] = function(rest)
    local alvo = tonumber((rest or ""):match("%d+"))
    if alvo then return DumpSlot(alvo) end

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

-- Instrumentation of the APPEARANCE. The user reported twice that the transmog swap "nao troca e
-- nao gera nenhum erro", the second time with the step already checking the result. With no error,
-- exactly three guesses are left, and none of them is settled by reading code on disk:
--
--   A. the step is SKIPPED -- `GetActiveOutfitID()` already returns the ID the set wants;
--   B. the call is ACCEPTED and the check passes, but the appearance does not really change;
--   C. the call is REFUSED silently. The 12.1.0 source shows THREE doors that refuse without
--      saying anything, and the addon checked none of them:
--
--        * COOLDOWN. Switching appearance by hand spends spell 1247613
--          (`Constants.TransmogOutfitDataConsts.EQUIP_TRANSMOG_OUTFIT_MANUAL_SPELL_ID`), and the
--          game's own UI draws the cooldown over the button
--          (`Blizzard_TransmogTemplates.lua:191-198`). On cooldown, it does not switch and does not
--          warn. This is the strongest suspect for whoever is TESTING -- switching several times in
--          a row is exactly what keeps the cooldown up;
--        * A LOCKED SET (`IsLockedOutfit`), which the UI marks with a padlock (`:80-82`);
--        * A STYLE EVENT under way (`InTransmogEvent`): during it the UI DISABLES every
--          set that is not the event's (`:85-87`).
--
--      And there is a fourth possibility, the wrong door: the game's UI does NOT use `ChangeToOutfit`.
--      The set button calls `ChangeDisplayedOutfit(outfitID, trigger, toggleLock,
--      allowRemoveOutfit)` (`Blizzard_TransmogTemplates.lua:72`) -- by outfitID, with the situation
--      trigger. `ChangeToOutfit` is the macro/slash path, by index.
--
-- This command tells the three apart in one run. `/rs transmog` shows the state; `/rs transmog
-- <index>` calls the API and reads the active ID BEFORE, RIGHT AFTER and half a second later --
-- because it is not checked that the swap holds in the same frame, and that was the doubt left.
-- Instrumentation of the EQUIPMENT WARNING. Six doors close that path and none writes anything;
-- `/rs alert` shows the six at once. See `Alert.Diagnose`.
commands["alert"] = function()
    local d = ns.Alert.Diagnose()

    local function marca(v)
        if v == nil then return "|cffff5555nil|r" end
        if v == true then return "|cff40d878sim|r" end
        if v == false then return "|cffff5555nao|r" end
        return tostring(v)
    end

    ns.Print("diagnostico do aviso de equipamento")
    print("  contexto ............ " .. (d.contexto or "|cffff5555nil (mundo aberto)|r"))
    print("  instancia ........... " .. (d.instancia or "-"))
    print("  war mode ............ " .. marca(d.warMode) .. "  |cff808080(o aviso ignora)|r")
    print("  aviso ligado ........ " .. marca(d.avisoLigado))
    print("  em combate .......... " .. marca(d.emCombate))
    print("  pode consertar ...... " .. marca(d.podeConsertar))
    print("  deteccao viva ....... " .. marca(d.deteccaoViva))

    local r = {}
    for nome, ativa in pairs(d.restricoes) do
        if ativa then r[#r + 1] = nome end
    end
    print("  restricoes ativas ... " .. (#r > 0 and table.concat(r, ", ") or "nenhuma"))

    if #d.filas == 0 then
        print("  filas de PvP ........ nenhuma")
    else
        for _, f in ipairs(d.filas) do
            print(("  fila %d .............. %s  %s"):format(f.id, f.status, f.mapa or ""))
        end
    end

    print(("  pecas vestidas ...... %d"):format(d.vestido or 0))
    print(("  como PvP ............ %d errada(s) de %d lida(s), leitura %s"):format(
        d.comoPvP.errado, d.comoPvP.lido, d.comoPvP.confiavel and "confiavel" or "SUSPEITA"))
    print(("  como PvE ............ %d errada(s) de %d lida(s), leitura %s"):format(
        d.comoPvE.errado, d.comoPvE.lido, d.comoPvE.confiavel and "confiavel" or "SUSPEITA"))
end

commands["transmog"] = function(rest)
    local arg = rest and rest:match("^%s*(%S+)")

    if not C_TransmogOutfitInfo then
        ns.Print("|cffff5555C_TransmogOutfitInfo nao existe neste cliente.|r")
        return
    end

    -- WHICH FUNCTIONS EXIST. One of them missing explains everything, and asking costs nothing.
    local faltando = {}
    for _, nome in ipairs({ "GetOutfitsInfo", "GetActiveOutfitID", "ChangeToOutfit" }) do
        if type(C_TransmogOutfitInfo[nome]) ~= "function" then
            faltando[#faltando + 1] = nome
        end
    end
    if #faltando > 0 then
        ns.Print("|cffff5555faltam neste cliente:|r " .. table.concat(faltando, ", "))
        return
    end

    local function Ativo()
        local ok, id = pcall(C_TransmogOutfitInfo.GetActiveOutfitID)
        if not ok then return "erro: " .. tostring(id) end
        if id == nil then return "nil" end
        if issecretvalue(id) then return "secret" end
        return tostring(id)
    end

    ------------------------------------------------------------------ so mostrar
    ------------------------------------------------------------------ as portas
    --- Returns the text of what is blocking, or nil when nothing is.
    local function Portas(outfitID)
        local motivos = {}

        -- RECARGA: `GetSpellCooldown` devolve tabela com startTime/duration/isEnabled.
        local okCD, cd = pcall(C_Spell.GetSpellCooldown, 1247613)
        if okCD and type(cd) == "table" and cd.duration and cd.duration > 0
            and cd.startTime and cd.startTime > 0 then
            local resta = (cd.startTime + cd.duration) - GetTime()
            if resta > 0 then
                motivos[#motivos + 1] = ("recarga: faltam %.1fs"):format(resta)
            end
        end

        if C_TransmogOutfitInfo.InTransmogEvent then
            local okEv, emEvento = pcall(C_TransmogOutfitInfo.InTransmogEvent)
            if okEv and emEvento then motivos[#motivos + 1] = "evento de estilo em andamento" end
        end

        if outfitID and C_TransmogOutfitInfo.IsLockedOutfit then
            local okLk, travado = pcall(C_TransmogOutfitInfo.IsLockedOutfit, outfitID)
            if okLk and travado then motivos[#motivos + 1] = "conjunto travado" end
        end

        if #motivos == 0 then return nil end
        return table.concat(motivos, ", ")
    end

    ------------------------------------------------------------------ as situacoes automaticas
    --- Midnight's set system switches appearance BY ITSELF per situation, and two of the
    --- situations are `Specialization` and `EquipmentSet`
    --- (`TransmogOutfitConstantsDocumentation.lua:373-374`) -- exactly the two steps the addon's
    --- chain runs before the appearance. If that is on, the game may be switching on its own on top of
    --- what we asked, and that shows as an error nowhere. Reading the state is cheap and answers it.
    local function Situacoes()
        local partes = {}

        if C_TransmogOutfitInfo.GetOutfitSituationsEnabled then
            local ok, ligado = pcall(C_TransmogOutfitInfo.GetOutfitSituationsEnabled)
            if ok then
                partes[#partes + 1] = "troca automatica por situacao: "
                    .. (ligado and "|cffff5555LIGADA|r" or "|cff40d878desligada|r")
            end
        end

        if C_TransmogOutfitInfo.HasPendingOutfitSituations then
            local ok, pendente = pcall(C_TransmogOutfitInfo.HasPendingOutfitSituations)
            if ok and pendente then
                partes[#partes + 1] = "|cffff5555ha situacao pendente|r"
            end
        end

        if C_TransmogOutfitInfo.IsEquippedGearOutfitDisplayed then
            local ok, mostrando = pcall(C_TransmogOutfitInfo.IsEquippedGearOutfitDisplayed)
            if ok and mostrando then
                partes[#partes + 1] = "mostrando a aparencia do EQUIPAMENTO, nao de um conjunto"
            end
        end

        if #partes == 0 then return nil end
        return table.concat(partes, "; ")
    end

    if not arg then
        ns.Print("aparencia ativa agora: |cffffd100" .. Ativo() .. "|r")

        local impedindo = Portas(nil)
        ns.Print("impedimentos agora: " ..
            (impedindo and ("|cffff5555" .. impedindo .. "|r") or "|cff40d878nenhum|r"))

        local sit = Situacoes()
        if sit then ns.Print("situacoes: " .. sit) end

        local ok, lista = pcall(C_TransmogOutfitInfo.GetOutfitsInfo)
        if not ok or type(lista) ~= "table" then
            ns.Print("|cffff5555GetOutfitsInfo nao devolveu tabela:|r " .. tostring(lista))
            return
        end
        print(("  %-4s %-6s %-24s %s"):format("id", "indice", "nome", "estado"))
        for _, info in ipairs(lista) do
            print(("  %-4s %-6s %-24s %s"):format(
                tostring(info.outfitID),
                tostring(info.playerFacingOutfitIndex),
                tostring(info.name),
                (info.isDisabled and "|cffff5555desativado|r" or "ok")
                    .. (info.isEventOutfit and " (evento)" or "")))
        end

        -- AND WHAT EACH SET WANTS, resolved the same way the step resolves it. If the index comes out
        -- `nil` here, the set keeps an `outfitID` that no longer exists.
        ns.Print("o que cada conjunto pede:")
        for _, preset in ipairs(ns.db.presets) do
            if preset.transmog then
                local indice
                for _, o in ipairs(ns.Data.GetOutfits()) do
                    if o.outfitID == preset.transmog then indice = o.index end
                end
                print(("  %-24s id %-4s -> indice %s"):format(
                    preset.name or "?", tostring(preset.transmog),
                    indice and tostring(indice) or "|cffff5555nao existe mais|r"))
            end
        end
        ns.Print("para testar a troca crua: |cffffd100/rs transmog <indice>|r")
        return
    end

    ------------------------------------------------------------------ trocar de verdade
    local indice = tonumber(arg)
    if not indice then
        ns.Print("|cffff5555use um indice numerico|r (o da coluna 'indice' de /rs transmog)")
        return
    end

    -- O outfitID daquele indice, que a segunda porta de entrada pede.
    local alvoID
    for _, o in ipairs(ns.Data.GetOutfits()) do
        if o.index == indice then alvoID = o.outfitID end
    end

    local impedindo = Portas(alvoID)
    if impedindo then
        ns.Print("|cffff5555impedimento antes mesmo de tentar:|r " .. impedindo)
        ns.Print("tente de novo quando passar -- o resultado abaixo nao vale como teste.")
    end

    local antes = Ativo()

    -- THE TWO DOORS IN, in the same run, because the doubt is which of them serves an addon:
    --
    --   `ChangeToOutfit(index, allowRemove)`  -- the macro/slash path, by INDEX;
    --   `ChangeDisplayedOutfit(id, trigger, lock, allowRemove)` -- what the game's BUTTON uses.
    --
    -- `allowRemoveOutfit = false` in both: with `true`, asking for the appearance already on is
    -- treated as CLEARING (`SlashCommands.lua:1714`), and that would muddle the reading -- it would
    -- look like the call did nothing, when it did the opposite.
    local ok, err = pcall(C_TransmogOutfitInfo.ChangeToOutfit, indice, false)
    ns.Print(("1) ChangeToOutfit(%d, false): %s"):format(
        indice, ok and "|cff40d878sem erro|r" or ("|cffff5555" .. tostring(err) .. "|r")))
    print("   ativo antes:       " .. antes)
    print("   ativo logo depois: " .. Ativo())

    C_Timer.After(0.5, function()
        local depoisDa1 = Ativo()
        print("   ativo 0,5s depois: " .. depoisDa1)

        if depoisDa1 == tostring(alvoID) then
            ns.Print("|cff40d878o ID ativo virou o alvo.|r Olhe o personagem: a tela mudou?")
            print("   se a tela NAO mudou, a API aceita e nao aplica (hipotese B).")
            print("   se mudou, a API funciona e o defeito esta na corrente do addon.")
            return
        end

        -- THE FIRST DOOR DID NOT TAKE. Tries the one the game uses, with the same target.
        ns.Print("|cffff5555o ID ativo NAO virou o alvo.|r Tentando a porta que a UI do jogo usa:")
        if not alvoID or not C_TransmogOutfitInfo.ChangeDisplayedOutfit then
            print("   indisponivel: " .. (alvoID and "a funcao nao existe" or "indice sem outfitID"))
            return
        end

        local trigger = Enum and Enum.TransmogSituationTrigger
            and Enum.TransmogSituationTrigger.Manual
        local ok2, err2 = pcall(C_TransmogOutfitInfo.ChangeDisplayedOutfit,
            alvoID, trigger, false, false)
        ns.Print(("2) ChangeDisplayedOutfit(%s, Manual, false, false): %s"):format(
            tostring(alvoID), ok2 and "|cff40d878sem erro|r"
                or ("|cffff5555" .. tostring(err2) .. "|r")))

        C_Timer.After(0.5, function()
            local depoisDa2 = Ativo()
            print("   ativo 0,5s depois: " .. depoisDa2)
            if depoisDa2 == tostring(alvoID) then
                ns.Print("|cff40d878e ESTA funcionou.|r A porta certa e `ChangeDisplayedOutfit`.")
            else
                -- THE EXPECTED. Both are PROTECTED: patch 12.0.5 added a secure action
                -- `"outfit"` exactly because of that.
                --
                -- The command keeps trying because it proves, on the player's machine, what here is
                -- only a quote -- and because if Blizzard ever opens it up, it tells.
                ns.Print("|cffff5555nenhuma das duas trocou -- e e o esperado.|r As duas sao "
                    .. "protegidas; addon nao troca aparencia.")
                ns.Print("quem troca e o |cffffd100clique no botao Carregar|r da janela do "
                    .. "addon, que carrega a acao segura de aparencia.")
            end

            -- "SO TROCOU A APARENCIA DA ARMA" was the report of 06/09, and none of the doors explains
            -- it: they are all-or-nothing. It is explained by piece -- there is a whole
            -- enum of errors PER PIECE (`TransmogOutfitSlotError`: NoItem, NotSoulbound,
            -- Legendary, InvalidItemType, Mismatch, CannotUseItem, InvalidSlotForRace...) --
            -- or by the game having switched by itself per situation. Both show here.
            local sit = Situacoes()
            if sit then ns.Print("situacoes: " .. sit) end

            if C_TransmogOutfitInfo.GetOutfitInfo and alvoID then
                local okInfo, info = pcall(C_TransmogOutfitInfo.GetOutfitInfo, alvoID)
                if okInfo and type(info) == "table" then
                    print(("   conjunto alvo: %s  (%s)"):format(
                        tostring(info.name),
                        info.isDisabled and "|cffff5555desativado|r" or "ativo"))
                end
            end
        end)
    end)
end

-- Instrumentation, for the same reason as `/rs gear`: `FROM_GAME` depends on the client's globals, and
-- a global that does not exist warns nothing -- the label just stays in English, which cannot be
-- told from "that is right". One line of output settles it.
commands["i18n"] = function()
    local report = ns.CheckGameStrings()
    ns.Print(format(L["locale %s, %d game label(s):"], GetLocale(), #report))

    local broken = 0
    for _, row in ipairs(report) do
        if row.text then
            print(format("  |cff33ff99ok|r    %-24s %s", row.tag, row.text))
        else
            broken = broken + 1
            print(format("  |cffff5555--|r    %-24s %s  (%s)", row.tag, row.key, row.why))
        end
    end

    if broken > 0 then
        ns.Print(format(L["%d game label(s) are not usable here."], broken))
    end
end

-- THE SWAP'S LOG. The user's literal question after the swap failed again: "tu ta
-- salvando logs para poder entender os problemas?". The answer was no, and that is why the rounds
-- before were me guessing which step failed and him telling me in writing.
--
-- `/rs log` shows the last lines in the chat -- it settles the simple case without leaving the game.
-- The file in SavedVariables answers the hard case, and it is only written on `/reload` or on
-- logout: that is why the message says so instead of letting the player hunt an empty file.
commands["log"] = function(rest)
    -- So existe fora do pacote (ver Core.lua).
    if not ns.Log.enabled then
        ns.Print(L["the log only exists in development builds."])
        return
    end
    local arg = rest and rest:lower():match("^%S*")

    if arg == "clear" then
        ns.Log.Clear()
        ns.Log.ClearErrors()
        ns.Print(L["log cleared."])
        return
    end

    -- THE ERRORS FIRST, and in the chat. Reading the file needs `/reload` and leaving the game; the
    -- count here answers "did anything happen?" without any of that.
    ns.PrintErrorSummary()

    local linhas = ns.Log.Tail(14)
    if #linhas == 0 then
        ns.Print(L["the log is empty: load a preset and look again."])
        return
    end

    ns.Print(format(L["log: %d entries. The last ones:"], ns.Log.Count()))
    for _, linha in ipairs(linhas) do
        print("  " .. linha)
    end
    ns.Print(L["type /reload so the file is written, then send:"])
    print("  WTF\\Account\\<conta>\\SavedVariables\\RocketSwap.lua")
end

commands["help"] = function()
    ns.Print(L["version"] .. " " .. ns.version .. " — " .. L["commands:"])
    print("  /rs                 " .. L["opens the window"])
    print("  /rs load <nome>     " .. L["loads a preset by name"])
    print("  /rs list            " .. L["lists the presets"])
    print("  /rs macro           " .. L["makes a macro for each preset, on this character"])
    print("  /rs gear            " .. L["shows what each slot is reading as"])
    print("  /rs transmog        " .. L["shows the appearance sets and tests the switch"])
    print("  /rs i18n            " .. L["checks the labels taken from the game"])
    print("  /rs warn            " .. L["turns the gear warning on or off"])
    print("  /rs ready           " .. L["turns the ready check summary on or off"])
    print("  /rs queue           " .. L["turns the PvP queue pop summary on or off"])
    print("  /rs unmute          " .. L["re-enables warnings you silenced"])
    print("  /rs fix             " .. L["updates a broken gear set with what you are wearing"])
    print("  /rs progress        " .. L["turns the swap progress panel on or off"])
    if ns.Log.enabled then
        print("  /rs log [clear]     " .. L["shows the log of the last swaps"])
    end
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
        -- "/rs mitica" is a shortcut for "/rs load mitica": the common case deserves no verb.
        commands["load"](msg)
    end
end

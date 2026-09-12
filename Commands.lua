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

-- `/rs warn` liga/desliga o aviso; `/rs warn warmode` liga/desliga o de modo guerra, que nasce
-- desligado. A mesma porta para as duas coisas porque e o mesmo aviso -- uma e o recorte da outra.
commands["warn"] = function(rest)
    local arg = (rest or ""):lower()
    if arg:find("warmode", 1, true) or arg:find("guerra", 1, true) then
        ns.db.warnWarMode = not (ns.db.warnWarMode == true)
        ns.Print(ns.db.warnWarMode and L["war mode warning on."] or L["war mode warning off."])
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
        return
    end

    ns.db.warn = ns.db.warn == false
    ns.Print(ns.db.warn and L["gear warning on."] or L["gear warning off."])
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
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

-- Instrumentacao da APARENCIA. O usuario relatou duas vezes que a troca de transmog "nao troca e
-- nao gera nenhum erro", e a segunda vez com o passo ja conferindo o resultado. Sem erro sobram
-- exatamente tres hipoteses, e nenhuma delas se decide lendo codigo em disco:
--
--   A. o passo e PULADO -- `GetActiveOutfitID()` ja devolve o ID que o conjunto quer;
--   B. a chamada e ACEITA e a confirmacao passa, mas a aparencia nao muda de verdade;
--   C. a chamada e RECUSADA em silencio. A fonte do 12.1.0 mostra TRES portas que recusam sem
--      dizer nada, e nenhuma delas o addon consultava:
--
--        * RECARGA. Trocar de aparencia a mao gasta a magia 1247613
--          (`Constants.TransmogOutfitDataConsts.EQUIP_TRANSMOG_OUTFIT_MANUAL_SPELL_ID`), e a
--          propria UI do jogo desenha o cooldown por cima do botao
--          (`Blizzard_TransmogTemplates.lua:191-198`). Em recarga, nao troca e nao avisa. Esta e
--          a suspeita mais forte para quem esta TESTANDO -- trocar varias vezes seguidas e
--          exatamente o que mantem a recarga de pe;
--        * CONJUNTO TRAVADO (`IsLockedOutfit`), que a UI marca com um cadeado (`:80-82`);
--        * EVENTO DE ESTILO em andamento (`InTransmogEvent`): durante ele a UI DESABILITA todo
--          conjunto que nao seja do evento (`:85-87`).
--
--      E ha uma quarta possibilidade, de porta errada: a UI do jogo NAO usa `ChangeToOutfit`.
--      O botao de conjunto chama `ChangeDisplayedOutfit(outfitID, trigger, toggleLock,
--      allowRemoveOutfit)` (`Blizzard_TransmogTemplates.lua:72`) -- por outfitID, com o gatilho
--      de situacao. `ChangeToOutfit` e o caminho de macro/slash, por indice.
--
-- Este comando distingue as tres em uma execucao. `/rs transmog` mostra o estado; `/rs transmog
-- <indice>` chama a API e le o ID ativo ANTES, LOGO DEPOIS e meio segundo depois -- porque nao
-- esta verificado que a troca vale no mesmo quadro, e essa era a duvida que sobrava.
-- Instrumentacao do AVISO DE EQUIPAMENTO. Seis portas fecham esse caminho e nenhuma escreve
-- nada; `/rs alert` mostra as seis de uma vez. Ver `Alert.Diagnose`.
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

    -- QUE FUNCOES EXISTEM. Uma delas faltando explica tudo, e nao custa nada perguntar.
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
    ---Devolve o texto do que esta impedindo, ou nil quando nada esta.
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
    ---O sistema de conjuntos do Midnight troca aparencia SOZINHO por situacao, e duas das
    ---situacoes sao `Specialization` e `EquipmentSet`
    ---(`TransmogOutfitConstantsDocumentation.lua:373-374`) -- exatamente os dois passos que a
    ---corrente do addon executa antes da aparencia. Se isso estiver ligado, o jogo pode estar
    ---trocando por conta propria em cima do que pedimos, e isso nao aparece como erro em lugar
    ---nenhum. Ler o estado e barato e responde.
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

        -- E O QUE CADA CONJUNTO QUER, resolvido do mesmo jeito que o passo resolve. Se o indice
        -- sair `nil` aqui, o conjunto guarda um `outfitID` que nao existe mais.
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

    -- AS DUAS PORTAS DE ENTRADA, na mesma execucao, porque a duvida e qual delas serve a addon:
    --
    --   `ChangeToOutfit(indice, allowRemove)`  -- caminho de macro/slash, por INDICE;
    --   `ChangeDisplayedOutfit(id, gatilho, travar, allowRemove)` -- o que o BOTAO do jogo usa.
    --
    -- `allowRemoveOutfit = false` nas duas: com `true`, pedir a aparencia que ja esta posta e
    -- tratado como LIMPAR (`SlashCommands.lua:1714`), e isso confundiria a leitura -- pareceria
    -- que a chamada nao fez nada, quando fez o oposto.
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

        -- A PRIMEIRA PORTA NAO PEGOU. Tenta a que o jogo usa, com o mesmo alvo.
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
                -- O ESPERADO. As duas sao PROTEGIDAS: o autor do Plumber registrou isso
                -- ("The API to activate outfit C_TransmogOutfitInfo.ChangeDisplayedOutfit is
                -- protected"), o patch 12.0.5 adicionou uma acao segura `"outfit"` justamente por
                -- causa disso, e nenhum dos 117 addons instalados chama as duas funcoes.
                --
                -- O comando continua tentando porque prova, na maquina do jogador, o que aqui e
                -- so citacao -- e porque se um dia a Blizzard liberar, ele avisa.
                ns.Print("|cffff5555nenhuma das duas trocou -- e e o esperado.|r As duas sao "
                    .. "protegidas; addon nao troca aparencia.")
                ns.Print("quem troca e o |cffffd100clique no botao Carregar|r da janela do "
                    .. "addon, que carrega a acao segura de aparencia.")
            end

            -- "SO TROCOU A APARENCIA DA ARMA" foi o relato de 06/09, e ele nao se explica por
            -- nenhuma das portas: elas sao tudo-ou-nada. Explica-se por peca -- ha um enum
            -- inteiro de erro POR PECA (`TransmogOutfitSlotError`: NoItem, NotSoulbound,
            -- Legendary, InvalidItemType, Mismatch, CannotUseItem, InvalidSlotForRace...) --
            -- ou pelo jogo ter trocado sozinho por situacao. Os dois aparecem aqui.
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

-- Instrumentacao, pelo mesmo motivo do `/rs gear`: `FROM_GAME` depende de globais do cliente, e
-- global que nao existe nao avisa nada — o rotulo apenas continua em ingles, o que e
-- indistinguivel de "esta certo assim". Uma linha de saida encerra a duvida.
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

-- O DIARIO DA TROCA. Pergunta literal do usuario depois de a troca falhar de novo: "tu ta
-- salvando logs para poder entender os problemas?". A resposta era nao, e por isso as rodadas
-- anteriores foram eu adivinhando qual passo falhou e ele me contando por escrito.
--
-- `/rs log` mostra as ultimas linhas no chat -- resolve o caso simples sem sair do jogo. O
-- arquivo em SavedVariables e quem responde o caso dificil, e ele so e escrito no `/reload` ou
-- no logout: por isso a mensagem diz isso em vez de deixar o jogador procurar um arquivo vazio.
commands["log"] = function(rest)
    local arg = rest and rest:lower():match("^%S*")

    if arg == "clear" then
        ns.Log.Clear()
        ns.Log.ClearErrors()
        ns.Print(L["log cleared."])
        return
    end

    -- OS ERROS PRIMEIRO, e no chat. Ler o arquivo exige `/reload` e sair do jogo; a contagem
    -- aqui responde "aconteceu alguma coisa?" sem nada disso.
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
    print("  /rs gear            " .. L["shows what each slot is reading as"])
    print("  /rs transmog        " .. L["shows the appearance sets and tests the switch"])
    print("  /rs i18n            " .. L["checks the labels taken from the game"])
    print("  /rs warn            " .. L["turns the gear warning on or off"])
    print("  /rs ready           " .. L["turns the ready check summary on or off"])
    print("  /rs unmute          " .. L["re-enables warnings you silenced"])
    print("  /rs log [clear]     " .. L["shows the log of the last swaps"])
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

-- RocketSwap | Alert.lua
-- Três avisos, e os três funcionam SEM que o jogador crie um conjunto:
--
--   1. Equipamento errado para o conteúdo — de PvE em arena, de PvP em masmorra.
--   2. No ready check, um resumo do que você está usando, para o grupo conferir antes de puxar.
--   3. No convite da fila de PvP, o mesmo resumo — e ali ele vale mais: dentro da partida a
--      restrição de addon fecha a troca do começo ao fim, então o convite é a última janela.
--
-- O MODO DE FALHA DESTE ARQUIVO NÃO É ERRO DE LUA — é o usuário desligar porque encheu o saco.
-- O critério de aceitação é: quem fez tudo certo por duas semanas viu o addon zero vezes.
-- Daí as quatro comportas antes de qualquer pixel:
--
--   a) DÁ PARA CONSERTAR? Em combate, ou com a restrição já ativa, o aviso cala. Aviso sobre o
--      que não tem mais conserto é ruído puro.
--   b) A LEITURA É CONFIÁVEL? Se todo slot lido deu errado, é a detecção que falhou, não o
--      jogador que errou dezesseis peças (ver `Gear.LooksReliable`).
--   c) JÁ AVISEI ISSO? Mesma situação, mesma natureza: cala.
--   d) O USUÁRIO MANDOU CALAR? Silêncio persistido, por slot e por situação.
--
-- `ADDON_RESTRICTION_STATE_CHANGED` é a última chamada: a documentação da Blizzard diz que ele
-- dispara **antes** da restrição ativar. E `IsAddOnRestrictionActive` "will always return false
-- during dispatch" desse evento — por isso lemos o `state` do payload, nunca a função.
local ADDON, ns = ...
local L = ns.L

local Alert = {}
ns.Alert = Alert

local frame, ui
local lastKey            -- a última situação avisada, para não repetir

--------------------------------------------------------------------------------
-- Contexto
--------------------------------------------------------------------------------
---Onde estamos? "pvp", "pve" ou nil (mundo aberto: o addon não opina).
function Alert.Context()
    local inInstance, instanceType = IsInInstance()
    if inInstance then
        if instanceType == "arena" or instanceType == "pvp" then return "pvp" end
        if instanceType == "party" or instanceType == "raid" then return "pve" end
        return nil
    end

    -- FILA DE PvP: qualquer uma conta, inclusive a espera.
    --
    -- ⚑ ANTES SÓ VALIAM `"confirm"` E `"active"`, e `"confirm"` **não é a espera** — é o estouro
    -- da fila, o convite com contagem para aceitar. (O DBM prova: ele só cria a barra de "tempo
    -- restante para aceitar uma fila" quando o status vira `"confirm"`, medindo-a com
    -- `GetBattlefieldPortExpiration`.) Então, no momento literal do pedido do usuário — *"quando
    -- dou fila em BG, arena"* — o contexto era `nil` e o aviso morria antes de ler uma peça.
    --
    -- A lista agora é a do que NÃO vale, e isso é de propósito: o nome literal do status de
    -- espera não deu para provar de disco (nenhum addon instalado o compara), e um teste
    -- positivo dependeria de acertar esse nome. O negativo não depende.
    if GetMaxBattlefieldID and GetBattlefieldStatus then
        for i = 1, (GetMaxBattlefieldID() or 0) do
            local status = GetBattlefieldStatus(i)
            if status ~= nil and status ~= "none" and status ~= "error" then
                return "pvp"
            end
        end
    end

    -- MODO GUERRA: pedido do usuário — *"inclusive quando seto para pvp, habilitando o war mode
    -- on, sem avisos"*.
    --
    -- O mundo aberto era excluído de propósito ("o addon não opina"), e War Mode não era
    -- consultado em lugar nenhum. Mas com ele ligado o jogador está aberto a PvP, e é isso que
    -- ele quis dizer com "seto para pvp".
    --
    -- Devolve um contexto PRÓPRIO, e não `"pvp"`, porque a situação é outra: com War Mode ligado
    -- a maior parte do tempo é PvE (missões, world quests). Tratá-lo como arena faria o aviso
    -- gritar "equipamento de PvE numa partida de PvP" para quem está farmando — e o mesmo texto
    -- para duas situações diferentes é o que transforma aviso em ruído.
    if C_PvP and C_PvP.IsWarModeDesired then
        local ok, ligado = pcall(C_PvP.IsWarModeDesired)
        if ok and ligado then return "warmode" end
    end

    return nil
end

---Dá para consertar agora?
local function CanFix()
    if InCombatLockdown() then return false end

    if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState and Enum
        and Enum.AddOnRestrictionType and Enum.AddOnRestrictionState then
        for _, kind in ipairs({ Enum.AddOnRestrictionType.PvPMatch,
                               Enum.AddOnRestrictionType.Encounter,
                               Enum.AddOnRestrictionType.ChallengeMode }) do
            local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, kind)
            if ok and state == Enum.AddOnRestrictionState.Active then return false end
        end
    end
    return true
end

---TODA COMPORTA DO CAMINHO DO AVISO, num retrato so.
---
---⚑ POR QUE ISTO EXISTE. O usuario relatou, em 08/09/2026: *"o aviso de item pvp para conteudo
---pve ta funcionando. porem o de pve no pvp, ainda nao vi funcionar, quando dou fila em BG,
---arena, ele nao avisa nada sobre meus itens"* -- e depois *"inclusive quando seto para pvp,
---habilitando o war mode on, sem avisos"*.
---
---O caminho ate o aviso tem SEIS portas, e cada uma fecha em silencio:
---
---  1. `ns.db.warn == false`            -- desligado pelo jogador
---  2. `Alert.Context()` devolve nil    -- o addon nao opina aqui
---  3. `CanFix()` devolve false         -- combate, ou restricao de addon ativa
---  4. `Gear.PatternReady()` false      -- a deteccao nao funciona neste idioma
---  5. `#wrong == 0`                    -- nao ha o que avisar
---  6. `Gear.LooksReliable()` false     -- todos errados = leitura suspeita
---
---Nenhuma delas escreve nada em lugar nenhum. Com seis portas mudas, adivinhar qual fechou custa
---uma ida ao jogo por palpite; este retrato custa uma.
---
---@return table estado
function Alert.Diagnose()
    local contexto = Alert.Context()
    local inInstance, instanceType = IsInInstance()

    local filas = {}
    if GetMaxBattlefieldID then
        for i = 1, (GetMaxBattlefieldID() or 0) do
            local status, mapa = GetBattlefieldStatus(i)
            if status and status ~= "none" then
                filas[#filas + 1] = { id = i, status = status, mapa = mapa }
            end
        end
    end

    -- WAR MODE. O addon nao consulta isto em lugar nenhum hoje -- e justamente por isso o
    -- diagnostico consulta: para o retrato mostrar o que o addon esta ignorando.
    local guerra
    if C_PvP and C_PvP.IsWarModeDesired then
        local ok, ativo = pcall(C_PvP.IsWarModeDesired)
        if ok then guerra = ativo end
    end

    local restricoes = {}
    if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState and Enum
        and Enum.AddOnRestrictionType and Enum.AddOnRestrictionState then
        for nome, kind in pairs({ PvPMatch = Enum.AddOnRestrictionType.PvPMatch,
                                  Encounter = Enum.AddOnRestrictionType.Encounter,
                                  ChallengeMode = Enum.AddOnRestrictionType.ChallengeMode }) do
            local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, kind)
            restricoes[nome] = ok and (state == Enum.AddOnRestrictionState.Active) or false
        end
    end

    -- AS DUAS DIRECOES, sempre. Perguntar so a do contexto atual esconde o caso em que o
    -- contexto e que esta errado -- que e exatamente uma das suspeitas.
    local erradoPvP, lidoPvP, vestido = ns.Gear.Wrong(true, ns.db and ns.db.mutedSlots)
    local erradoPvE, lidoPvE = ns.Gear.Wrong(false, ns.db and ns.db.mutedSlots)

    return {
        contexto = contexto,
        instancia = inInstance and instanceType or nil,
        filas = filas,
        warMode = guerra,
        emCombate = InCombatLockdown() and true or false,
        restricoes = restricoes,
        podeConsertar = CanFix(),
        avisoLigado = not (ns.db and ns.db.warn == false),
        -- A SÉTIMA PORTA, e ela é nova: com Modo Guerra ligado o aviso só sai se o jogador tiver
        -- marcado a opção. Sem esta linha o retrato diria "tudo pronto para avisar" e o aviso não
        -- sairia — que é o tipo de silêncio que este diagnóstico existe para não ter.
        avisoModoGuerra = ns.db and ns.db.warnWarMode == true or false,
        deteccaoViva = ns.Gear.PatternReady(),
        vestido = vestido,
        comoPvP = { errado = #erradoPvP, lido = lidoPvP,
            confiavel = ns.Gear.LooksReliable(erradoPvP, lidoPvP) },
        comoPvE = { errado = #erradoPvE, lido = lidoPvE,
            confiavel = ns.Gear.LooksReliable(erradoPvE, lidoPvE) },
    }
end

--------------------------------------------------------------------------------
-- A janela do aviso
--------------------------------------------------------------------------------
local function Build()
    if ui then return ui end

    ui = CreateFrame("Frame", ADDON .. "Alert", UIParent, "ButtonFrameTemplate")
    ui:SetSize(360, 190)
    ui:SetPoint("TOP", UIParent, "TOP", 0, -180)
    ui:SetFrameStrata("DIALOG")
    ui:SetMovable(true)
    ui:EnableMouse(true)
    ui:RegisterForDrag("LeftButton")
    ui:SetScript("OnDragStart", ui.StartMoving)
    ui:SetScript("OnDragStop", ui.StopMovingOrSizing)
    ui:Hide()

    if ui.SetTitle then ui:SetTitle(ADDON) end
    if ui.SetPortraitToAsset then ui:SetPortraitToAsset(ns.FirstIcon(ns.ICON_CANDIDATES)) end
    if ui.Inset then ui.Inset:Hide() end

    ui.headline = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.headline:SetPoint("TOPLEFT", 60, -30)
    ui.headline:SetPoint("RIGHT", -14, 0)
    ui.headline:SetJustifyH("LEFT")
    ui.headline:SetTextColor(1, 0.82, 0)

    ui.body = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.body:SetPoint("TOPLEFT", 14, -64)
    ui.body:SetPoint("RIGHT", -14, 0)
    ui.body:SetJustifyH("LEFT")
    ui.body:SetSpacing(3)

    ui.fix = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
    ui.fix:SetSize(150, 22)
    ui.fix:SetPoint("BOTTOMLEFT", 14, 8)

    ui.mute = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
    ui.mute:SetSize(150, 22)
    ui.mute:SetPoint("BOTTOMRIGHT", -14, 8)
    ui.mute:SetText(L["Don't warn here"])
    ui.mute:SetScript("OnClick", function()
        if lastKey then
            ns.db.muted = ns.db.muted or {}
            ns.db.muted[lastKey] = true
        end
        ui:Hide()
    end)

    tinsert(UISpecialFrames, ui:GetName())
    return ui
end

---O aviso esta na tela? E o que ele esta dizendo?
---
---⚑ EXISTEM PORQUE O TESTE ANTERIOR NAO TESTAVA NADA. Ele afirmava
---`ns.Alert.__shown ~= true` -- e `__shown` nunca era escrito em `Alert`, so nos frames do
---simulador. A comparacao era `nil ~= true`, verdadeira sempre: o check passava com o aviso
---aparecendo ou nao. Um teste que nao pode reprovar e um comentario com sintaxe de teste.
function Alert.__Shown()
    return ui ~= nil and ui:IsShown() and true or false
end

---O botao de consertar esta oferecido? E o que separa "o addon avisou" de "o addon avisou E
---consegue resolver" -- as duas coisas deixaram de andar juntas.
function Alert.__FixShown()
    return ui ~= nil and ui.fix ~= nil and ui.fix:IsShown() and true or false
end

function Alert.__Headline()
    return ui and ui.headline and ui.headline:GetText() or nil
end

function Alert.Hide()
    if ui then ui:Hide() end
end

--------------------------------------------------------------------------------
-- Aviso de equipamento errado
--------------------------------------------------------------------------------
---Um conjunto que sirva para o contexto, se o jogador tiver criado algum. É o que transforma
---o aviso de "você errou" em "quer que eu conserte?". Sem conjuntos, o aviso só aponta.
---Este contexto pede equipamento de PvP?
---
---São TRÊS contextos agora ("pvp", "warmode", "pve") e dois deles pedem PvP. Perguntar
---`context == "pvp"` em cada lugar deixaria o modo guerra silenciosamente do lado do PvE — que é
---o oposto do que ele significa.
local function WantsPvP(context)
    return context == "pvp" or context == "warmode"
end

local function PresetFor(context)
    for _, preset in ipairs(ns.db.presets or {}) do
        if preset.gear then
            local wrong, read = ns.Gear.Wrong(WantsPvP(context))
            -- Um conjunto serve se, aplicado, ele resolveria: usamos o próprio nome como
            -- pista quando não dá para simular (não dá — as peças do conjunto não estão
            -- vestidas). Nome é heurística, e por isso é só sugestão de botão, nunca ação
            -- automática.
            local name = (preset.name or ""):lower()
            local looksPvP = name:find("pvp") or name:find("arena") or name:find("bg")
                or name:find("campo")
            if WantsPvP(context) == (looksPvP ~= nil) then
                return preset, wrong, read
            end
        end
    end
    return nil
end

function Alert.Check(reason)
    if not ns.db or ns.db.warn == false then return end

    local context = Alert.Context()
    if not context then return end

    -- ⚑ O AVISO DE MODO GUERRA É OPT-IN (`warnWarMode`, padrão desligado). Pedido de 12/09:
    -- *"tira o alerta dos itens de pvp em mundo aberto no war mode, ou transforma em opção por
    -- padrão desmarcada"*.
    --
    -- A COMPORTA FICA AQUI, E NÃO EM `Alert.Context()`, de propósito: o contexto continua sendo
    -- "warmode" para `/rs gear` (o diagnóstico precisa dizer onde o jogador está) e para o resumo
    -- do ready check. Quem cala é o aviso, que é o que incomodava. Mexer no contexto apagaria
    -- também as duas coisas que ninguém pediu para apagar.
    if context == "warmode" and ns.db.warnWarMode ~= true then return end

    -- ⚑ EM COMBATE O AVISO CALA, e só em combate. Antes a comporta era `CanFix()`, que também
    -- fecha quando a **restrição de addon** está ativa — e a documentação de API deste cliente
    -- (12.1.0.69587) define `Enum.AddOnRestrictionType.PvPMatch` como *"the player is in an
    -- active and incomplete PvP match"*: uma janela fechada do começo ao fim da partida.
    --
    -- Isso desligava o aviso durante TODA arena e TODO campo de batalha, e é parte da assimetria
    -- que o usuário relatou: em PvE as restrições equivalentes (`Encounter`, `ChallengeMode`)
    -- deixam janelas livres — masmorra fora de encontro, raide entre bosses — enquanto uma
    -- partida de PvP não deixa nenhuma.
    --
    -- E a dependência era errada de origem: **saber não depende de poder consertar**. Quem
    -- descobre no meio da partida que está de PvE ao menos sai e volta certo. O que depende de
    -- poder consertar é o BOTÃO, e ele já sabe se esconder.
    if InCombatLockdown() then return end

    local wrong, read = ns.Gear.Wrong(WantsPvP(context), ns.db.mutedSlots)
    if #wrong == 0 then
        Alert.Hide()
        return
    end
    if not ns.Gear.LooksReliable(wrong, read) then return end

    local key = context .. ":" .. (#wrong > 0 and "gear" or "")
    if ns.db.muted and ns.db.muted[key] then return end
    if key == lastKey and ui and ui:IsShown() then return end
    lastKey = key

    -- O texto do jogo, no lugar do jogo: aviso amarelo abaixo do centro. É onde a Blizzard
    -- põe recado desta natureza, e o helper já cuida de cor e de repetição.
    -- A REDAÇÃO É DO CONTEXTO, e o modo guerra tem a dele.
    --
    -- Com War Mode ligado a maior parte do tempo é PvE — missão, world quest, farm. Dizer
    -- "equipamento de PvE numa partida de PvP" ali seria falso (não há partida) e viraria ruído
    -- em quem só quer o bônus de experiência. O texto avisa que ele está EXPOSTO, que é o fato.
    local titulo = L["PvP gear in PvE content."]
    if context == "pvp" then
        titulo = L["PvE gear in a PvP match."]
    elseif context == "warmode" then
        titulo = L["PvE gear with War Mode on."]
    end

    if UIErrorsFrame and UIErrorsFrame.AddExternalWarningMessage then
        pcall(UIErrorsFrame.AddExternalWarningMessage, UIErrorsFrame, titulo)
    end

    Build()

    ui.headline:SetText(titulo)

    local lines = {}
    for i = 1, math.min(#wrong, 6) do
        lines[#lines + 1] = "• " .. ns.Gear.SlotName(wrong[i].slot) .. "   " .. wrong[i].link
    end
    if #wrong > 6 then
        lines[#lines + 1] = format(L["...and %d more."], #wrong - 6)
    end
    ui.body:SetText(table.concat(lines, "\n"))

    -- O BOTÃO, sim, depende de poder consertar: oferecer "Carregar <conjunto>" no meio de uma
    -- partida, onde a troca é recusada, seria um botão que não faz nada.
    local preset = CanFix() and PresetFor(context) or nil
    if preset then
        ui.fix:SetText(format(L["Load %s"], preset.name))
        ui.fix:SetScript("OnClick", function()
            ns.Data.Apply(preset, function(text) ns.Print(text) end)
            ui:Hide()
        end)
        ui.fix:Show()
    else
        ui.fix:Hide()
    end

    ui:SetHeight(120 + math.min(#wrong, 7) * 14)
    ui:Show()
end

--------------------------------------------------------------------------------
-- Ready check: o resumo antes de puxar
--------------------------------------------------------------------------------
---O que você está usando agora: os três campos, com o RÓTULO de cada um.
---
---Não é aviso e não julga nada: é a conferência que o líder pede quando manda o ready check.
---
---OS RÓTULOS SÃO OS DA PRÓPRIA JANELA DO ADDON — `Especialização`, `Talentos`, `Itens` — e essa
---é a razão de eles serem esses e não outros. O jogador que abre `/rs` lê exatamente essas três
---palavras ao lado dos três combos; o resumo usando outras o obrigaria a aprender dois
---vocabulários para a mesma coisa. Nenhuma chave nova: `L["Specialization"]`, `L["Talents"]` e
---`L["Gear"]` já existem e já são o que o editor mostra.
---
---E é por isso que o terceiro NÃO vem do jogo. As duas primeiras vêm (`SPECIALIZATION` e
---`TALENTS`, via `FROM_GAME`), mas para itens não há global limpa e há uma armadilha registrada
---em `Locales/enUS.lua`: em pt-BR o jogo chama **loadout de talentos** de "equipamento" e
---**conjunto de itens** de "conjunto". Este addon foge das duas de propósito, porque ele existe
---justamente para quem já confunde as duas coisas — e o pedido que trouxe estes rótulos
---("não sei o que é o que") é essa confusão em pessoa.
---
---@param separator string|nil `nil` = uma linha (chat); `"\n"` = uma por linha (caixa)
function Alert.Summary(separator)
    local parts = {}

    ---Um campo do resumo. `rótulo: valor`, e o rótulo é o mesmo do editor.
    ---
    ---VAZIO É `(nenhum)`, e não mais "(sem conjunto de itens)". As frases longas existiam porque
    ---**elas eram o único contexto** — sem rótulo, "(sem conjunto de itens)" era a única forma de
    ---saber de que campo se tratava. Com o rótulo na frente elas passaram a repetir a própria
    ---etiqueta ("Itens: (sem conjunto de itens)") e ainda arrastavam duas palavras que este addon
    ---evita: **"loadout"**, que o cliente traduz como "equipamento" em pt-BR, e **"conjunto"**,
    ---que aqui é o nome dos PRESETS (`L["Presets"] = "Conjuntos"`) — o campo e o contêiner
    ---passavam a dividir o nome.
    ---
    ---`L["(none)"]` já existe e já é o que os combos do editor mostram no mesmo caso. Mesmo
    ---vocabulário, de novo.
    local function Add(label, value)
        parts[#parts + 1] = label .. ": " .. value
    end

    local specIndex = ns.Data.GetCurrentSpecIndex()
    local spec = ns.Data.GetSpecByIndex(specIndex)
    if spec then Add(L["Specialization"], spec.name) end

    if spec then
        local configID = ns.Data.GetActiveLoadoutID(spec.id)
        local name = configID and ns.Data.LoadoutName(spec.id, configID)
        Add(L["Talents"], name or L["(none)"])
    end

    -- ⚑ `(nenhum)` SÓ QUANDO NÃO HÁ NADA. `isEquipped` é tudo-ou-nada: trocar UMA peça de um
    -- conjunto de 14 apaga a flag, e o resumo dizia "Itens: (nenhum)" para quem estava com o
    -- conjunto quase inteiro no corpo. Relato do usuário: *"fica com a mensagem de (nenhum), uma
    -- mensagem errada, porque ele tá com os itens só que um ou mais não estão salvos"*.
    --
    -- Dizer o nome com a contagem é o que separa os dois casos que a frase antiga fundia: quem
    -- esqueceu de carregar conjunto nenhum e quem trocou uma peça e não salvou. O primeiro precisa
    -- carregar; o segundo precisa SALVAR — e é o segundo que aparece no ready check.
    local setID = ns.Data.GetEquippedSetID()
    if setID then
        Add(L["Gear"], ns.Data.GearSetName(setID))
    else
        local _, vestidas, itens, nome = ns.Data.PartialGearSet()
        if nome then
            Add(L["Gear"], format(L["%s (%d of %d pieces)"], nome, vestidas, itens))
        else
            Add(L["Gear"], L["(none)"])
        end
    end

    -- UMA FUNÇÃO SÓ, com um separador, e não duas funções. A regra vem de tropeço próprio neste
    -- projeto: duas fontes de verdade para a mesma informação divergem na primeira mudança —
    -- foi assim que a lista de contornos do configurador ficou sem o "médio".
    return table.concat(parts, separator or "  ·  ")
end

--------------------------------------------------------------------------------
-- Fila estourou: o resumo antes de aceitar
--------------------------------------------------------------------------------
---O convite da fila de PvP — o momento em que dá para consertar, e o último.
---
---Pedido do usuário (18/09/2026): *"quando chama para entrar na arena após ter esperado na fila,
---tem como dar o aviso de qual build tá setado?"*.
---
---É a mesma pergunta do ready check, num instante em que ela vale mais: dentro da arena a troca
---de talentos é recusada pela restrição de addon, e a partida inteira é uma janela fechada (ver
---o comentário de `Alert.Check`). Quem descobre depois de aceitar, descobre tarde.
---
---`GetBattlefieldStatus(i)` devolve `"confirm"` exatamente enquanto o convite está na tela
---(documentada no cliente 12.1.5; é o mesmo caminho que o DBM usa para a barra de tempo do
---convite, `DBM-Core.lua:3360-3364`). O 2º retorno é o nome do mapa e o 3º, o tamanho do time
---da arena — 0 em campo de batalha.
---
---UMA VEZ POR CONVITE. `UPDATE_BATTLEFIELD_STATUS` dispara várias vezes com o mesmo `"confirm"`
---(o relógio do convite anda), e a caixa espera OK: sem trava, cada disparo empilharia a mesma
---caixa por cima da anterior.
local queueShown = false

function Alert.OnQueuePop()
    if not GetBattlefieldStatus then return end

    -- `GetMaxBattlefieldID` é quem diz quantas filas existem. Sem ela, duas — que é o que o DBM
    -- percorre, e é o teto histórico.
    local quantas = (GetMaxBattlefieldID and GetMaxBattlefieldID()) or 2

    local mapa, teamSize
    for i = 1, quantas do
        local ok, status, m, t = pcall(GetBattlefieldStatus, i)
        if ok and status == "confirm" then
            mapa, teamSize = m, t
            break
        end
    end

    -- ⚑ UM AVISO ENQUANTO HOUVER CONVITE, e não um por fila. O resumo fala da SUA build, que é a
    -- mesma para as duas filas — com uma trava por índice, duas filas estourando juntas abriam a
    -- mesma caixa duas vezes, e a segunda só substituía a primeira (a chave do diálogo é uma só).
    --
    -- E uma vez por convite, não por disparo: `UPDATE_BATTLEFIELD_STATUS` dispara várias vezes
    -- com o mesmo convite na tela, porque o relógio dele anda.
    if mapa ~= nil or teamSize ~= nil then
        if not queueShown and ns.db and ns.db.queuePop ~= false then
            queueShown = true
            Alert.ShowQueueSummary(mapa, teamSize)
        end
    elseif queueShown then
        -- Saiu do convite (aceitou, recusou ou expirou): a caixa perde o assunto e some, e a
        -- trava libera o próximo convite. Sem isto, a caixa ficaria pendurada dentro da partida,
        -- que é onde ela não serve para mais nada.
        queueShown = false
        if StaticPopup_Hide then pcall(StaticPopup_Hide, "ROCKETSWAP_READY_CHECK") end
    end
end

---A caixa do convite. Mesmo formato do ready check — um rótulo por linha, esperando OK.
---
---O TÍTULO DIZ O MAPA quando o jogo informa: "Nagrand Arena" responde *por que isto apareceu* sem
---gastar uma frase explicando. Sem o nome, a frase genérica.
function Alert.ShowQueueSummary(mapa, teamSize)
    local resumo = Alert.Summary()
    local titulo = L["Queue is up — check before you enter"]
    if type(mapa) == "string" and mapa ~= "" then
        if type(teamSize) == "number" and teamSize > 0 then
            titulo = format("%s (%dv%d)", mapa, teamSize, teamSize)
        else
            titulo = mapa
        end
    end

    ns.Print(L["queue is up:"] .. " " .. resumo)

    if StaticPopup_Show then
        local ok = pcall(StaticPopup_Show, "ROCKETSWAP_READY_CHECK",
            titulo .. "\n\n" .. Alert.Summary("\n"))
        if not ok and RaidWarningUtil and RaidWarningUtil.AddMessage then
            pcall(RaidWarningUtil.AddMessage, resumo, NORMAL_FONT_COLOR, 5)
        end
    end
end

-- A CAIXA DE CONFIRMAÇÃO DO RESUMO.
--
-- O resumo era chat + aviso de raide, e os dois SOMEM sozinhos. Pedido do usuário: *"como mostra
-- o aviso e some, o usuário pode nem ver"*. Ele tem razão, e o ready check é justamente o momento
-- em que a pessoa está olhando para outra coisa — para o botão de "Pronto".
--
-- Espera um OK, e é o ponto: a caixa fica até alguém a fechar, então o resumo não depende de o
-- jogador estar olhando na hora certa.
--
-- `timeout = 0` — não fecha sozinha, pelo mesmo motivo de existir.
-- `whileDead = 1` — morto no meio de uma tentativa é exatamente quando se pede ready check.
-- `hideOnEscape = 1` — Esc fecha, como em toda caixa do jogo; obrigar o clique seria birra.
--
-- O nome tem prefixo do addon porque `StaticPopupDialogs` é uma tabela GLOBAL, compartilhada com
-- o jogo e com todos os addons: uma chave genérica sobrescreveria a de outro.
-- Dentro do `if`: `StaticPopupDialogs` é global do jogo e sempre existe, mas indexar global nula
-- em escopo de ARQUIVO derruba o addon inteiro no carregamento — e perder o addon por causa de
-- uma caixa de aviso é troca ruim.
if StaticPopupDialogs then
    StaticPopupDialogs["ROCKETSWAP_READY_CHECK"] = {
        text = "%s",
        button1 = OKAY,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        -- Sem `OnAccept`: a caixa é informativa, o OK só a fecha. Ação escondida atrás de um OK
        -- que diz "OK" é o tipo de coisa que o jogador não espera.
    }
end

function Alert.OnReadyCheck()
    if not ns.db or ns.db.readyCheck == false then return end

    local resumo = Alert.Summary()
    ns.Print(L["ready check:"] .. " " .. resumo)

    -- A CAIXA É A PRINCIPAL, e o chat vira registro. O aviso de raide saiu: ele também some, e
    -- somado à caixa seria a mesma informação em dois lugares, um deles inútil.
    --
    -- `pcall` porque `StaticPopup_Show` **dá erro** quando o diálogo não existe
    -- (`StaticPopup.lua:302-304`, `error("Dialog "..which.." does not exist.")`) — e não existir é
    -- possível se outro addon limpar a tabela global.
    if StaticPopup_Show then
        -- UMA LINHA POR CAMPO na caixa, e tudo numa só no chat. A caixa tem altura livre e o
        -- chat não; e é na caixa que o jogador vai parar para ler.
        -- TÍTULO SEM DOIS-PONTOS. `L["ready check:"]` é PREFIXO de linha de chat, e lá o
        -- dois-pontos está certo; como título de caixa, seguido de linha em branco, ele fica
        -- pendurado. A linha de chat chegava a ter três: "RocketSwap: conferência: Especialização:
        -- Gelido".
        --
        -- E O TÍTULO NOMEIA O CONTEÚDO, não o ritual. O prefixo do chat continua dizendo
        -- "conferência" de propósito: lá ele responde *por que o addon falou sozinho* — alguém
        -- mandou o ready check — e essa é a dúvida de quem lê uma linha que apareceu no meio da
        -- conversa. Na caixa, o jogador já sabe por que ela abriu; o que ele precisa em meio
        -- segundo é saber **o que está olhando**.
        local ok = pcall(StaticPopup_Show, "ROCKETSWAP_READY_CHECK",
            L["What you are using"] .. "\n\n" .. Alert.Summary("\n"))
        if not ok and RaidWarningUtil and RaidWarningUtil.AddMessage then
            -- Só então o aviso do meio da tela, como rede: melhor um aviso que some do que nada.
            pcall(RaidWarningUtil.AddMessage, resumo, NORMAL_FONT_COLOR, 5)
        end
    end

    -- E de quebra: se o equipamento estiver errado para o conteúdo, é a hora de saber.
    Alert.Check("readycheck")
end

--------------------------------------------------------------------------------
-- Gatilhos
--------------------------------------------------------------------------------
function Alert.Create()
    if frame then return frame end

    -- ⚑ QUANDO OS DADOS DO ITEM CHEGAM, A CONTA REFAZ. `Gear` pede o carregamento do que leu como
    -- "não sei" e avisa por aqui; sem esta inscrição o pedido não serviria para nada -- o aviso
    -- ficaria com a leitura incompleta até o próximo gatilho, que pode não vir.
    --
    -- `lastKey = nil` porque o aviso recusa repetir a mesma chave enquanto está na tela: sem
    -- zerar, a reavaliação seria descartada justamente quando ela tem algo novo a dizer.
    ns.Gear.onItemLoaded = function()
        lastKey = nil
        Alert.Check("item carregado")
    end

    frame = CreateFrame("Frame", ADDON .. "AlertEvents")

    -- Entrar em instância: `PLAYER_ENTERING_WORLD` sozinho é cedo demais — o equipamento
    -- ainda não está carregado. Dois segundos é o que o TalentReminder usa, pelo mesmo motivo.
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
    frame:RegisterEvent("READY_CHECK")
    -- Estes só CANCELAM: podem esconder um aviso, nunca criar um.
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
    if C_EventUtils and C_EventUtils.IsEventValid
        and C_EventUtils.IsEventValid("ADDON_RESTRICTION_STATE_CHANGED") then
        frame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    end

    frame:SetScript("OnEvent", function(_, event, a, b)
        if event == "READY_CHECK" then
            Alert.OnReadyCheck()

        elseif event == "UPDATE_BATTLEFIELD_STATUS" then
            -- DUAS COISAS NO MESMO EVENTO, e na ordem certa: primeiro o resumo do convite, que é
            -- imediato e tem prazo (o convite expira), e só depois a checagem de equipamento, que
            -- espera os 2 segundos de sempre porque depende da tooltip ter carregado.
            Alert.OnQueuePop()
            C_Timer.After(2, function() Alert.Check(event) end)

        elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "EQUIPMENT_SWAP_FINISHED" then
            ns.Gear.ClearCache()
            lastKey = nil
            Alert.Hide()

            -- Mudou o equipamento: pede o que faltar. Sem isto, uma peça recém-equipada continua
            -- sem dados até alguém passar o mouse nela -- e foi assim que o aviso de 13/09 acusou
            -- duas peças de PvP de serem PvE.
            for _, slot in ipairs(ns.Gear.SLOTS) do
                ns.Gear.RequestLoad(slot)
            end

        elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
            -- `b` é o estado. `Activating` é a última chamada: ainda dá para trocar.
            if Enum and Enum.AddOnRestrictionState and b == Enum.AddOnRestrictionState.Activating then
                Alert.Check("restriction")
            end

        else
            C_Timer.After(2, function() Alert.Check(event) end)
        end
    end)

    return frame
end

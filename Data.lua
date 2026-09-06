-- RocketSwap | Data.lua
-- A ÚNICA camada que fala com a API do jogo. Nenhum outro arquivo chama `C_*`.
--
-- O QUE ESTE ADDON FAZ, E POR QUE ELE PRECISA EXISTIR:
--
-- O jogo já guarda tudo o que interessa. Ele guarda conjuntos de itens (Frost, Unholy, Blood,
-- PvP) e guarda loadouts de talentos (PvP, SBA ST, Deathbringer ST). O que ele **não** faz é
-- relacionar os dois de forma útil:
--
--   * `C_EquipmentSet.AssignSpecToEquipmentSet` amarra **um** conjunto por especialização.
--     Um Cavaleiro da Morte Gélido que tem um conjunto "Frost" e um conjunto "PvP" não
--     consegue expressar isso — as duas são a mesma spec.
--   * O jogo lembra **o último** loadout de talentos por spec. Mesmo problema: "PvP" e
--     "SBA ST" são as duas de Gélido.
--
-- Então a tabela `nome -> (spec, talentos, itens)` **tem** que morar no addon. É a camada
-- fina que falta, e é tudo o que o RocketSwap guarda. O resto é lido do jogo.
--
-- ORDEM DE APLICAÇÃO — não é arbitrária:
--
--   1. especialização   → é um CAST, pode falhar (`SPECIALIZATION_CHANGE_CAST_FAILED`)
--   2. talentos         → assíncrono, confirma em `TRAIT_CONFIG_UPDATED`
--   3. itens            → POR ÚLTIMO, de propósito
--
-- O passo 3 vem por último porque, ao trocar de spec, **o jogo equipa sozinho** o conjunto
-- amarrado àquela spec. Equipar antes seria sobrescrito pelo próprio jogo.
--
-- E TUDO ISSO FALHA EM SILÊNCIO. `UseEquipmentSet` não devolve erro. Por isso cada passo
-- espera o evento de confirmação e tem prazo — sem isso o addon diria "pronto" sem ter
-- feito nada, que é pior do que não ter addon.
local ADDON, ns = ...
local L = ns.L

local Data = {}
ns.Data = Data

-- Prazo de cada passo. Trocar de spec é o mais lento: tem cast e o servidor responde.
local STEP_TIMEOUT = 12

-- A MAGIA QUE A TROCA MANUAL DE APARENCIA GASTA, e a razao de ela ter uma.
--
-- Trocar de conjunto a mao nao e de graca no Midnight: consome
-- `Constants.TransmogOutfitDataConsts.EQUIP_TRANSMOG_OUTFIT_MANUAL_SPELL_ID`, e a propria UI do
-- jogo desenha a recarga por cima do botao do conjunto
-- (`Blizzard_Transmog/Blizzard_TransmogTemplates.lua:191-198`).
--
-- ISSO IMPORTA AQUI PORQUE E RECUSA SILENCIOSA: em recarga a chamada nao troca nada e nao
-- devolve erro nenhum -- que e exatamente o relato, duas vezes, do usuario. E quem esta TESTANDO
-- e quem mais cai nela: trocar de conjunto varias vezes seguidas mantem a recarga de pe.
--
-- O numero literal e o valor da constante no 12.1.0
-- (`Blizzard_APIDocumentationGenerated/TransmogOutfitConstantsDocumentation.lua:429`). Lemos da
-- constante quando ela existe e caimos no literal quando nao -- `Constants` e tabela do cliente e
-- pode nao estar carregada na ordem que esperamos.
local TRANSMOG_SPELL_ID = 1247613

local function TransmogSpellID()
    local consts = Constants and Constants.TransmogOutfitDataConsts
    local id = consts and consts.EQUIP_TRANSMOG_OUTFIT_MANUAL_SPELL_ID
    return type(id) == "number" and id or TRANSMOG_SPELL_ID
end

---O que esta impedindo a troca de aparencia AGORA, ou nil quando nada esta.
---
---As tres portas saem da UI nativa do conjunto, que consulta as tres antes de deixar clicar
---(`Blizzard_TransmogTemplates.lua:72-87,191-198`). Nenhuma delas devolve erro quando a troca e
---pedida assim mesmo: a chamada simplesmente nao faz nada. Perguntar ANTES e o que transforma
---"nao troca e nao gera nenhum erro" numa frase que diz o motivo.
---@param outfitID number|nil o conjunto alvo, para conferir se ELE esta travado
---@return string|nil
function Data.TransmogBlockedBy(outfitID)
    if not C_TransmogOutfitInfo then return nil end

    -- RECARGA. `GetSpellCooldown` devolve `{ startTime, duration, isEnabled, modRate }`, e a
    -- condicao de "esta em recarga" NAO e so `duration > 0`: e a mesma que a Blizzard usa no
    -- proprio `CooldownFrame_Set` (`Blizzard_FrameXMLUtil/Cooldown.lua:3`), que exige os TRES --
    --
    --     enable and enable ~= 0 and start > 0 and duration > 0
    --
    -- Ela guarda contra `duration > 0` com `start == 0`, entao esse caso acontece; espelhar o
    -- predicado dela e mais barato que descobrir quando.
    --
    -- `C_Spell and C_Spell.GetSpellCooldown` ANTES do `pcall`: o `pcall` protege a CHAMADA, nao
    -- a busca do argumento. `pcall(C_Spell.GetSpellCooldown, ...)` com `C_Spell` nulo estoura na
    -- indexacao, fora da protecao. Pego pelo harness.
    local getCD = C_Spell and C_Spell.GetSpellCooldown
    local ok, cd = false, nil
    if getCD then ok, cd = pcall(getCD, TransmogSpellID()) end
    if ok and type(cd) == "table"
        and cd.isEnabled and cd.isEnabled ~= 0
        and type(cd.duration) == "number" and cd.duration > 0
        and type(cd.startTime) == "number" and cd.startTime > 0 then
        local resta = (cd.startTime + cd.duration) - GetTime()
        if resta > 0 then
            return format(L["changing appearance is on cooldown (%d s left)."], resta + 0.5)
        end
    end

    -- EVENTO DE ESTILO: durante ele a UI desabilita todo conjunto que nao seja do evento.
    if C_TransmogOutfitInfo.InTransmogEvent then
        local okEv, emEvento = pcall(C_TransmogOutfitInfo.InTransmogEvent)
        if okEv and emEvento then
            return L["a style event is running; appearances are locked."]
        end
    end

    -- CONJUNTO TRAVADO a uma situacao: a UI marca com cadeado.
    if outfitID and C_TransmogOutfitInfo.IsLockedOutfit then
        local okLk, travado = pcall(C_TransmogOutfitInfo.IsLockedOutfit, outfitID)
        if okLk and travado then
            return L["that appearance set is locked."]
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Leitura: o que o jogador já tem
--------------------------------------------------------------------------------
---As especializações da classe, na ordem em que o jogo as lista.
---
---`specIndex` (1..n) é o que as APIs de troca e de conjunto usam — **não** o `specID`.
---Confundir os dois é o erro clássico aqui: `AssignSpecToEquipmentSet` recebe índice.
function Data.GetSpecs()
    local out = {}
    local count = C_SpecializationInfo.GetNumSpecializations
        and C_SpecializationInfo.GetNumSpecializations() or GetNumSpecializations()
    if not count then return out end

    for index = 1, count do
        local id, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(index)
        if id then
            out[#out + 1] = { index = index, id = id, name = name or "?", icon = icon }
        end
    end
    return out
end

function Data.GetCurrentSpecIndex()
    local index = C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()
    if index == nil and GetSpecialization then index = GetSpecialization() end
    return index
end

function Data.GetSpecByIndex(index)
    if not index then return nil end
    for _, spec in ipairs(Data.GetSpecs()) do
        if spec.index == index then return spec end
    end
    return nil
end

---Loadouts de talento de uma especialização.
---
---O nome vem de `C_Traits.GetConfigInfo`, não do `C_ClassTalents` — este último só entrega
---os ids. A "Seleção Inicial" (starter build) não aparece aqui porque não é um config salvo.
function Data.GetLoadouts(specID)
    local out = {}
    if not specID or not C_ClassTalents or not C_ClassTalents.GetConfigIDsBySpecID then
        return out
    end

    local ok, ids = pcall(C_ClassTalents.GetConfigIDsBySpecID, specID)
    if not ok or type(ids) ~= "table" then return out end

    for _, configID in ipairs(ids) do
        local info = C_Traits and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
        if info and info.name then
            out[#out + 1] = { configID = configID, name = info.name }
        end
    end
    return out
end

function Data.GetActiveLoadoutID(specID)
    if not specID or not C_ClassTalents or not C_ClassTalents.GetLastSelectedSavedConfigID then
        return nil
    end
    local ok, configID = pcall(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
    return ok and configID or nil
end

---Conjuntos de itens, com ícone — o mesmo que aparece na ficha do personagem.
function Data.GetGearSets()
    local out = {}
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs then return out end

    local ok, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
    if not ok or type(ids) ~= "table" then return out end

    for _, setID in ipairs(ids) do
        local name, icon, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if name then
            out[#out + 1] = { setID = setID, name = name, icon = icon, isEquipped = isEquipped }
        end
    end
    return out
end

---Conjuntos de aparência (transmog) que o jogador tem salvos.
---
---`C_TransmogOutfitInfo` é namespace NOVO do Midnight — não é o transmog antigo, preso ao NPC.
---É o sistema de "outfits" que o jogo passou a trocar sozinho por situação (o enum
---`TransmogSituationTrigger` tem `Location`, `Movement`, `Weather`, `Specialization` e até
---`EquipmentSet`).
---
---GUARDAMOS O `outfitID`, MAS A TROCA PEDE O ÍNDICE. São coisas diferentes, e o comentário da
---própria Blizzard diz por quê: *"playerFacingOutfitIndex is slightly different from outfitID
---(outfitIDs may have gaps)"*. Guardar o índice apodreceria: apagar um conjunto de aparência
---desloca todos os seguintes, e o preset passaria a vestir outra roupa.
function Data.GetOutfits()
    local out = {}
    if not C_TransmogOutfitInfo or not C_TransmogOutfitInfo.GetOutfitsInfo then return out end

    local ok, list = pcall(C_TransmogOutfitInfo.GetOutfitsInfo)
    if not ok or type(list) ~= "table" then return out end

    for _, info in ipairs(list) do
        if info.outfitID and not info.isDisabled then
            out[#out + 1] = {
                outfitID = info.outfitID,
                index = info.playerFacingOutfitIndex,
                name = info.name or "?",
                icon = info.icon,
            }
        end
    end
    return out
end

function Data.OutfitName(outfitID)
    if not outfitID then return nil end
    for _, o in ipairs(Data.GetOutfits()) do
        if o.outfitID == outfitID then return o.name, o.icon end
    end
    return nil
end

function Data.GetActiveOutfitID()
    if not C_TransmogOutfitInfo or not C_TransmogOutfitInfo.GetActiveOutfitID then return nil end
    local ok, id = pcall(C_TransmogOutfitInfo.GetActiveOutfitID)
    return ok and id or nil
end

function Data.GetEquippedSetID()
    for _, set in ipairs(Data.GetGearSets()) do
        if set.isEquipped then return set.setID end
    end
    return nil
end

---Nome de um loadout/conjunto por id, para a lista mostrar texto em vez de número.
function Data.LoadoutName(specID, configID)
    if not configID then return nil end
    for _, l in ipairs(Data.GetLoadouts(specID)) do
        if l.configID == configID then return l.name end
    end
    return nil
end

function Data.GearSetName(setID)
    if not setID then return nil end
    for _, s in ipairs(Data.GetGearSets()) do
        if s.setID == setID then return s.name, s.icon end
    end
    return nil
end

---Este conjunto já está inteiramente aplicado? Serve para a lista marcar o ativo e para não
---anunciar troca quando não há nada a trocar.
function Data.IsLoaded(preset)
    if not preset then return false end

    if preset.spec and preset.spec ~= Data.GetCurrentSpecIndex() then return false end

    local spec = Data.GetSpecByIndex(preset.spec or Data.GetCurrentSpecIndex())
    if preset.talent and spec and Data.GetActiveLoadoutID(spec.id) ~= preset.talent then
        return false
    end
    if preset.gear and Data.GetEquippedSetID() ~= preset.gear then return false end
    if preset.transmog and Data.GetActiveOutfitID() ~= preset.transmog then return false end

    return true
end

--------------------------------------------------------------------------------
-- Aplicação: a corrente de passos
--------------------------------------------------------------------------------
local running          -- { preset, steps, at, timer, report }
local listener

local function Report(text, isError)
    if running and running.report then running.report(text, isError) end
end

local function Finish(ok, message)
    if running and running.timer then running.timer:Cancel() end

    -- Guarda o `report` ANTES de zerar `running`: `Report()` lê de `running`, e limpar
    -- primeiro fazia a mensagem final — inclusive a de FALHA — nunca chegar à janela. O erro
    -- só aparecia no chat, que é justamente onde a pessoa não está olhando depois de clicar
    -- em "Carregar". Pego pelo harness, não in-game.
    local preset = running and running.preset
    local report = running and running.report
    local failures = running and running.failures
    running = nil

    -- Correu tudo, mas algum passo não deu: o resultado não é sucesso nem fracasso, é
    -- **parcial**, e a mensagem tem que dizer as duas coisas — o que foi aplicado e o que não.
    if ok and failures and #failures > 0 then
        ok = false
        message = format(L["%s loaded, except: %s"],
            preset and preset.name or "?", table.concat(failures, "; "))
    end

    local text = ok and format(L["%s is ready."], preset and preset.name or "?")
        or (message or L["timed out waiting for the game to confirm."])

    if report then report(text, not ok) end
    if not ok then ns.Print(text) end

    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

local RunNext   -- declarado antes para os passos poderem chamá-lo

---Arma o prazo do passo corrente. Sem isso, um passo que nunca confirma deixa o addon
---travado em "carregando" para sempre, sem dizer nada.
---Nome do passo em curso, para o relatório. O prazo dizia só "o jogo não confirmou a tempo", sem
---dizer de quê — e numa corrente de quatro passos isso obriga o jogador a adivinhar (ou a me
---contar, que foi o que aconteceu: "deu a mensagem que o jogo não confirmou o tempo" e eu tive de
---perguntar qual passo era).
local STEP_LABEL = {
    spec     = "Specialization",
    talent   = "Talents",
    gear     = "Gear",
    transmog = "Appearance",
}

local function StepName(key)
    local label = STEP_LABEL[key]
    return label and L[label] or (key or "?")
end

local function Arm()
    if running.timer then running.timer:Cancel() end
    -- O PRAZO TAMBEM SO ANOTA. Pela mesma razao do `fail` em `RunNext`: se os talentos nao
    -- confirmarem a tempo, os itens e a aparencia ainda podem ser aplicados, e derrubar tudo
    -- deixaria o jogador sem nada em vez de sem uma parte.
    -- O NOME DO PASSO É CAPTURADO AGORA, e não lido dentro do prazo: quando ele vencer, `running.at`
    -- já pode ter andado. Ler lá dentro nomearia o passo errado — que é pior que não nomear.
    local qual = StepName(running.steps[running.at])

    running.timer = C_Timer.NewTimer(STEP_TIMEOUT, function()
        if not running then return end
        running.failures = running.failures or {}
        running.failures[#running.failures + 1] =
            format(L["%s: the game did not confirm in time."], qual)
        RunNext()
    end)
end

--------------------------------------------------------------------------------
local Steps = {}

function Steps.spec(preset)
    local wanted = preset.spec
    if not wanted or wanted == Data.GetCurrentSpecIndex() then return "skip" end

    Report(L["Switching specialization..."], false)

    -- `C_SpecializationInfo.SetSpecialization` é o caminho atual; a global antiga fica como
    -- reserva. Os dois recebem o ÍNDICE da spec, não o id.
    local ok
    if C_SpecializationInfo and C_SpecializationInfo.SetSpecialization then
        ok = pcall(C_SpecializationInfo.SetSpecialization, wanted)
    elseif SetSpecialization then
        ok = pcall(SetSpecialization, wanted)
    end
    if not ok then return "fail", L["the specialization change failed."] end

    Arm()
    return "wait"
end

---A mensagem do JOGO, quando ele der uma.
---
---O texto vem localizado e diz a causa concreta ("você não pode fazer isso em combate", "não é
---possível numa área de dificuldade Mítica"…). A nossa frase genérica só entra quando o jogo
---não explicou — e aí ela é honesta, porque de fato não se sabe.
local function TalentError(changeError)
    if type(changeError) == "string" and changeError ~= "" then
        return format(L["talents: %s"], changeError)
    end
    return L["the talent loadout could not be loaded."]
end

function Steps.talent(preset)
    if not preset.talent then return "skip" end

    local spec = Data.GetSpecByIndex(Data.GetCurrentSpecIndex())
    if spec and Data.GetActiveLoadoutID(spec.id) == preset.talent then return "skip" end

    Report(L["Loading talents..."], false)

    if not C_ClassTalents or not C_ClassTalents.LoadConfig then
        return "fail", L["the talent loadout could not be loaded."]
    end

    -- PERGUNTA ANTES, e usa a resposta do jogo. `CanEditTalents` devolve `canEdit, changeError`
    -- e a documentação é explícita: *"Returns true if the player could switch talents if they
    -- staged a proper loadout"*. É o motivo real da falha intermitente — combate, área errada,
    -- restrição de instância — e o jogo já o entrega em português.
    if C_ClassTalents.CanEditTalents then
        local fine, canEdit, why = pcall(C_ClassTalents.CanEditTalents)
        if fine and canEdit == false then
            return "fail", TalentError(why)
        end
    end

    -- TRÊS retornos, não um: `result, changeError, newLearnedNodeIDs`. Capturar só o primeiro
    -- jogava fora justamente a string que diz POR QUE não deu — e o addon respondia com um
    -- "não deu para carregar os talentos" que não ensina nada.
    local ok, result, changeError = pcall(C_ClassTalents.LoadConfig, preset.talent, true)
    if not ok then return "fail", L["the talent loadout could not be loaded."] end

    -- Faz o jogo lembrar qual loadout está valendo — sem isto a própria janela de talentos
    -- continua marcando o anterior como selecionado.
    if spec and C_ClassTalents.UpdateLastSelectedSavedConfigID then
        pcall(C_ClassTalents.UpdateLastSelectedSavedConfigID, spec.id, preset.talent)
    end

    local E = Enum.LoadConfigResult
    if result == (E and E.NoChangesNecessary) or result == (E and E.Ready) then
        return "skip"       -- já aplicado; segue direto para o próximo passo
    end
    if result == (E and E.Error) then
        return "fail", TalentError(changeError)
    end

    Arm()
    return "wait"           -- LoadInProgress: confirma em TRAIT_CONFIG_UPDATED
end

function Steps.gear(preset)
    if not preset.gear then return "skip" end
    if Data.GetEquippedSetID() == preset.gear then return "skip" end

    -- As três guardas que o próprio jogo usa antes de equipar um conjunto. A ordem importa
    -- só para a mensagem: cada falha tem a sua, porque `UseEquipmentSet` não devolve motivo.
    if C_EquipmentSet.EquipmentSetContainsLockedItems
        and C_EquipmentSet.EquipmentSetContainsLockedItems(preset.gear) then
        return "fail", L["some items of this set are locked (in use, or in the mail)."]
    end
    if UnitCastingInfo("player") then
        return "fail", L["you are casting something — try again in a second."]
    end

    Report(L["Equipping gear..."], false)

    local ok = pcall(C_EquipmentSet.UseEquipmentSet, preset.gear)
    if not ok then return "fail", L["the gear set could not be equipped."] end

    Arm()
    return "wait"           -- confirma em EQUIPMENT_SWAP_FINISHED
end

---A aparência entra POR ÚLTIMO, depois dos itens.
---
---Motivo concreto: equipar um conjunto de itens mexe nas peças, e a aparência se aplica sobre
---o que está vestido. Trocar a roupa antes das peças seria escrever por cima do que o passo
---seguinte vai mudar.
---
---CONFIRMA POR EVENTO, como todos os outros passos.
---
---Isto aqui dizia, por escrito, que "este passo é o único que NÃO tem evento de confirmação
---amarrado". **Era falso**, e a afirmação custou caro: em cima dela o passo passou a conferir com
---um `C_Timer.After(0.1)` — número escolhido no olho, sem nada que garantisse que a troca vale
---dentro dele. Se a troca demora mais que isso, o passo acusa falha numa troca que funcionou.
---
---O evento existe e é `TRANSMOG_DISPLAYED_OUTFIT_CHANGED`
---(`TransmogOutfitInfoDocumentation.lua:818-821`, `SynchronousEvent = true`), e é ele que a
---própria janela de transmog escuta para se redesenhar (`Blizzard_Transmog.lua:85,184`). O que eu
---tinha olhado era o `TRANSMOG_OUTFITS_CHANGED` — esse sim avisa que a LISTA mudou (criar,
---apagar), e não qual está ativa. Dois eventos de nome parecido, e eu conferi só um.
function Steps.transmog(preset)
    if not preset.transmog then return "skip" end
    if Data.GetActiveOutfitID() == preset.transmog then return "skip" end

    if not C_TransmogOutfitInfo or not C_TransmogOutfitInfo.ChangeToOutfit then
        return "fail", L["this client cannot switch transmog outfits."]
    end

    -- O índice é resolvido AGORA, não no momento em que o conjunto foi salvo: ele desloca
    -- quando uma aparência é apagada.
    local index
    for _, outfit in ipairs(Data.GetOutfits()) do
        if outfit.outfitID == preset.transmog then index = outfit.index end
    end
    if not index then
        return "fail", L["that transmog outfit no longer exists."]
    end

    -- PERGUNTA ANTES DE CHAMAR. A chamada em si nunca reclama; se algo esta impedindo, ela
    -- devolve sucesso e nao faz nada. Sem esta consulta o passo so podia dizer "nao deu",
    -- e o usuario relatou justamente a ausencia de motivo.
    local impedindo = Data.TransmogBlockedBy(preset.transmog)
    if impedindo then return "fail", impedindo end

    Report(L["Changing appearance..."], false)

    -- `Arm()` ANTES DA CHAMADA, e a ordem é obrigatória.
    --
    -- `TRANSMOG_DISPLAYED_OUTFIT_CHANGED` é `SynchronousEvent = true`
    -- (`TransmogOutfitInfoDocumentation.lua:818-821`): ele dispara DENTRO da chamada, não no
    -- quadro seguinte. Como a aparência é o último passo, o ouvinte chama `RunNext`, que chega ao
    -- fim da corrente e zera `running` ali mesmo — e qualquer linha depois disso indexaria
    -- `running` já nulo. Armando antes, o prazo existe quando a chamada volta e não há nada a
    -- fazer depois dela.
    --
    -- Não é teórico: foi o que o harness pegou assim que o stub passou a disparar o evento como o
    -- jogo dispara. A versão anterior desta função tinha a armadilha na direção contrária.
    Arm()

    -- A PORTA QUE A UI DO JOGO USA, e não a de macro.
    --
    -- Havia duas, e o addon estava na errada. `ChangeToOutfit(índice, allowRemove)` é o que o
    -- **comando de barra** e a ação segura chamam (`SlashCommands.lua:1726`,
    -- `SecureTemplates.lua:663`). O **botão de conjunto** da janela de transmog chama outra:
    --
    --     C_TransmogOutfitInfo.ChangeDisplayedOutfit(outfitID, trigger, toggleLock, allowRemove)
    --     -- Blizzard_Transmog/Blizzard_TransmogTemplates.lua:72
    --
    -- Trocar para ela é justificado mesmo sem o defeito: ela recebe **outfitID**, que é o que
    -- guardamos, então a tradução para índice — e toda a classe de erro que vem de traduzir —
    -- deixa de existir. E ela recebe o GATILHO explicitamente.
    --
    -- O gatilho importa mais do que parece. `TransmogSituationTrigger` tem `Specialization` (5) e
    -- `EquipmentSet` (6): o sistema de conjuntos do Midnight troca aparência SOZINHO quando a spec
    -- ou o conjunto de itens muda — que é exatamente o que esta corrente acabou de fazer nos dois
    -- passos anteriores. Dizer `Manual` é dizer ao jogo que esta troca é do jogador, e não mais
    -- uma reação em cadeia dele.
    --
    -- `allowRemoveOutfit = false` nas duas, e o motivo está escrito na própria Blizzard:
    -- *"if applying the same outfit that is already applied, it will be treated as a **clear**"*
    -- (`SlashCommands.lua:1714`). Com `true`, carregar duas vezes o mesmo conjunto TIRARIA a
    -- aparência na segunda.
    --
    -- NÃO ESTÁ CONFIRMADO que era a porta. O que está confirmado é que a anterior não fez o jogo
    -- disparar `TRANSMOG_DISPLAYED_OUTFIT_CHANGED` em 12 segundos. `/rs transmog <índice>` executa
    -- as duas e diz qual responde.
    local ok
    if C_TransmogOutfitInfo.ChangeDisplayedOutfit then
        local manual = Enum and Enum.TransmogSituationTrigger
            and Enum.TransmogSituationTrigger.Manual
        ok = pcall(C_TransmogOutfitInfo.ChangeDisplayedOutfit,
            preset.transmog, manual, false, false)
    else
        -- Cliente sem a função da UI: cai na de macro, que é a que existe desde antes.
        ok = pcall(C_TransmogOutfitInfo.ChangeToOutfit, index, false)
    end
    if not ok then return "fail", L["the transmog outfit could not be applied."] end

    -- "wait": ou o evento fecha o passo, ou o prazo do `Arm()` anota a falha e segue. Nos dois
    -- caminhos o jogador fica com tudo o que era possível aplicar.
    --
    -- E se o evento já correu lá em cima, `running` é nulo e este "wait" não faz nada: `RunNext`
    -- só olha o resultado para decidir se CONTINUA, e não há mais o que continuar.
    return "wait"
end

--------------------------------------------------------------------------------
RunNext = function()
    if not running then return end

    running.at = running.at + 1
    local name = running.steps[running.at]

    if not name then
        Finish(true)
        return
    end

    local outcome, message = Steps[name](running.preset)
    if outcome == "skip" then
        RunNext()
    elseif outcome == "fail" then
        -- UM PASSO QUE FALHA NÃO DERRUBA OS SEGUINTES.
        --
        -- Antes, `fail` chamava `Finish` na hora, e a corrente parava ali. Como a ordem é
        -- spec → talentos → itens → aparência, uma falha nos talentos (que acontece por motivo
        -- do jogo — combate, área errada) levava junto os ITENS e a APARÊNCIA, que teriam
        -- funcionado. Foi assim que "a aparência não funciona" apareceu: ela é o último passo e
        -- quase nunca chegava a rodar.
        --
        -- Agora a falha é anotada e a corrente segue. No fim, o relatório diz o que não deu —
        -- e o jogador fica com tudo que era possível aplicar, em vez de nada.
        running.failures = running.failures or {}
        running.failures[#running.failures + 1] = message
        RunNext()
    end
    -- "wait": o evento correspondente chama RunNext()
end

---Aplica um conjunto. Devolve false quando nem começou (combate, ou já está tudo aplicado).
---@param report function|nil recebe (texto, éErro) a cada passo, para a UI mostrar
function Data.Apply(preset, report)
    if not preset then return false end

    if InCombatLockdown() then
        ns.Print(L["in combat: will apply when the fight ends."])
        if report then report(L["in combat: will apply when the fight ends."], true) end
        ns.RunWhenSafe(function() Data.Apply(preset, report) end)
        return false
    end

    if running then return false end

    if Data.IsLoaded(preset) then
        if report then
            report(format(L["Nothing to change — %s is already loaded."], preset.name or "?"), false)
        end
        return false
    end

    running = { preset = preset, steps = { "spec", "talent", "gear", "transmog" }, at = 0, report = report }
    if report then report(format(L["Loading %s..."], preset.name or "?"), false) end

    Data.EnsureListener()
    RunNext()
    return true
end

function Data.IsApplying()
    return running ~= nil
end

--------------------------------------------------------------------------------
-- Confirmação: os eventos que fecham cada passo
--------------------------------------------------------------------------------
---O ouvinte só existe enquanto o addon precisa dele. Registrar `TRAIT_CONFIG_UPDATED` e
---`EQUIPMENT_SWAP_FINISHED` o tempo todo faria o addon acordar em toda troca manual do
---jogador, e não há nada a fazer nesses casos.
function Data.EnsureListener()
    if listener then return listener end

    listener = CreateFrame("Frame", ADDON .. "ApplyListener")
    listener:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    listener:RegisterEvent("SPECIALIZATION_CHANGE_CAST_FAILED")
    listener:RegisterEvent("TRAIT_CONFIG_UPDATED")
    listener:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
    listener:RegisterEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")

    listener:SetScript("OnEvent", function(_, event, arg1)
        if not running then return end
        local step = running.steps[running.at]

        if event == "SPECIALIZATION_CHANGE_CAST_FAILED" then
            Finish(false, L["the specialization change failed."])

        elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" and step == "spec" then
            RunNext()

        elseif event == "TRAIT_CONFIG_UPDATED" and step == "talent" then
            RunNext()

        elseif event == "TRANSMOG_DISPLAYED_OUTFIT_CHANGED" and step == "transmog" then
            -- O EVENTO NÃO DIZ QUAL conjunto entrou — não tem carga útil
            -- (`TransmogOutfitInfoDocumentation.lua:818-821`). Então ele é o sinal de que
            -- ALGO mudou, e quem responde "mudou para o certo?" continua sendo a leitura.
            --
            -- E se mudou para o ERRADO, isso não é falha a repetir: é o jogador tendo trocado a
            -- aparência à mão no meio da aplicação. O relatório diz o que houve e a corrente
            -- segue, como em todo passo que não deu.
            if Data.GetActiveOutfitID() ~= running.preset.transmog then
                local porque = Data.TransmogBlockedBy(running.preset.transmog)
                running.failures = running.failures or {}
                running.failures[#running.failures + 1] =
                    porque or L["the transmog outfit could not be applied."]
            end
            RunNext()

        elseif event == "EQUIPMENT_SWAP_FINISHED" and step == "gear" then
            -- 1º argumento é `result` (bool). Falso aqui é a única pista de que a troca de
            -- itens não deu certo — a função em si não devolve nada.
            if arg1 == false then
                Finish(false, L["the gear set could not be equipped."])
            else
                RunNext()
            end
        end
    end)

    return listener
end

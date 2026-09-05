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

-- Um quadro de folga antes de conferir se a aparencia trocou. Ver `Steps.transmog`: nao esta
-- verificado que a troca vale no mesmo quadro da chamada, e conferir cedo demais transformaria
-- uma troca que funciona num aviso de falha.
local TRANSMOG_CONFIRM_DELAY = 0.1

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
local function Arm()
    if running.timer then running.timer:Cancel() end
    -- O PRAZO TAMBEM SO ANOTA. Pela mesma razao do `fail` em `RunNext`: se os talentos nao
    -- confirmarem a tempo, os itens e a aparencia ainda podem ser aplicados, e derrubar tudo
    -- deixaria o jogador sem nada em vez de sem uma parte.
    running.timer = C_Timer.NewTimer(STEP_TIMEOUT, function()
        if not running then return end
        running.failures = running.failures or {}
        running.failures[#running.failures + 1] =
            L["timed out waiting for the game to confirm."]
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
---Este passo é o único que NÃO tem evento de confirmação amarrado: `TRANSMOG_OUTFITS_CHANGED`
---dispara quando a LISTA muda (criar, apagar), não quando a aparência ativa troca. Então ele
---confirma lendo `GetActiveOutfitID` logo depois — e se a leitura não bater, avisa em vez de
---dizer "pronto".
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

    Report(L["Changing appearance..."], false)

    -- `allowRemoveOutfit = false` é obrigatório aqui, e o motivo está escrito na própria
    -- Blizzard: *"if applying the same outfit that is already applied, it will be treated as a
    -- **clear** unless the index is prefixed by '!'"* (`SlashCommands.lua:1716`). Com `true`,
    -- carregar duas vezes o mesmo conjunto TIRARIA a aparência na segunda.
    local ok = pcall(C_TransmogOutfitInfo.ChangeToOutfit, index, false)
    if not ok then return "fail", L["the transmog outfit could not be applied."] end

    -- CONFERE, em vez de presumir. O comentário acima desta função já prometia isso desde a
    -- 0.3.0 e o código não fazia: devolvia "skip" logo depois da chamada. Como não há evento de
    -- confirmação para a troca de aparência (`TRANSMOG_OUTFITS_CHANGED` avisa que a LISTA mudou,
    -- não qual está ativa), ler o estado de volta é a única verificação possível.
    --
    -- **Não imediatamente**, e este cuidado é deliberado: não está verificado que a troca vale
    -- no mesmo quadro da chamada. Conferir na hora e errar transformaria uma troca que funciona
    -- num aviso de falha — pior que o defeito original. Um quadro de espera custa nada e tira o
    -- palpite da conta.
    -- `Arm()` ANTES de agendar: a confirmação chama `RunNext`, que pode terminar a corrente e
    -- zerar `running` ali mesmo. Armar depois disso indexaria `running` já nulo — e não é
    -- teórico, foi o que o harness pegou na primeira versão desta função.
    Arm()

    local token = running
    C_Timer.After(TRANSMOG_CONFIRM_DELAY, function()
        -- Outra aplicação pode ter começado nesse meio tempo; esta já não manda mais.
        if not running or running ~= token then return end

        if Data.GetActiveOutfitID() ~= preset.transmog then
            running.failures = running.failures or {}
            running.failures[#running.failures + 1] =
                L["the transmog outfit could not be applied."]
        end
        RunNext()
    end)

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

    listener:SetScript("OnEvent", function(_, event, arg1)
        if not running then return end
        local step = running.steps[running.at]

        if event == "SPECIALIZATION_CHANGE_CAST_FAILED" then
            Finish(false, L["the specialization change failed."])

        elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" and step == "spec" then
            RunNext()

        elseif event == "TRAIT_CONFIG_UPDATED" and step == "talent" then
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

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
-- CORREÇÃO DE UMA CRENÇA MINHA QUE VIROU DEFEITO. Este cabeçalho dizia, por escrito, que
-- "`UseEquipmentSet` não devolve erro" — e mais abaixo o ouvinte repetia que "a função em si não
-- devolve nada". **As duas frases eram falsas no 12.1.0**, e enquanto elas estivessem aqui a
-- próxima rodada refaria o mesmo raciocínio:
--
--   `C_EquipmentSet.UseEquipmentSet`         -> `setWasEquipped` (bool)
--                                              `EquipmentManagerDocumentation.lua:287-299`
--   `C_SpecializationInfo.SetSpecialization` -> `success` (bool)
--                                              `SpecializationInfoDocumentation.lua:368-380`
--
-- A Blizzard ramifica nos dois (`Blizzard_ClassSpecializationsFrame.lua:457-465`). Nós
-- guardávamos só o `ok` do `pcall`, que responde "estourou?" e não "o jogo aceitou?" — então uma
-- recusa imediata virava doze segundos de espera e depois "o jogo não confirmou a tempo", com a
-- corrente seguindo para o passo seguinte no estado errado.
--
-- Cada passo espera o evento de confirmação E olha o retorno. Sem os dois o addon diz "pronto"
-- sem ter feito nada, que é pior do que não ter addon.
local ADDON, ns = ...
local L = ns.L

local Data = {}
ns.Data = Data

-- PRAZO POR PASSO, e generoso. O usuário foi explícito: *"não tem problema demorar um pouco"*.
--
-- Doze segundos para tudo era um número meu, e a Blizzard não impõe prazo nenhum: o frame dela
-- segura o estado "ativando" até o evento chegar ou o cast falhar
-- (`Blizzard_ClassSpecializationsFrame.lua:174-190,209-214`). Trocar de spec tem cast e ida e
-- volta de servidor, e ainda dispara a troca automática de itens amarrada àquela spec — é o
-- passo que mais tem como engasgar, e era o que mais estourava.
--
-- A aparência é o oposto: ela já foi pedida no clique, antes da corrente começar. Se não chegou
-- em dois segundos, não vai chegar — esperar doze só atrasa a mensagem.
local STEP_TIMEOUT = {
    spec     = 45,
    talent   = 30,
    gear     = 20,
    transmog = 2,
}
local STEP_TIMEOUT_DEFAULT = 20

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

    -- RECARGA — e aqui morava o pior defeito desta corrente, escrito por mim.
    --
    -- A versao anterior lia `cd.startTime` e `cd.duration`, comparava os dois com zero e ainda
    -- somava um ao outro. Os dois sao **SECRET dentro de mitica+**:
    --
    --   * `C_Spell.GetSpellCooldown` e `SecretWhenCooldownsRestricted`
    --     (`SpellDocumentation.lua:271`), e esse predicado vale para combate, encontro, **modo
    --     desafio** e partida de PvP -- ou seja, a chave inteira, nao so a luta;
    --   * em `SpellCooldownInfo`, `isEnabled`, `isActive` e `isOnGCD` sao `NeverSecret`;
    --     **`startTime` e `duration` NAO SAO** (`SpellSharedDocumentation.lua:23-30`).
    --
    -- E a guarda de `type` nao protegia nada: `type()` num secret devolve o TIPO REAL, entao as
    -- duas passavam e a comparacao estourava. O `pcall` acima cobre a CHAMADA, nao as contas
    -- feitas com o que ela devolveu.
    --
    -- O ESTRAGO ERA O RELATO INTEIRO. Erro de Lua aqui, com `running` ja definido e nenhum prazo
    -- armado ainda, deixava a corrente presa para sempre -- e todo clique seguinte voltava MUDO
    -- em `Data.Apply`. "As vezes nao troca, gera erro", numa linha so.
    --
    -- `isActive` responde a mesma pergunta sem ler campo secreto nenhum: *"False if cooldown is
    -- not active (ex: not enabled, or startTime or duration are 0)"* -- as tres condicoes do
    -- `CooldownFrame_Set` de uma vez. O preco e nao dizer quantos segundos faltam, e ele vale:
    -- contar segundos exige os dois campos proibidos.
    local getCD = C_Spell and C_Spell.GetSpellCooldown
    local ok, cd = false, nil
    if getCD then ok, cd = pcall(getCD, TransmogSpellID()) end
    if ok and type(cd) == "table" and cd.isActive == true then
        return L["changing appearance is on cooldown."]
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

---O `playerFacingOutfitIndex` de um conjunto de aparência, resolvido AGORA.
---
---Guardamos o `outfitID` e a troca pede o índice, e os dois não são a mesma coisa — o comentário
---da própria Blizzard diz por quê: *"playerFacingOutfitIndex is slightly different from outfitID
---(outfitIDs may have gaps)"*. O índice desloca quando uma aparência é apagada, então ele se
---resolve na hora de usar e nunca se guarda.
function Data.OutfitIndex(outfitID)
    if not outfitID then return nil end
    for _, outfit in ipairs(Data.GetOutfits()) do
        if outfit.outfitID == outfitID then return outfit.index end
    end
    return nil
end

---A magia que o jogo lança para ativar uma especialização.
---
---NÃO EXISTE CONSTANTE PARA ELA. Procurei: o transmog tem
---`EQUIP_TRANSMOG_OUTFIT_MANUAL_SPELL_ID` na documentação gerada, a troca de spec não tem
---equivalente. O que existe é o predicado `IsSpecializationActivateSpell(spellID)`, que a própria
---janela de talentos usa para reconhecer o cast dela
---(`Blizzard_ClassSpecializationsFrame.lua:187`).
---
---Então o addon **aprende o id com o jogo**: quando um cast do jogador termina, ele pergunta ao
---predicado se aquele era o de ativar spec, e guarda. Dali em diante dá para ler a recarga.
---
---Guardado em SavedVariables porque o id não muda e reaprendê-lo a cada sessão significaria a
---primeira troca de cada sessão continuar às cegas.
local function SpecSpellID()
    return RocketSwapLogDB and RocketSwapLogDB.specSpellID
end

---Chamado quando um cast do jogador termina. Guarda o id se for o de ativar especialização.
function Data.NoteSpellCast(spellID)
    -- `type` ANTES DE TUDO. `UNIT_SPELLCAST_SUCCEEDED` é `SecretWhenUnitSpellCastRestricted`
    -- (`UnitDocumentation.lua:4702`), então sob restrição o `spellID` vem opaco — e guardar valor
    -- opaco em SavedVariables é caminho certo para erro.
    --
    -- A guarda é **defensiva**: sabotá-la não reprova teste nenhum, porque o predicado do jogo
    -- devolve falso para um valor que não é o id. Fica porque o custo de errar é um arquivo de
    -- configuração corrompido, e o de acertar é uma linha.
    if type(spellID) ~= "number" then return end
    if not IsSpecializationActivateSpell then return end
    if SpecSpellID() then return end                       -- já sabemos

    local ok, ehDeSpec = pcall(IsSpecializationActivateSpell, spellID)
    if ok and ehDeSpec then
        RocketSwapLogDB = RocketSwapLogDB or {}
        RocketSwapLogDB.specSpellID = spellID
        if ns.Log then
            ns.Log.Add("aprendeu", { magiaDeSpec = spellID })
        end
    end
end

---Dá para trocar de especialização agora?
---
---É a MESMA pergunta que a janela de talentos do jogo faz para decidir se o botão "Ativar" fica
---clicável: `specContentFrame.ActivateButton:SetEnabled(canSpecsBeActivated)`, com
---`canSpecsBeActivated = C_SpecializationInfo.CanPlayerUseTalentSpecUI()`
---(`Blizzard_ClassSpecializationsFrame.lua:139,149`).
---
---Usar a condição da Blizzard tem duas vantagens sobre inventar a nossa: ela cobre todos os
---motivos de uma vez (combate, veículo, troca em andamento, o que mais existir), e ela **devolve
---o motivo em texto**, já traduzido pelo cliente — `canUse, failureReason`
---(`SpecializationInfoDocumentation.lua:21-28`).
---
---Antes o addon descobria a recusa **chamando e levando não**, que é o que produzia a mensagem
---genérica depois do clique. Perguntar antes deixa a interface responder sem tentar.
---@return boolean pode, string|nil motivo
function Data.CanChangeSpec()
    if not C_SpecializationInfo or not C_SpecializationInfo.CanPlayerUseTalentSpecUI then
        return true      -- cliente sem a função: não há como perguntar, então não se impede
    end

    local ok, pode, motivo = pcall(C_SpecializationInfo.CanPlayerUseTalentSpecUI)
    if ok and pode == false then
        return false, (type(motivo) == "string" and motivo ~= "") and motivo or nil
    end

    -- E A RECARGA DA MAGIA, que é o caso que o usuário viveu e que a pergunta acima NÃO cobre.
    --
    -- O diário provou: às 02:28:18 a troca deu certo e às 02:28:26 — oito segundos depois — o
    -- jogo devolveu `false`, com `CanPlayerUseTalentSpecUI` respondendo **sim** o tempo todo.
    -- Aquela pergunta é sobre a interface estar utilizável, não sobre a troca estar disponível.
    --
    -- `isActive` e não `startTime`/`duration`: os dois últimos viram SECRET sob restrição, e
    -- comparar secret já travou este addon uma vez.
    local spellID = SpecSpellID()
    local getCD = spellID and C_Spell and C_Spell.GetSpellCooldown
    if getCD then
        local okCD, cd = pcall(getCD, spellID)
        if okCD and type(cd) == "table" and cd.isActive == true then
            return false, nil       -- sem motivo do jogo: a nossa frase explica a espera
        end
    end

    return true
end

function Data.GetActiveOutfitID()
    if not C_TransmogOutfitInfo or not C_TransmogOutfitInfo.GetActiveOutfitID then return nil end
    local ok, id = pcall(C_TransmogOutfitInfo.GetActiveOutfitID)
    return ok and id or nil
end

---O primeiro conjunto marcado como vestido. Serve para o ✓ da lista, e **só** para isso.
---
---`isEquipped` é por conjunto e independente: a janela do jogo desenha um ✓ em CADA conjunto cujo
---`isEquipped` é verdadeiro (`PaperDollFrame.lua:2396,2414-2418`). Dois conjuntos que compartilham
---as peças ficam os dois marcados, e "o primeiro" é uma resposta arbitrária.
function Data.GetEquippedSetID()
    for _, set in ipairs(Data.GetGearSets()) do
        if set.isEquipped then return set.setID end
    end
    return nil
end

---**Este** conjunto está vestido?
---
---É a pergunta certa para confirmar o passo de itens, e ela é diferente da de cima: perguntar
---"qual está vestido" e comparar dá a resposta errada quando dois conjuntos compartilham peças —
---o alvo estaria vestido e o addon acharia que não, porque o outro apareceu primeiro na lista.
function Data.IsGearSetEquipped(setID)
    if setID == nil then return false end
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetInfo then return false end

    -- `isEquipped` é o 4º retorno (`EquipmentManagerDocumentation.lua:128-149`).
    local ok, _, _, _, isEquipped = pcall(C_EquipmentSet.GetEquipmentSetInfo, setID)
    return ok and isEquipped == true
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

    if ns.Log then ns.Log.Finish(ok, text, failures) end

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
    local passo = running.steps[running.at]
    local qual = StepName(passo)
    local prazo = STEP_TIMEOUT[passo] or STEP_TIMEOUT_DEFAULT

    running.timer = C_Timer.NewTimer(prazo, function()
        if not running then return end
        running.failures = running.failures or {}
        running.failures[#running.failures + 1] =
            format(L["%s: the game did not confirm in time."], qual)
        RunNext()
    end)
end

--------------------------------------------------------------------------------
-- Declarada aqui e definida abaixo: `Steps.talent` a chama, e `local` declarada DEPOIS de quem a
-- usa resolve como global nil lá dentro. É a armadilha que este projeto já pagou três vezes.
local ConfirmTalent

local Steps = {}

function Steps.spec(preset)
    local wanted = preset.spec
    if not wanted or wanted == Data.GetCurrentSpecIndex() then return "skip" end

    -- PERGUNTA ANTES DE CHAMAR, com a condição da própria janela de talentos do jogo. O motivo
    -- vem dele e já vem traduzido; a nossa frase só entra quando ele não manda nenhum.
    local pode, motivo = Data.CanChangeSpec()
    if ns.Log then
        ns.Log.Call("spec", "CanChangeSpec", pode, motivo, SpecSpellID() or "magia desconhecida")
    end
    if not pode then
        return "abort", motivo
            or L["the game refused to change specialization now; wait a few seconds."]
    end

    Report(L["Switching specialization..."], false)

    -- `C_SpecializationInfo.SetSpecialization` é o caminho atual; a global antiga fica como
    -- reserva. Os dois recebem o ÍNDICE da spec, não o id.
    -- O RETORNO IMPORTA. `SetSpecialization` devolve `success`
    -- (`SpecializationInfoDocumentation.lua:368-380`), e a propria Blizzard ramifica nele
    -- (`Blizzard_ClassSpecializationsFrame.lua:457-465`). Guardar so o `ok` do `pcall` capturava
    -- apenas "estourou?", entao uma recusa imediata do jogo virava doze segundos de
    -- "Carregando..." seguidos de "o jogo nao confirmou a tempo" -- e a corrente seguia para os
    -- talentos com a spec ERRADA.
    local ok, aceito
    if C_SpecializationInfo and C_SpecializationInfo.SetSpecialization then
        ok, aceito = pcall(C_SpecializationInfo.SetSpecialization, wanted)
        if ns.Log then
            ns.Log.Call("spec", "SetSpecialization(" .. tostring(wanted) .. ")", ok, aceito)
        end
    elseif SetSpecialization then
        ok, aceito = pcall(SetSpecialization, wanted)
        if ns.Log then ns.Log.Call("spec", "SetSpecialization global", ok, aceito) end
    elseif ns.Log then
        ns.Log.Call("spec", "nenhuma funcao de troca de spec existe")
    end
    -- `aceito == false` é RECUSA DO JOGO, e o diário mostrou que ela é comum: em quatro das nove
    -- trocas gravadas o jogo devolveu `false`, sempre quando a troca vinha poucos segundos depois
    -- de outra. Trocar de especialização tem custo no jogo, e insistir não adianta — esperar sim.
    if not ok or aceito == false then
        return "abort", L["the game refused to change specialization now; wait a few seconds."]
    end

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

    -- A SPEC TEM QUE SER A DO CONJUNTO ANTES DE MEXER EM TALENTO, e este era o defeito que fazia
    -- a troca "fazer coisa errada".
    --
    -- Um loadout pertence a UMA especialização. Este passo resolvia pela spec ATUAL, então quando
    -- o passo anterior falhava, estourava o prazo, ou simplesmente ainda não tinha virado, ele
    -- pegava a spec VELHA e mandava `LoadConfig` com um id que é de OUTRA — o jogo reclama, e com
    -- razão.
    --
    -- E o pior vinha logo depois: `UpdateLastSelectedSavedConfigID(spec.id, preset.talent)`
    -- gravava o loadout da spec alvo como "o último selecionado" da spec velha. Isso **fica
    -- gravado no jogo**, então o estrago sobrevive ao `/reload` e reaparece na próxima vez que o
    -- jogador voltar àquela spec pela janela de talentos.
    --
    -- Recusar aqui é o que "sequencial" quer dizer: sem a spec certa, o passo de talentos não tem
    -- o que fazer, e fingir que tem é como se corrompe estado alheio.
    local atual = Data.GetCurrentSpecIndex()
    if preset.spec and atual ~= preset.spec then
        return "fail", L["the specialization did not change, so the talents were left alone."]
    end

    local spec = Data.GetSpecByIndex(atual)
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
    if ns.Log then
        ns.Log.Call("talent", "LoadConfig(" .. tostring(preset.talent) .. ")",
            ok, result, changeError)
    end
    if not ok then return "fail", L["the talent loadout could not be loaded."] end

    -- A ESCRITA DE "QUAL LOADOUT ESTÁ VALENDO" SAIU DAQUI, e foram duas razões:
    --
    --   1. escrever ANTES de o jogo confirmar é como o estado alheio foi corrompido (o loadout
    --      da spec alvo gravado como o da spec velha) — é o defeito da 0.13.1 pela raiz;
    --   2. e ela envenenava a própria confirmação: eu passei a confirmar o passo lendo
    --      `GetLastSelectedSavedConfigID`, que é exatamente o que esta linha escreve. O addon
    --      escrevia a resposta e depois a lia como prova. Circular.
    --
    -- Agora ela roda em `ConfirmTalent`, quando o jogo confirma.

    -- `Ready` NAO E "ja aplicado", e tratar como tal era mentira confortavel. `NoChangesNecessary`
    -- diz que nao ha o que fazer; `Ready` diz que a configuracao foi PREPARADA e espera commit.
    -- Somar os dois num `skip` fazia o addon anunciar "pronto" com os talentos antigos.
    local E = Enum.LoadConfigResult
    if result == (E and E.NoChangesNecessary) then
        -- REGISTRA MESMO SEM MUDANÇA, e o diário real é que mostrou isto: `LoadConfig` devolveu
        -- `NoChangesNecessary` em **seis das nove** trocas gravadas. Faz sentido — os nós da
        -- árvore já estavam iguais.
        --
        -- Mas a 0.13.2 só registrava o loadout na confirmação por evento, e este caminho não
        -- espera evento nenhum. Resultado: o jogo nunca ficava sabendo qual loadout passou a
        -- valer, a janela de talentos continuava marcando o anterior, e `IsLoaded` nunca dava
        -- verdadeiro — então o ✓ não aparecia e o jogador clicava de novo. É o "não chega a
        -- trocar tudo certo", e a causa era minha, de ontem.
        ConfirmTalent()
        return "skip"
    end
    if result == (E and E.Ready) then
        return "fail", L["the talents were staged but not applied; open the talent window and apply."]
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
---CONFERE, mas NÃO troca: trocar de conjunto de aparência é privilégio de código seguro.
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

    -- ATÉ AQUI A TROCA JÁ DEVERIA TER ACONTECIDO, no próprio clique. Se não aconteceu, não há o
    -- que este passo faça: as duas funções que trocam de conjunto são PROTEGIDAS.
    --
    -- Chegar a isso custou três rodadas de teste in-game, e a resposta não estava em nada que eu
    -- pudesse deduzir do código — estava no parque de addons e na web:
    --
    --   * dos 117 addons instalados, NENHUM chama `ChangeToOutfit` ou `ChangeDisplayedOutfit`.
    --     O único que troca aparência, o `EnhanceQoLQuickActions`, monta um botão seguro
    --     (`Runtime.lua:4544,4593-4595`: `type = "outfit"`, `outfit-index`, `action = "change"`);
    --   * o autor do Plumber, no repositório dele: *"The API to activate outfit
    --     C_TransmogOutfitInfo.ChangeDisplayedOutfit is protected"*;
    --   * e o patch 12.0.5 adicionou **uma ação segura `"outfit"`** justamente para isso —
    --     *"Added a new secure action (`"outfit"`) for changing/clearing transmog outfits"* — que
    --     é a forma como a Blizzard respondeu ao pedido de os addons poderem trocar.
    --
    -- Ou seja: o caminho não existe por API e não vai existir. Existe por **clique do jogador num
    -- botão seguro**, e é isso que o botão "Carregar" passou a ser (`UI.lua`, `BuildRow`).
    --
    -- POR QUE O PASSO CONTINUA AQUI, se não age: porque ele é a única coisa que sabe dizer que a
    -- aparência ficou para trás. Sem ele o conjunto se daria por aplicado com a roupa errada.
    -- Antes ele CHAMAVA e mentia sobre poder; agora ele CONFERE e diz a verdade.
    local index = Data.OutfitIndex(preset.transmog)
    if not index then
        return "fail", L["that transmog outfit no longer exists."]
    end

    -- E se alguma das portas conhecidas estiver fechada, o motivo dela é melhor que o genérico:
    -- o clique seguro passa pelas mesmas (a recarga da magia 1247613, o evento de estilo, o
    -- conjunto travado), então elas explicam também o clique que não pegou.
    local impedindo = Data.TransmogBlockedBy(preset.transmog)
    if impedindo then return "fail", impedindo end

    -- SE VEIO DO CLIQUE, A TROCA JÁ FOI PEDIDA — e pedir não é ter chegado.
    --
    -- A ação segura roda no clique e o servidor responde depois; este passo pode rodar antes da
    -- resposta, principalmente quando os três passos anteriores não têm nada a fazer e a corrente
    -- chega aqui no mesmo quadro. Conferir na hora e falhar transformaria uma troca que funciona
    -- num aviso de falha — que é pior que o defeito original, e foi o que a primeira versão desta
    -- verificação fazia.
    --
    -- Então espera o evento, com o prazo do `Arm()` por trás, como todos os outros passos.
    if running and running.byClick then
        Arm()
        return "wait"
    end

    -- E SE NÃO VEIO DO CLIQUE não há o que esperar: ninguém pediu nada. É o caso do
    -- `/rs load <nome>` e do minimapa, e a frase precisa dizer isso em vez de deixar o jogador
    -- esperando doze segundos por uma confirmação que não vem.
    return "fail", L["the appearance only changes by clicking Load (Blizzard protects the API)."]
end

---Registra no jogo qual loadout passou a valer.
---
---Só depois de o jogo confirmar. Sem esta chamada a janela de talentos continua marcando o
---anterior como selecionado; feita cedo demais, ela grava a associação errada e o estrago fica
---salvo no jogo, sobrevivendo ao `/reload`.
ConfirmTalent = function()
    if not running or not running.preset.talent then return end
    if not C_ClassTalents or not C_ClassTalents.UpdateLastSelectedSavedConfigID then return end

    local spec = Data.GetSpecByIndex(Data.GetCurrentSpecIndex())
    if not spec then return end

    -- SÓ SE A SPEC FOR A DO CONJUNTO — e esta guarda é **defensiva**, não load-bearing: o passo de
    -- talentos já recusa antes de chegar aqui, e sabotá-la não reprova nenhum teste. Fica porque
    -- esta função roda a partir de um EVENTO, e evento chega quando quer: entre o passo e a
    -- confirmação a spec pode ter mudado por fora. E o que ela protege é estado que sobrevive ao
    -- `/reload`, então o custo de errar é maior que o de uma linha a mais.
    if running.preset.spec and Data.GetCurrentSpecIndex() ~= running.preset.spec then return end

    pcall(C_ClassTalents.UpdateLastSelectedSavedConfigID, spec.id, running.preset.talent)
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

    -- `pcall` NO PASSO, e a razão é o pior defeito que esta corrente já teve: um erro de Lua
    -- dentro de um passo sobe pelo `RunNext`, e **nada zera `running`** — só o `Finish`. A partir
    -- daí todo clique em Carregar voltava MUDO, porque `Data.Apply` recusa quando há corrente em
    -- curso. Erro vermelho uma vez, e o botão morto até `/reload`.
    --
    -- Com o `pcall`, o erro vira uma falha anotada como qualquer outra: a corrente segue, o
    -- diário registra a mensagem de Lua, e o addon continua vivo.
    local okStep, outcome, message = pcall(Steps[name], running.preset)
    if not okStep then
        if ns.Log then ns.Log.Step(name, "erro de lua", tostring(outcome)) end
        message = L["an internal error interrupted this step."]
        outcome = "fail"
    elseif ns.Log then
        ns.Log.Step(name, outcome or "wait", message)
    end

    if outcome == "skip" then
        RunNext()

    -- "abort" É DIFERENTE DE "fail", e a diferença veio do diário: quando a troca de spec é
    -- recusada, **tudo depois dela cai junto** — os talentos são de outra spec, o conjunto de
    -- itens some junto com a spec, e a aparência já está em recarga da troca anterior. O relatório
    -- saía com QUATRO falhas em fila, o que o usuário leu como "fica bugado e dando erro".
    --
    -- Uma causa, uma mensagem. Só o passo de spec usa isto, e só quando o conjunto pede uma spec:
    -- sem ela, nada do resto faz sentido.
    elseif outcome == "abort" then
        Finish(false, message)

    elseif outcome == "fail" then
        -- `running` pode ter sumido DENTRO do passo: os eventos de confirmação são despachados
        -- pelo jogo e um deles pode ter fechado a corrente inteira antes de voltarmos aqui.
        if not running then return end
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
---@param byClick boolean|nil a chamada veio do clique no botão seguro, que JÁ pediu a aparência
function Data.Apply(preset, report, byClick)
    if not preset then return false end

    if InCombatLockdown() then
        ns.Print(L["in combat: will apply when the fight ends."])
        if report then report(L["in combat: will apply when the fight ends."], true) end
        ns.RunWhenSafe(function() Data.Apply(preset, report) end)
        return false
    end

    -- RECUSAR EM SILÊNCIO É O QUE FAZIA O BOTÃO PARECER QUEBRADO. Se ainda há corrente em curso,
    -- dizer isso — e registrar, porque o caso interessante é justamente a corrente que ficou
    -- presa e nunca terminou.
    if running then
        -- DIZ DE QUE PASSO ESTA ESPERANDO. O diário do usuário trouxe oito segundos de "recusado"
        -- em fila, e a mensagem não dizia nada — daí *"teve mensagem de ainda tá pendente, mas
        -- não ficou carregando nada"*. Nomear o passo transforma o silêncio em informação: se
        -- ficar parado no mesmo por muito tempo, o próprio jogador vê que travou.
        local passo = StepName(running.steps[running.at])
        if ns.Log then
            ns.Log.Add("recusado", { motivo = "ja ha uma troca em curso", esperando = passo })
        end
        if report then
            report(format(L["still applying %s: waiting for %s."],
                running.preset.name or "?", passo), true)
        end
        return false
    end

    if Data.IsLoaded(preset) then
        if report then
            report(format(L["Nothing to change — %s is already loaded."], preset.name or "?"), false)
        end
        return false
    end

    running = {
        preset = preset, steps = { "spec", "talent", "gear", "transmog" }, at = 0,
        report = report, byClick = byClick and true or false,
    }

    -- O RETRATO DE ANTES. É a linha que responde "a troca nem precisava acontecer" e "ela pedia
    -- algo que não existe mais" — dois casos que já apareceram e que o chat não mostrava.
    if ns.Log then ns.Log.Apply(preset, byClick) end
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

    listener:SetScript("OnEvent", function(_, event, arg1, arg2)
        -- REGISTRA ANTES DE DECIDIR, inclusive o evento que chega sem corrente em curso. É o que
        -- responde a hipótese que eu não tinha como testar: estes eventos são GLOBAIS e disparam
        -- quando o JOGADOR mexe à mão ou quando outro addon mexe. Se o log mostrar um evento
        -- fechando um passo que não era nosso, é isso.
        -- OS DOIS ARGUMENTOS. `EQUIPMENT_SWAP_FINISHED` traz `result, setID`, e sem o segundo
        -- não dá para saber se o evento era do nosso conjunto — foi exatamente a pergunta que
        -- ficou sem resposta ao ler o diário de 02:05.
        local emCurso = running and running.steps[running.at] or nil
        if ns.Log then ns.Log.Event(event, emCurso, running ~= nil, arg1, arg2) end

        if not running then return end
        local step = running.steps[running.at]

        -- TODOS OS RAMOS CONFEREM O PASSO EM CURSO, e este não conferia. Qualquer cast de troca
        -- de spec que falhasse — o clique do próprio jogador na janela de talentos, outro addon —
        -- matava a corrente de onde ela estivesse. E `Finish` virou anotação: falhar a spec não
        -- deve impedir os itens de entrar.
        if event == "SPECIALIZATION_CHANGE_CAST_FAILED" and step == "spec" then
            running.failures = running.failures or {}
            running.failures[#running.failures + 1] = L["the specialization change failed."]
            RunNext()

        elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" and step == "spec" then
            RunNext()

        elseif event == "TRAIT_CONFIG_UPDATED" and step == "talent" then
            -- CONFERE DE QUEM É O EVENTO. Ele carrega `configID`
            -- (`SharedTraitsDocumentation.lua:810-815`) e a Blizzard avisa por escrito que ele
            -- chega mais de uma vez por gravação — *"Saving a change to a loadout may lead to
            -- Updated event both for the base spec config id and then the selected loadout config
            -- id"* (`Blizzard_ClassTalentsFrame.lua:407-411`) — e filtra.
            --
            -- Fechávamos no PRIMEIRO, que é o do config base da spec, antes de o loadout entrar.
            -- Resultado: "X está pronto" com os talentos antigos. E a troca de spec, que roda
            -- logo antes, enfileira esses mesmos eventos — por isso acontecia em todo conjunto
            -- que mexe em spec e talentos, que é o caso comum.
            -- ACEITA O EVENTO. E esta linha é uma RETIRADA deliberada, com o motivo escrito:
            --
            -- Na 0.13.0 eu pus um filtro pelo `configID`, porque a Blizzard avisa que a gravação
            -- gera evento "both for the base spec config id **and then** the selected loadout
            -- config id" (`Blizzard_ClassTalentsFrame.lua:407-411`) e eu quis fechar só no certo.
            -- Mas a fonte **não diz qual dos dois fecha**, e o filtro recusou o evento que
            -- funcionava: o passo ficava esperando até o prazo — que eu tinha acabado de subir
            -- para trinta segundos. O usuário sentiu isso como *"apertei duas, três vezes pra
            -- funcionar"* e *"mensagem de ainda tá pendente, mas não ficou carregando nada"*.
            --
            -- Trocar um caminho que funciona por um palpite mais preciso é o pior negócio
            -- possível. O risco de fechar cedo é o passo seguinte começar um instante antes; o
            -- risco do filtro errado é o addon travar. Volto ao que funcionava, e o diário grava
            -- o `arg1` de cada evento — com uma troca real na mão dá para fechar a questão com
            -- dado em vez de com dedução.
            ConfirmTalent()
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
            -- O EVENTO DIZ QUE TERMINOU. É nele que se confia, e esta linha é a SEGUNDA retirada
            -- do mesmo erro meu nesta sequência.
            --
            -- A 0.13.2 trocou a confirmação por uma leitura de estado —
            -- `Data.IsGearSetEquipped(preset.gear)` — achando que perguntar ao mundo era mais
            -- honesto que confiar no evento. O diário do usuário provou o contrário, e de forma
            -- mecânica: às 02:05:35 chegou `EQUIPMENT_SWAP_FINISHED` com `result = true`, ou seja
            -- **a troca terminou com sucesso**, e a leitura de estado ainda respondia que o
            -- conjunto não estava vestido. A corrente não avançou, e a partir dali todo clique do
            -- jogador bateu em "já há uma troca em curso" — oito segundos de "recusado" seguidos
            -- no diário.
            --
            -- A LIÇÃO É A MESMA DO RAMO DE TALENTOS, duas versões atrás: o estado do jogo pode
            -- atrasar em relação ao evento, então exigir que ele já tenha virado transforma uma
            -- confirmação em armadilha. O evento é o fato; a leitura, no máximo, um detalhe.
            --
            -- O `arg2` continua servindo para RECUSAR o que é claramente de outro conjunto —
            -- trocar de spec faz o jogo equipar sozinho o conjunto amarrado àquela spec — mas
            -- recusar é tudo o que ele faz. Sem `arg2`, seguimos.
            if arg2 ~= nil and running.preset.gear ~= nil and arg2 ~= running.preset.gear then
                return      -- é de outro conjunto; o nosso ainda vem
            end

            -- `false` é ANOTAÇÃO, não fim de corrente: um `false` alheio matava a nossa e jogava
            -- fora as falhas já anotadas.
            if arg1 == false then
                running.failures = running.failures or {}
                running.failures[#running.failures + 1] = L["the gear set could not be equipped."]
            end
            RunNext()
        end
    end)

    return listener
end

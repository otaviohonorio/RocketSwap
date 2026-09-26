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
-- Os passos que o JOGO recusa em combate, e que por isso esperam a luta acabar em vez de falhar.
-- A aparência fica fora: quem a troca é o clique seguro, antes da corrente, e o passo dela aqui
-- só confere — não há o que o combate impeça.
local COMBAT_SENSITIVE = { spec = true, talent = true, gear = true }

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
            -- TERCEIRO RETORNO: "foi a recarga". Sem ele o diário escrevia `pode=false motivo=nil`
            -- igualzinho ao caso "a interface respondeu não e não disse por que" — duas causas
            -- diferentes na mesma linha, e a leitura do diário não separava.
            --
            -- E quem chama usa isso para decidir entre ESPERAR e desistir: recarga passa.
            return false, nil, "recarga da magia de spec"
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

---O conjunto que o jogador ESTÁ usando com peça trocada — o quase-vestido.
---
---⚑ ISTO EXISTE POR CAUSA DO `(nenhum)` MENTIROSO. `isEquipped` é tudo-ou-nada: trocar uma única
---peça de um conjunto de 14 derruba a flag dos 14, e o resumo do ready check passava a dizer
---"Itens: (nenhum)" para quem estava com o conjunto quase inteiro no corpo. A frase era falsa no
---momento em que mais custa — o líder acabou de pedir a conferência.
---
---A MEDIDA É `numEquipped`, o 6º retorno de `GetEquipmentSetInfo`: quantas peças DESTE conjunto
---estão no corpo agora. Ela não é uma dedução nossa, é a contabilidade do jogo — a mesma de que
---`Data.GearSetCounts` já vive.
---
---DUAS RECUSAS, e as duas são para não inventar resposta:
---
---  * **maioria simples ou nada.** Com metade ou menos das peças casando, "você está com o
---    conjunto X" deixa de ser verdade: dois conjuntos de raide dividem anel, capa e joia sem
---    ninguém ter vestido nenhum dos dois. Abaixo do corte a resposta honesta continua sendo
---    `(nenhum)`;
---  * **empate não responde.** Dois conjuntos com a mesma contagem são a mesma ambiguidade que o
---    comentário de `GetEquippedSetID` descreve, e escolher "o primeiro" aqui seria escolher no
---    sorteio qual nome o jogador lê. Empate devolve `nil`.
---
---As peças ignoradas ficam de fora da conta dos dois lados (`itens` já as inclui, e o jogo conta
---uma ignorada como não-vestida): o denominador é o total do conjunto, que é o número que o
---jogador vê na janela de equipamento.
---@return number|nil setID, number|nil vestidas, number|nil itens, string|nil nome
function Data.PartialGearSet()
    local melhorID, melhorNome, melhorVestidas, melhorItens
    local empatado = false

    for _, set in ipairs(Data.GetGearSets()) do
        if not set.isEquipped then
            local c = Data.GearSetCounts(set.setID)
            -- `type` e não só `and`: contagem ausente vira comparação com nil, que é erro de Lua.
            if c and type(c.vestidas) == "number" and type(c.itens) == "number" and c.itens > 0 then
                if c.vestidas * 2 > c.itens then
                    if melhorVestidas == nil or c.vestidas > melhorVestidas then
                        melhorID, melhorNome = set.setID, set.name
                        melhorVestidas, melhorItens = c.vestidas, c.itens
                        empatado = false
                    elseif c.vestidas == melhorVestidas then
                        empatado = true
                    end
                end
            end
        end
    end

    if empatado then return nil end
    return melhorID, melhorVestidas, melhorItens, melhorNome
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

---A CONTABILIDADE DO CONJUNTO, que é o que o jogo sabe e nós não estávamos perguntando.
---
---`GetEquipmentSetInfo` devolve NOVE valores, e os quatro últimos são contagem:
---`numItems, numEquipped, numInInventory, numLost, numIgnored`. **`numLost` é "peças que o
---jogador não tem à mão agora"** — e é a única resposta direta que existe para "por que a troca
---falhou", porque `UseEquipmentSet` não dá motivo e `EQUIPMENT_SWAP_FINISHED` só traz um booleano.
---
---⚑ ISTO EXISTE POR CAUSA DO DIÁRIO DE 09/09. Às 17:22:02 o jogo devolveu
---`EQUIPMENT_SWAP_FINISHED(false, 1)` para o conjunto "Frost PvE ST" — e às 00:00:26 do MESMO dia
---a mesma corrente, com o mesmo conjunto e a mesma ordem de eventos, tinha devolvido `true`. O
---diário registrava a recusa e nada mais: nem o retorno da chamada, nem o estado do conjunto. Não
---dava para separar "faltou peça" de "o jogo recusou por outro motivo", que é exatamente a
---pergunta que o diário existe para responder.
---@return table|nil counts `{ nome, itens, vestidas, naBolsa, perdidas, ignoradas }`
function Data.GearSetCounts(setID)
    if setID == nil then return nil end
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetInfo then return nil end

    local ok, name, _, _, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored =
        pcall(C_EquipmentSet.GetEquipmentSetInfo, setID)
    if not ok or name == nil then return nil end

    return {
        nome = name,
        vestido = isEquipped == true,
        itens = numItems,
        vestidas = numEquipped,
        naBolsa = numInInventory,
        perdidas = numLost,
        ignoradas = numIgnored,
    }
end

---A contabilidade em uma linha, para o diário. `nil` quando o jogo não respondeu.
function Data.DescribeGearSet(setID)
    local c = Data.GearSetCounts(setID)
    if not c then return nil end
    return format("itens=%s vestidas=%s naBolsa=%s perdidas=%s ignoradas=%s vestido=%s",
        tostring(c.itens), tostring(c.vestidas), tostring(c.naBolsa),
        tostring(c.perdidas), tostring(c.ignoradas), tostring(c.vestido))
end

---A falha de equipar, dita com o que o jogo informa — e só com o que ele informa.
---
---Com `numLost > 0` a causa está provada: o conjunto pede peça que o jogador não tem à mão. Sem
---isso, devolve a frase genérica: **inventar um motivo aqui seria pior que não ter nenhum**.
function Data.GearFailureReason(setID)
    local c = Data.GearSetCounts(setID)
    if c and type(c.perdidas) == "number" and c.perdidas > 0 then
        return format(L["%d item(s) of this set are not available right now."], c.perdidas)
    end
    return L["the gear set could not be equipped."]
end

---O conjunto de itens está quebrado? E dá para consertar agora?
---
---(!) DEFEITO RELATADO EM 22/09. O jogador trocou uma peça e **vendeu a anterior** sem salvar o
---conjunto. O jogo mostra o nome do conjunto em VERMELHO no gerenciador; o Rocket Swap trocava
---assim mesmo, mas o passo nunca fechava com o "V" — porque com peça perdida o `isEquipped` do
---jogo nunca fica `true`, e "vestido" é o que confirma o passo. Relato dele: *"ele troca, mas não
---fica marcado como trocado e em uso"*.
---
---O dado já estava aqui desde 09/09: `numLost` é lido e registrado no diário. Só que ele era usado
---**depois** da falha, para explicá-la. A informação certa chegando tarde demais é quase igual a
---não ter a informação.
---
---`consertavel` responde a pergunta que torna o conserto SEGURO. Salvar um conjunto grava o que
---você está vestindo por cima dele — então só é a coisa certa a fazer quando você **já está
---vestindo o conjunto inteiro menos o que sumiu**. Fora disso, salvar destruiria o conjunto
---trocando-o pela roupa do momento, que é um estrago bem pior que o defeito original.
---@return table|nil `{ nome, perdidas, consertavel }`, ou nil se não há problema
function Data.GearSetProblem(setID)
    local c = Data.GearSetCounts(setID)
    if not c then return nil end
    if type(c.perdidas) ~= "number" or c.perdidas <= 0 then return nil end

    local vestidas = type(c.vestidas) == "number" and c.vestidas or 0
    local itens = type(c.itens) == "number" and c.itens or 0

    -- QUAL PEÇA SUMIU, e não só quantas. "Falta 1 item" manda o jogador procurar; "falta o
    -- Elmo" ele já sabe o que fazer. `GetItemLocations` marca com **-1** o slot cuja peça não
    -- está disponível.
    --
    -- ⚠️ A própria documentação avisa que `-1` **não distingue** "sumiu" de "este slot não dá
    -- para equipar". Por isso os nomes só são colhidos quando `numLost > 0` (aí sabemos que há
    -- peça perdida de verdade) e a lista é cortada em `numLost`: mais nomes que isso seria
    -- inventar, e nomear o slot errado é pior que não nomear nenhum.
    local slots
    if C_EquipmentSet and C_EquipmentSet.GetItemLocations then
        local okLoc, locais = pcall(C_EquipmentSet.GetItemLocations, setID)
        if okLoc and type(locais) == "table" then
            slots = {}
            for slot, onde in pairs(locais) do
                if onde == -1 and #slots < c.perdidas then
                    slots[#slots + 1] = ns.Gear and ns.Gear.SlotName(slot) or tostring(slot)
                end
            end
            if #slots == 0 then slots = nil end
        end
    end

    return {
        nome = c.nome,
        perdidas = c.perdidas,
        slots = slots,
        consertavel = (itens > 0) and (vestidas + c.perdidas == itens) or false,
    }
end

---Grava o que o jogador está vestindo AGORA por cima do conjunto, consertando a peça que sumiu.
---
---`SaveEquipmentSet` só modifica conjunto existente e roda em contexto não contaminado — a mesma
---classe do `UseEquipmentSet`, que esta corrente já usa com sucesso. O retorno vai para o diário
---porque é aí que se descobre, de fora do jogo, se a chamada pegou.
function Data.SaveGearSet(setID)
    if not C_EquipmentSet or not C_EquipmentSet.SaveEquipmentSet then return false end
    local ok, err = pcall(C_EquipmentSet.SaveEquipmentSet, setID)
    if ns.Log then
        ns.Log.Call("gear", "SaveEquipmentSet(" .. tostring(setID) .. ")", ok, err)
    end
    return ok
end

---Por que o botão Carregar está apagado, ou `nil` se ele pode ser clicado.
---
---(!) A REGRA VIVE AQUI, e não dentro do desenho da linha. Ela já morou lá, e a sabotagem
---mostrou o custo: desligar a linha que apagava o botão **não reprovava nada**, porque nenhum
---teste alcança um widget. Regra que decide comportamento não pode morar onde só o olho vê.
---
---São dois motivos, e a ordem importa: peça perdida primeiro, porque ela vale para qualquer
---conjunto, e a restrição de especialização depois, porque ela só vale para conjunto que troca
---de spec — apagar por causa dela um conjunto que só mexe em itens seria punir o inocente.
---@return string|nil motivo
function Data.LoadBlockedReason(preset)
    if not preset then return nil end

    local problema = preset.gear and Data.GearSetProblem(preset.gear)
    if problema then
        return format(
            L["%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."],
            problema.nome or "?", problema.perdidas)
    end

    if preset.spec ~= nil and preset.spec ~= Data.GetCurrentSpecIndex() then
        local pode, motivo = Data.CanChangeSpec()
        if not pode then
            return motivo or L["the game refused to change specialization now; wait a few seconds."]
        end
    end

    return nil
end

---Que ação o botão da linha deve oferecer: nenhuma mudança, salvar, ou abrir o gerenciador.
---
---Vive aqui, e não na UI, por duas razões: a decisão é sobre **dado do jogo**, não sobre pixel;
---e assim o harness consegue afirmar sobre ela. A versão anterior dela morava dentro do desenho
---da linha, onde só um teste de widget alcançaria — e teste que não roda parece aprovado.
---@return string|nil `nil` (carregar normal), `"save"` ou `"manager"`
function Data.GearFixAction(preset)
    local problema = preset and preset.gear and Data.GearSetProblem(preset.gear)
    if not problema then return nil end
    return problema.consertavel and "save" or "manager"
end

---Abre o Gerenciador de Equipamento do jogo, na aba certa.
---
---Explicar onde fica é pior que levar: "abra a ficha do personagem, clique na terceira aba da
---lateral" é uma instrução que o jogador tem que executar, e ele está no meio de outra coisa.
---
---`ToggleCharacter` **alterna** — chamada com a ficha já aberta, ela FECHA. Por isso a guarda do
---`IsShown`, que é o mesmo cuidado que o EnhanceQoL toma (`EnhanceQoL.lua:7551`).
---
---A aba da lateral tem dois caminhos porque nem todo cliente expõe os dois; se nenhum existir, a
---ficha abre mesmo assim, que já é quase todo o caminho.
function Data.OpenEquipmentManager()
    if InCombatLockdown() then
        ns.Print(L["in combat: will apply when the fight ends."])
        return false
    end

    if CharacterFrame and CharacterFrame.IsShown and not CharacterFrame:IsShown() then
        if ToggleCharacter then pcall(ToggleCharacter, "PaperDollFrame") end
    elseif ToggleCharacter and not CharacterFrame then
        pcall(ToggleCharacter, "PaperDollFrame")
    end

    if PaperDollFrame_SetSidebar then
        pcall(PaperDollFrame_SetSidebar, nil, 3)
    elseif _G and _G.PaperDollSidebarTab3 and _G.PaperDollSidebarTab3.Click then
        pcall(_G.PaperDollSidebarTab3.Click, _G.PaperDollSidebarTab3)
    end
    return true
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
local running          -- { preset, steps, at, timer, report, progress, startedAt }

-- O RETRATO DO FIM DA ÚLTIMA TROCA. `running` é zerado no `Finish` — e é exatamente aí que o
-- resultado interessa: qual passo entrou, qual foi pulado, qual não deu. Sem guardar isto, a
-- tela de progresso sumiria no instante em que ela tem algo a dizer.
local lastRun
local listener

local function Report(text, isError)
    if running and running.report then running.report(text, isError) end
end

---O passo já está satisfeito no mundo, agora?
---
---⚑ EXISTE PARA UMA COISA SÓ: não acusar falha do que deu certo. Quando o prazo vence, a pergunta
---certa não é "o evento chegou?" mas "está aplicado?" — e o histórico deste addon mostra que as
---duas divergem: em 07/09 02:05:35 o `EQUIPMENT_SWAP_FINISHED` chegou com `true` e a leitura de
---estado ainda dizia que o conjunto não estava vestido. A confirmação dos passos continua sendo
---por EVENTO justamente por isso; esta leitura entra só no fim do prazo, dezenas de segundos
---depois, quando o estado já teve tempo de assentar.
---
---O pedido do usuário é literal: *"devo conseguir fazer as trocas sem que tenha erros"*. Reclamar
---de algo que está aplicado é o erro mais barato de eliminar.
local function StepSatisfied(name)
    if not running or not running.preset then return false end
    local preset = running.preset

    if name == "spec" then
        return preset.spec ~= nil and Data.GetCurrentSpecIndex() == preset.spec

    elseif name == "talent" then
        if not preset.talent then return false end
        -- Um loadout pertence a uma spec: sem a spec certa a comparação não significa nada.
        if preset.spec and Data.GetCurrentSpecIndex() ~= preset.spec then return false end
        local spec = Data.GetSpecByIndex(Data.GetCurrentSpecIndex())
        return spec ~= nil and Data.GetActiveLoadoutID(spec.id) == preset.talent

    elseif name == "gear" then
        return preset.gear ~= nil and Data.IsGearSetEquipped(preset.gear)

    elseif name == "transmog" then
        return preset.transmog ~= nil and Data.GetActiveOutfitID() == preset.transmog
    end

    return false
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

    if running then
        -- PASSO QUE FICOU EM "doing" NA HORA DO FIM É PASSO QUE NÃO CONFIRMOU. Chegar aqui com
        -- um passo em andamento só acontece por desistência ou por prazo vencido — quando o jogo
        -- confirma, o `RunNext` já fechou o passo como "done" antes de vir parar neste `Finish`.
        for _, key in ipairs(running.steps) do
            if running.progress and running.progress[key] == "doing" then
                running.progress[key] = "failed"
            end
        end
        lastRun = {
            preset = running.preset,
            steps = running.steps,
            progress = running.progress or {},
            startedAt = running.startedAt,
            tries = running.specTries or 0,
        }
    end

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
local RerunStep -- idem: o `RunNext` pausa em combate e pede o passo DE NOVO quando a luta acaba

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

        -- ⚑ ANTES DE ACUSAR, CONFERE O ESTADO. Esta é a maior fonte de "erro" que o jogador vê sem
        -- que nada tenha dado errado: o evento de confirmação não chegou (ou chegou e não era
        -- nosso), mas a troca aconteceu. Sem esta leitura o addon anuncia "o jogo não confirmou a
        -- tempo" sobre uma spec que já virou.
        --
        -- E o prazo é o lugar seguro para ler estado: são 20 a 45 segundos depois do pedido, não o
        -- instante seguinte a ele — que é o que fez a 0.13.2 travar a corrente.
        if StepSatisfied(passo) then
            if running.progress then running.progress[passo] = "done" end
            if ns.Log then
                ns.Log.Add("prazo", { passo = passo, desfecho = "ja estava aplicado" })
            end
            RunNext()
            return
        end

        -- ⚑ E O PRAZO PASSA A TER LINHA PRÓPRIA. Antes ele só aparecia no `fim`, dentro de
        -- `falhas`: no diário, um silêncio e depois o veredito. `insistindo` e `gravou` já têm
        -- linha; o prazo é o desfecho que mais precisa de uma.
        if ns.Log then ns.Log.Add("prazo", { passo = passo, desfecho = "nao confirmou" }) end

        -- O PASSO NÃO CONFIRMOU, E ISSO PRECISA FICAR MARCADO **ANTES** DO `RunNext`.
        --
        -- Sem esta linha o `RunNext` encontraria o passo ainda em "doing" e o promoveria a
        -- "done" — porque é assim que ele fecha um passo que o jogo confirmou. O prazo vencido é
        -- o caso oposto, e o resultado seria um ✓ verde num passo que o jogo nunca confirmou:
        -- a pior mentira que esta tela pode contar, porque ela contradiz a mensagem de falha que
        -- sai logo abaixo.
        if running.progress then running.progress[passo] = "failed" end

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

-- De quanto em quanto tempo insistir na troca de especialização, e por quantas vezes.
--
-- Quatro segundos porque foi o menor intervalo que o diário mostrou funcionando (02:42:48
-- recusado, 02:42:52 aceito). O teto vem do prazo do passo: `Arm()` já corta em 45 s, então as
-- tentativas param bem antes de o prazo estourar.
local SPEC_RETRY_DELAY = 4

-- O TETO E O BACKSTOP DE VERDADE, e nao o prazo do passo: `RetrySpec` chama `Arm()` a cada
-- tentativa, o que RE-ARMA os 45 segundos -- então o prazo sozinho nunca venceria enquanto
-- houvesse insistência. Sem este número a corrente insistiria para sempre, e ficar presa é o
-- travamento que esta sequência já produziu duas vezes.
--
-- (O harness não distingue os dois finais: o `RunTimers` dele dispara tudo o que está na fila de
-- uma vez, então sabotar o teto não reprova. Fica pelo raciocínio acima, que é do jogo.)
local SPEC_RETRY_MAX = 8

-- INSISTIR NO CARREGAMENTO DE TALENTOS, pela mesma razao que se insiste na troca de spec.
--
-- Diario real de 07/09 21:1x, a troca para "Frost PvP":
--
--     SetSpecialization(2)            -> true
--     ACTIVE_PLAYER_SPECIALIZATION_CHANGED
--     LoadConfig(66832448)            -> result = 0 (Error), changeError = **nil**
--
-- `Enum.LoadConfigResult.Error` e 0 (`ClassTalentsDocumentation.lua:501`), entao o passo estava
-- certo em chamar de falha. O que estava errado era DESISTIR: `changeError` veio `nil`, ou seja o
-- jogo recusou **sem dizer por que**, no instante seguinte a troca de spec -- que e justamente
-- quando ele acabou de reescrever a arvore de talentos inteira do lado do servidor.
--
-- E `CanEditTalents` tinha respondido que podia. De novo o padrao que este projeto ja pagou tres
-- vezes: o preditor diz "pode" e a chamada recusa mesmo assim.
--
-- ⚠️ O intervalo NAO E MEDIDO -- e o unico numero deste arquivo que nao e. So ha uma ocorrencia
-- registrada com o retorno completo, entao nao da para tirar padrao dela. Os 4 segundos vem da
-- recusa de spec, que e a mesma familia (recusa do servidor sem motivo declarado) e a unica que
-- este projeto mediu. Se o diario mostrar outra coisa, e este numero que muda.
local TALENT_RETRY_DELAY = 4
local TALENT_RETRY_MAX = 5      -- 20 s, abaixo do prazo de 30 s do passo

-- ⚑ GRAVAR TALENTO É UM CAST, E OS ITENS NÃO ENTRAM ENQUANTO ELE CORRE.
--
-- `LoadConfig` com `LoadInProgress` abre uma gravação, e a UI da Blizzard só a dá por terminada
-- quando o cast `COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID` termina
-- (`Blizzard_ClassTalentsFrame.lua:345-350`). O diário de 11/09 mostra o que acontece quando se
-- equipa antes disso — troca "Tank" -> "Frost PvP":
--
--     17:20:02  ACTIVE_PLAYER_SPECIALIZATION_CHANGED
--     17:20:02  LoadConfig(66832448)          -> LoadInProgress
--     17:20:02  TRAIT_CONFIG_UPDATED 59714245        <- o passo fechava AQUI
--     17:20:02  UseEquipmentSet(0)            -> true, true
--     17:20:02  TRAIT_CONFIG_UPDATED 59714244
--     17:20:02  EQUIPMENT_SWAP_FINISHED       -> false   (16 peças na bolsa, 0 perdidas)
--     17:20:07  TRAIT_CONFIG_UPDATED 59714245        <- a gravação terminando de verdade
--
-- O PAR DO MESMO INSTANTE É ECO DA TROCA DE SPEC, e não resposta ao `LoadConfig`: ele aparece nas
-- sete correntes gravadas que trocaram spec antes dos talentos, inclusive na de 07/09 21:10:59,
-- em que o `LoadConfig` falhou na hora e nada foi carregado. E nas 24 correntes do diário os
-- itens foram recusados em exatamente as TRÊS que abriram gravação (09/09 17:22:02 e 17:58:14,
-- 11/09 17:20:02) — e entraram em todas as outras 21.
--
-- O eco traz o MESMO `configID` do evento verdadeiro (59714245 nos dois). É por isso que o filtro
-- por id da 0.13.0 não tinha como dar certo, e nenhum outro filtro por id dará. O que separa os
-- dois é o tempo: o eco caiu no segundo do `LoadConfig` nas sete vezes, o verdadeiro chegou 4 a
-- 7 s depois nas três gravações.
--
-- Então o passo fecha com o PRIMEIRO de dois sinais:
--   1. o fim do cast de gravação — o que a própria Blizzard usa;
--   2. um `TRAIT_CONFIG_UPDATED` que chegue depois da janela do eco — a reserva, para o caso de o
--      cast não ser visto (`spellID` opaco, ou um cliente que mude o fluxo).
--
-- ⚠️ A JANELA NÃO É MEDIDA COM PRECISÃO: o diário grava segundos inteiros. O que se sabe é que o
-- eco caiu dentro do mesmo segundo sete vezes em sete, e o verdadeiro nunca antes de 4 s. 2 fica
-- no meio. O diário grava agora QUAL sinal fechou e em quantos segundos (`event = "gravou"`); se
-- vier "evento" com menos de 4 s, é este número que precisa ser revisto.
local COMMIT_SPELL_ID = Constants and Constants.TraitConsts
    and Constants.TraitConsts.COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID or 384255
local COMMIT_ECHO_WINDOW = 2

---Traduz o resultado de um passo para o estado que a janela desenha.
---
---UM LUGAR SO, e a razao e um defeito real: isto morava dentro do `RunNext`, e os caminhos de
---INSISTENCIA (`RetrySpec`, `RetryTalent`) chamam `Steps.*` direto, sem passar por ele. O passo
---que desistia depois do teto continuava marcado como "doing", e a chamada seguinte de `RunNext`
---o promovia a **"done"** -- um visto verde ao lado da mensagem de falha, que e a mesma mentira
---que o prazo vencido ja tinha produzido uma vez.
---
---"wait" nao aparece aqui de proposito: ele mantem "doing", que e o que ele significa.
local function NoteOutcome(name, outcome)
    if not running or not running.progress then return end

    -- `"skip"` só vira "pulado" quando o retrato de antes diz que já estava certo. Sem essa
    -- consulta, tudo o que virou no meio da corrente era anunciado como "nada a mudar".
    if outcome == "skip" then
        running.progress[name] = (running.already or {})[name] and "skipped" or "done"
    elseif outcome == "fail" or outcome == "abort" then
        running.progress[name] = "failed"
    end
end

local Steps = {}

---Insiste no carregamento do loadout quando o jogo recusa sem dizer por que.
---
---Espelha `RetrySpec` de proposito, inclusive na guarda do token: outra aplicação pode ter
---começado nesse meio tempo, e a tentativa marcada por esta já não manda mais.
local function RetryTalent(preset)
    running.talentTries = (running.talentTries or 0) + 1

    if running.talentTries > TALENT_RETRY_MAX then
        return "fail", L["the game kept refusing to load the talents."]
    end

    Report(L["Waiting for the game to accept the talents..."], false)
    if ns.Log then
        ns.Log.Add("insistindo", { passo = "talent", tentativa = running.talentTries })
    end

    Arm()

    local token = running
    C_Timer.After(TALENT_RETRY_DELAY, function()
        if not running or running ~= token then return end
        if running.steps[running.at] ~= "talent" then return end

        local outcome, message = Steps.talent(preset)
        if ns.Log then ns.Log.Step("talent", outcome or "wait", message) end
        NoteOutcome("talent", outcome)

        if outcome == "skip" then
            RunNext()
        elseif outcome == "abort" then
            Finish(false, message)
        elseif outcome == "fail" then
            running.failures = running.failures or {}
            running.failures[#running.failures + 1] = message
            RunNext()
        end
    end)

    return "wait"
end

---O que o personagem está conjurando agora, se algo.
---
---⛑ EXISTE POR CAUSA DE UM DEFEITO NOSSO, achado no diário em 21/09. Em **10 de 10** trocas
---gravadas que mexem em especialização, a primeira `SetSpecialization` era recusada e a segunda,
---quatro segundos depois, era aceita. A causa não era o jogo estar ocupado por conta própria: o
---botão Carregar troca a aparência por **ação segura no próprio clique** (`UI.lua`, atributo
---`"outfit"`), e isso **conjura** a magia 1247613 no mesmo instante. O jogo não deixa começar uma
---conjuração com outra em voo, então a recusa era **causada por nós**, sempre, e custava ao
---jogador uma barra de conjuração perdida mais quatro segundos de nada.
---
---O relato foi *"às vezes ele cast mais de uma vez"*. Era sempre; o "às vezes" é porque conjunto
---sem aparência, ou sem troca de spec, não passa por aqui.
local function CastInFlight()
    if UnitCastingInfo then
        local name, _, _, _, _, _, _, _, spellID = UnitCastingInfo("player")
        if name then return name, spellID end
    end
    if UnitChannelInfo then
        local name, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
        if name then return name, spellID end
    end
end

-- Espera curta e repetida: a conjuração de aparência dura cerca de um segundo, então o passo
-- costuma sair na primeira ou segunda olhada. O teto existe para o caso de o jogador estar
-- conjurando outra coisa qualquer — aí a insistência normal assume, como sempre assumiu.
local CAST_WAIT_STEP = 0.25
local CAST_WAIT_MAX = 3

---Espera a conjuração em voo terminar e só então pede a troca de spec.
---
---**NÃO consome tentativa de `RetrySpec`**: isto não é o jogo recusando, é a gente esperando a
---nossa própria conjuração sair do caminho. Gastar tentativa aqui encurtaria o orçamento de
---insistência de quem realmente precisa dele.
local function WaitForCast(preset, elapsed)
    elapsed = elapsed or 0
    Arm()

    local token = running
    C_Timer.After(CAST_WAIT_STEP, function()
        if not running or running ~= token then return end
        if running.steps[running.at] ~= "spec" then return end

        if CastInFlight() and elapsed + CAST_WAIT_STEP < CAST_WAIT_MAX then
            WaitForCast(preset, elapsed + CAST_WAIT_STEP)
            return
        end

        local outcome, message = Steps.spec(preset)
        if ns.Log then ns.Log.Step("spec", outcome or "wait", message) end
        NoteOutcome("spec", outcome)

        if outcome == "skip" then
            RunNext()
        elseif outcome == "abort" then
            Finish(false, message)
        elseif outcome == "fail" then
            running.failures = running.failures or {}
            running.failures[#running.failures + 1] = message
            RunNext()
        end
    end)

    return "wait"
end

---Insiste na troca de especialização até o jogo aceitar.
---
---A recusa não é um erro do jogador nem do addon: é o jogo dizendo "agora não". Devolver isso
---como falha obrigava o jogador a clicar de novo — que é exatamente o que esta função faz por
---ele, e sem transformar em erro o que é só espera.
local function RetrySpec(preset, wanted)
    running.specTries = (running.specTries or 0) + 1

    if running.specTries > SPEC_RETRY_MAX then
        return "abort", L["the game kept refusing to change specialization."]
    end

    Report(L["Waiting for the game to allow the specialization change..."], false)
    if ns.Log then
        ns.Log.Add("insistindo", { passo = "spec", tentativa = running.specTries })
    end

    -- `Arm()` continua sendo o teto: se o jogo nunca aceitar, o prazo do passo encerra.
    Arm()

    local token = running
    C_Timer.After(SPEC_RETRY_DELAY, function()
        -- Outra aplicação pode ter começado nesse meio tempo; esta já não manda mais.
        if not running or running ~= token then return end
        if running.steps[running.at] ~= "spec" then return end

        local outcome, message = Steps.spec(preset)
        if ns.Log then ns.Log.Step("spec", outcome or "wait", message) end
        NoteOutcome("spec", outcome)

        if outcome == "skip" then
            RunNext()
        elseif outcome == "abort" then
            Finish(false, message)
        elseif outcome == "fail" then
            running.failures = running.failures or {}
            running.failures[#running.failures + 1] = message
            RunNext()
        end
    end)

    return "wait"
end

function Steps.spec(preset)
    local wanted = preset.spec
    if not wanted or wanted == Data.GetCurrentSpecIndex() then return "skip" end

    -- PERGUNTA ANTES DE CHAMAR, com a condição da própria janela de talentos do jogo. O motivo
    -- vem dele e já vem traduzido; a nossa frase só entra quando ele não manda nenhum.
    local pode, motivo, porque = Data.CanChangeSpec()
    if ns.Log then
        ns.Log.Call("spec", "CanChangeSpec", pode, motivo,
            porque or SpecSpellID() or "magia desconhecida")
    end
    if not pode then
        -- ⚑ RECARGA NÃO É MOTIVO PARA DESISTIR — É MOTIVO PARA ESPERAR, e era a causa mais comum
        -- de o jogador receber "o jogo recusou trocar de especialização agora" logo depois de uma
        -- troca bem-sucedida. A recarga da magia acaba em segundos, e a insistência já existe.
        --
        -- Motivo EM TEXTO continua abortando: aí o jogo disse o que era (combate, área mítica), e
        -- insistir seria repetir uma pergunta já respondida.
        if porque and not motivo then
            return RetrySpec(preset, wanted)
        end
        return "abort", motivo
            or L["the game refused to change specialization now; wait a few seconds."]
    end

    -- ⛑ NÃO PEÇA COM CONJURAÇÃO EM VOO. Ver `CastInFlight`: a recusa que o addon vinha tratando
    -- como "o jogo está ocupado" era provocada pela nossa própria troca de aparência. Esperar
    -- aqui é mais barato que insistir depois — e some a segunda barra de conjuração.
    local conjurando, conjurandoID = CastInFlight()
    if conjurando then
        if ns.Log then
            ns.Log.Add("esperando cast", {
                passo = "spec", magia = conjurando, id = conjurandoID or 0,
            })
        end
        Report(L["Switching specialization..."], false)
        return WaitForCast(preset)
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
    -- ENGOLE O ERRO VERMELHO QUE A NOSSA PRÓPRIA CHAMADA VAI PROVOCAR.
    --
    -- Relato: *"quando troco o preset aparece uma mensagem do jogo mesmo 'Você não pode fazer isso
    -- agora', vai confundir o usuário, ele vai achar que não vai trocar nada, mas tá funcionando"*.
    -- Ele está certo: a recusa é transitória e o addon já insiste sozinho, então o erro do jogo
    -- descreve um estado que deixa de valer quatro segundos depois.
    --
    -- `SuppressMessagesThisFrame` é método da própria Blizzard
    -- (`Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua:182-189`) e é do tamanho certo: vale por
    -- **um quadro** e se desarma sozinho com um `C_Timer.After(0, …)`. Não é
    -- `UnregisterEvent`, que apagaria erro alheio por tempo indeterminado — o erro que se engole
    -- aqui é só o que a nossa linha seguinte provoca.
    --
    -- E não se perde informação: o motivo continua no diário, e o passo continua reportando o que
    -- aconteceu na janela. O que sai da tela é a contradição — vermelho dizendo "não pode"
    -- enquanto o addon está resolvendo.
    if UIErrorsFrame and UIErrorsFrame.SuppressMessagesThisFrame then
        pcall(UIErrorsFrame.SuppressMessagesThisFrame, UIErrorsFrame)
    end

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
    -- RECUSA E TRANSITÓRIA: ESPERA E TENTA DE NOVO, em vez de devolver erro ao jogador.
    --
    -- Foi o diário dele que fechou isto, depois de eu errar a previsão TRÊS vezes:
    --
    --   02:42:14  SetSpecialization(1) -> true    (sucesso)
    --   02:42:28  SetSpecialization(2) -> false   (recusado)
    --   02:42:37  SetSpecialization(2) -> true    (nove segundos depois, sucesso)
    --   02:42:48  SetSpecialization(1) -> false   (recusado)
    --   02:42:52  SetSpecialization(1) -> true    (quatro segundos depois, sucesso)
    --
    -- **Tentar de novo sempre funciona.** E as três coisas que eu tentei usar para PREVER a
    -- recusa foram desmentidas pelo mesmo arquivo: `CanPlayerUseTalentSpecUI` respondeu `true` em
    -- todas elas; a recarga da magia 200749 (aprendida do próprio jogo) estava inativa; e não há
    -- janela de tempo fixa — o intervalo refutado varia de 4 a 14 segundos.
    --
    -- Então o addon para de adivinhar e faz o que o jogador faria: espera e clica de novo. Ele
    -- disse que *"não tem problema demorar um pouco"*, e o prazo do passo (45 s) é o teto.
    if not ok or aceito == false then
        -- GRAVA O QUE ESTAVA CONJURANDO NA HORA DA RECUSA. É a prova, ou a refutação, da causa
        -- diagnosticada em 21/09: se a guarda acima estiver certa, este campo passa a vir
        -- `nenhum` e a recusa some do diário. Se continuar aparecendo com magia, a causa é outra
        -- e o próximo diário diz qual — em vez de eu chutar de novo.
        if ns.Log then
            local emVoo, emVooID = CastInFlight()
            ns.Log.Add("recusa", {
                passo = "spec", conjurando = emVoo or "nenhum", id = emVooID or 0,
            })
        end
        return RetrySpec(preset, wanted)
    end

    Arm()
    return "wait"
end

---A mensagem do JOGO, quando ele der uma.
---
---O texto vem localizado e diz a causa concreta ("você não pode fazer isso em combate", "não é
---possível numa área de dificuldade Mítica"…). A nossa frase genérica só entra quando o jogo
---não explicou — e aí ela é honesta, porque de fato não se sabe.
---O nome do valor de `Enum.LoadConfigResult`, para o diario dizer `Error` em vez de `0`.
local function LoadConfigResultName(result)
    local E = Enum and Enum.LoadConfigResult
    if not E or result == nil then return result end
    for name, value in pairs(E) do
        if value == result then return name .. "(" .. tostring(result) .. ")" end
    end
    return result
end

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

    -- ⚑ O LOADOUT AINDA EXISTE? O id fica salvo em `RocketSwapDB.presets` e o jogador pode apagar
    -- o loadout na janela de talentos a qualquer momento. Sem esta conferência o addon chamava
    -- `LoadConfig` num id morto e o jogador ouvia "o jogo continuou recusando carregar os
    -- talentos" depois de cinco tentativas e vinte segundos — causa errada, espera inútil.
    --
    -- É a mesma resposta que a aparência já dava ("esse conjunto não existe mais"), e o que a UI
    -- nativa faz no caso equivalente: `ERR_TALENT_FAILED_INVALID_CONFIG`
    -- (`Blizzard_ClassTalentsFrame.lua:1743`).
    --
    -- Só decide quando a lista existe: cliente sem a API devolve lista vazia, e aí "não achei" não
    -- prova que foi apagado.
    if spec then
        local loadouts = Data.GetLoadouts(spec.id)
        if #loadouts > 0 then
            local existe = false
            for _, l in ipairs(loadouts) do
                if l.configID == preset.talent then existe = true end
            end
            if not existe then
                return "fail", L["that talent loadout no longer exists."]
            end
        end
    end

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
    running.commit = nil        -- só uma gravação aberta POR ESTA chamada confirma o passo
    local ok, result, changeError = pcall(C_ClassTalents.LoadConfig, preset.talent, true)
    if ns.Log then
        -- O NOME DO ENUM, NAO SO O NUMERO. Ler `result = 0` no diario custou uma ida a
        -- documentacao para descobrir que 0 e `Error` -- e o diario existe para responder na
        -- hora, nao para mandar procurar.
        ns.Log.Call("talent", "LoadConfig(" .. tostring(preset.talent) .. ")",
            ok, LoadConfigResultName(result), changeError)
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
        -- COM MOTIVO, REPORTA; SEM MOTIVO, INSISTE.
        --
        -- A distincao e o coracao da correcao. Quando `changeError` traz uma string, o jogo
        -- disse o que houve -- combate, area errada, restricao de instancia -- e insistir seria
        -- repetir uma pergunta ja respondida: reporta com as palavras dele.
        --
        -- Quando vem `nil`, o jogo recusou e nao explicou. Foi o caso do diario, logo depois da
        -- troca de spec. Recusa sem motivo declarado, neste addon, ja se provou transitoria uma
        -- vez (a da spec) -- e insistir e correto nas duas leituras possiveis: se for passageira,
        -- resolve; se for permanente, o teto devolve a mesma falha de antes, so que alguns
        -- segundos depois.
        if type(changeError) == "string" and changeError ~= "" then
            return "fail", TalentError(changeError)
        end
        return RetryTalent(preset)
    end

    -- LoadInProgress: a gravação começou, e ela é um cast (ver `COMMIT_ECHO_WINDOW`). A hora é o
    -- que separa o eco da troca de spec da confirmação de verdade.
    running.commit = { since = GetTime() }
    Arm()
    return "wait"           -- confirma no fim do cast de gravação (ou no TRAIT_CONFIG_UPDATED tardio)
end

-- Quantas vezes o passo de itens espera um cast acabar antes de desistir. O caso medido é UMA (o
-- cast de gravação de talentos); três deixa folga para o jogador lançar mais alguma coisa sem
-- deixar a corrente pendurada em quem não para de conjurar.
local GEAR_CAST_WAIT_MAX = 3

function Steps.gear(preset)
    if not preset.gear then return "skip" end
    if Data.GetEquippedSetID() == preset.gear then return "skip" end

    -- ⚑ O CONJUNTO AINDA EXISTE? `GetEquipmentSetInfo` não devolve nada para id apagado
    -- (`MayReturnNothing`), e é assim que a ficha do personagem decide desabilitar o botão
    -- Equipar (`PaperDollFrame.lua:2450-2468`). Sem isto o addon pedia a troca, o jogo não fazia
    -- nada, e o jogador recebia a frase genérica "não deu para equipar o conjunto de itens" — que
    -- manda procurar peça faltando onde o problema é outro.
    if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo
        and not Data.GearSetCounts(preset.gear) then
        return "fail", L["that gear set no longer exists."]
    end

    -- As três guardas que o próprio jogo usa antes de equipar um conjunto. A ordem importa
    -- só para a mensagem: cada falha tem a sua, porque `UseEquipmentSet` não devolve motivo.
    if C_EquipmentSet.EquipmentSetContainsLockedItems
        and C_EquipmentSet.EquipmentSetContainsLockedItems(preset.gear) then
        return "fail", L["some items of this set are locked (in use, or in the mail)."]
    end
    -- ⚑ CAST EM CURSO NÃO É FALHA, É ESPERA. Diário de 11/09 17:46:01, a primeira troca que
    -- exercitou a 0.22.0:
    --
    --     17:46:01  UNIT_SPELLCAST_SUCCEEDED 384255   -> o passo de talentos fecha (certo)
    --     17:46:01  passo gear -> fail "você está conjurando algo"
    --
    -- O cast que acabara de TERMINAR ainda constava. A barra de cast do jogo nem olha o
    -- SUCCEEDED: ela só dá o cast por encerrado no `UNIT_SPELLCAST_STOP`, e é ali que a
    -- informação dele deixa de existir (`CastingBarFrame.lua:459,482-483`). Recusar por isso
    -- derrubava os itens justamente na troca que o addon existe para fazer. Agora o passo espera o
    -- fim do cast — STOP, FAILED ou INTERRUPTED do jogador — e tenta de novo.
    --
    -- O TETO é para o jogador que segue conjurando uma magia atrás da outra: sem ele a espera se
    -- re-armaria a cada cast e o prazo nunca venceria.
    local conjurando, _, _, _, _, _, _, _, magia = UnitCastingInfo("player")
    if conjurando then
        running.gearCastWaits = (running.gearCastWaits or 0) + 1
        -- O QUE ESTÁ SENDO CONJURADO vai para o diário. A recusa das 17:46:01 não dizia, e foi
        -- preciso deduzir pelo instante que era o próprio cast de gravação.
        if ns.Log then ns.Log.Call("gear", "UnitCastingInfo", conjurando, magia) end
        if running.gearCastWaits > GEAR_CAST_WAIT_MAX then
            return "fail", L["you are casting something — try again in a second."]
        end
        running.gearWaitsCast = true
        Arm()
        return "wait"       -- o fim do cast chama o passo de novo (`RerunStep`)
    end

    Report(L["Equipping gear..."], false)

    -- O RETRATO ANTES DA CHAMADA. Depois dela não adianta: se a troca começar, as contagens já
    -- mudaram. É o que separa "o conjunto pedia peça que não existe" de "o jogo recusou por
    -- outro motivo" quando o evento voltar `false`.
    if ns.Log then
        ns.Log.Call("gear", "estado de " .. tostring(preset.gear),
            Data.DescribeGearSet(preset.gear) or "sem resposta")
    end

    -- ⚑ O SEGUNDO RETORNO ERA JOGADO FORA, e o cabeçalho deste arquivo já mandava não jogar:
    -- *"Cada passo espera o evento de confirmação E olha o retorno"*. `ok` é do `pcall` e
    -- responde "estourou?"; quem responde "o jogo aceitou?" é `setWasEquipped`
    -- (`EquipmentManagerDocumentation.lua:287-299`). Dos três passos da corrente, este era o
    -- único que não olhava — e por isso era o único cuja recusa não aparecia no diário.
    local ok, equipou = pcall(C_EquipmentSet.UseEquipmentSet, preset.gear)
    if ns.Log then
        ns.Log.Call("gear", "UseEquipmentSet(" .. tostring(preset.gear) .. ")", ok, equipou)
    end
    if not ok then return "fail", Data.GearFailureReason(preset.gear) end

    -- RECUSA IMEDIATA NÃO SE ESPERA. Sem swap, `EQUIPMENT_SWAP_FINISHED` não vem — e o passo
    -- ficaria os 20 segundos do prazo esperando um evento que ninguém vai mandar, para no fim
    -- dizer "o jogo não confirmou a tempo". É o mesmo defeito que a spec e os talentos já
    -- tiveram, corrigido nos dois; aqui ele continuava de pé.
    if equipou == false then
        return "fail", Data.GearFailureReason(preset.gear)
    end

    Arm()
    return "wait"           -- confirma em EQUIPMENT_SWAP_FINISHED
end

---A aparência é o ÚLTIMO da corrente — mas quem a troca já trocou lá no começo.
---
---A razão escrita aqui antes ("equipar itens mexe nas peças, então a roupa vem depois") descrevia
---um pedido que este addon **não faz mais**. Trocar de conjunto de aparência é privilégio de
---código seguro: quem dispara é a ação `outfit` armada no botão, dentro do próprio clique, antes
---de `Data.Apply` sequer existir. O addon aqui **confere e espera**, não pede.
---
---Então o que a última posição resolve é a CONFERÊNCIA: perguntar "a roupa entrou?" depois de os
---itens terem sido equipados, e não antes. Deixar a frase antiga no lugar era garantir que a
---próxima leitura refizesse o mesmo raciocínio errado.
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
--------------------------------------------------------------------------------
RunNext = function()
    if not running then return end

    -- O PASSO QUE ESTAVA ESPERANDO ACABOU DE SER CONFIRMADO. Quem chama `RunNext` de fora e o
    -- ouvinte de eventos, e chegar aqui com o passo em "doing" significa que o jogo confirmou.
    local anterior = running.steps[running.at]
    if anterior and running.progress and running.progress[anterior] == "doing" then
        running.progress[anterior] = "done"
    end

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
    -- O PASSO COMECOU. A janela le isto para mostrar em qual etapa a troca esta.
    running.progress = running.progress or {}
    running.progress[name] = "doing"

    -- ⚑ COMBATE NO MEIO DA CORRENTE PAUSA, NÃO FALHA. `Data.Apply` já enfileira quando o clique
    -- acontece em combate, mas nada reavaliava depois de começar: entrar em combate no meio fazia
    -- o jogo recusar passo por passo, e o jogador terminava com resultado parcial e uma fila de
    -- mensagens de erro — três das quatro descrevendo a MESMA causa.
    --
    -- `RunWhenSafe` é a fila que já existe (`Core.lua:33-39`, esvaziada em `PLAYER_REGEN_ENABLED`),
    -- e o token guarda contra o caso de outra corrente ter começado nesse meio tempo.
    --
    -- Sem `Arm()` de propósito: passo pausado não tem prazo correndo. Um prazo vencendo durante a
    -- luta acusaria falha de algo que o addon nem tentou.
    -- ⚑ `running.preset[name]` NÃO É REDUNDANTE, e o harness pegou isto na primeira rodada: a
    -- corrente tem SEMPRE os quatro passos, e o passo que o conjunto não define só passa por aqui
    -- para devolver "skip". Sem esta condição, um conjunto só de spec+itens pausava no passo de
    -- TALENTOS — parado durante a luta inteira num passo sem trabalho, e invisível na tela, porque
    -- o painel só desenha os passos que o conjunto define (`Data.GetProgress`). É a mesma
    -- condição do painel, de propósito.
    if COMBAT_SENSITIVE[name] and running.preset[name] and InCombatLockdown() then
        Report(L["in combat: will apply when the fight ends."], false)
        if ns.Log then ns.Log.Add("pausado", { passo = name, motivo = "combate" }) end

        local token = running
        ns.RunWhenSafe(function()
            if not running or running ~= token then return end
            if running.steps[running.at] ~= name then return end
            RerunStep(name)
        end)
        return
    end

    local okStep, outcome, message = pcall(Steps[name], running.preset)
    if not okStep then
        if ns.Log then ns.Log.Step(name, "erro de lua", tostring(outcome)) end
        message = L["an internal error interrupted this step."]
        outcome = "fail"
    elseif ns.Log then
        ns.Log.Step(name, outcome or "wait", message)
    end

    NoteOutcome(name, outcome)

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
--------------------------------------------------------------------------------
-- (!) ALL OR NOTHING: EVERY STEP IS CHECKED BEFORE ANY IS TAKEN (26/09)
--
-- The user: *"temos que mapear os possíveis erros e avisar ao usuário e adicionar algumas
-- seguranças para evitar de dar erro ao trocar e ficar coisa pelo meio do caminho, ou troca tudo
-- ou não troca nada e avisa"* -- and the macro on the bar makes the click fast. The log had it:
-- of 18 swaps, the 4 that went wrong all ended "loaded, except the appearance" (on cooldown twice,
-- not confirmed in time, not by the click) -- spec, talents and gear changed, the outfit did not.
--
-- So before the chain starts, each step the preset needs is asked of the game, and ONE "no"
-- stops everything, with the reason and, where the game lets us read it, the time left:
--   combat                 InCombatLockdown
--   specialization         CanPlayerUseTalentSpecUI + the spec spell's cooldown (`CanChangeSpec`),
--                          and standing still: the change is a cast, and moving cuts it
--   talents                C_ClassTalents.CanEditTalents -- "true if the player could switch
--                          talents if they staged a proper loadout", with the game's reason
--   gear                   a missing piece (`GearSetProblem`), locked items
--   appearance             `TransmogBlockedBy` (cooldown, style event, locked set) -- and it only
--                          changes through a click on the preset's secure button or macro
-- Cooldown SECONDS only where they are not secret: `startTime`/`duration` are secret in combat,
-- encounters, M+ and PvP (`SpellSharedDocumentation.lua`); there the warning has no time.
--------------------------------------------------------------------------------
local function SegundosDeRecarga(spellID)
    local getCD = spellID and C_Spell and C_Spell.GetSpellCooldown
    if not getCD then return nil end
    local ok, cd = pcall(getCD, spellID)
    if not (ok and type(cd) == "table" and cd.isActive == true) then return nil end
    local ini, dur = cd.startTime, cd.duration
    if issecretvalue and (issecretvalue(ini) or issecretvalue(dur)) then return nil end
    if type(ini) ~= "number" or type(dur) ~= "number" or not GetTime then return nil end
    local falta = ini + dur - GetTime()
    return falta > 0 and math.ceil(falta) or nil
end

---"45 s", "1 min 5 s".
function Data.TimeText(s)
    if not s then return nil end
    if s >= 60 then return format(L["%d min %d s"], math.floor(s / 60), s % 60) end
    return format(L["%d s"], s)
end

local function Com(msg, s)
    return s and (msg .. "  " .. format(L["(you can switch in %s)"], Data.TimeText(s))) or msg
end

---Everything that stops this preset from switching NOW, one line per reason; empty = go.
---@param byClick boolean the click on the secure button/macro (the only way the outfit changes)
---@return table list of { step, text, seconds }
function Data.Preflight(preset, byClick)
    local out = {}
    local function Nao(step, text, s) out[#out + 1] = { step = step, text = Com(text, s), seconds = s } end
    if not preset then return out end

    if InCombatLockdown() then
        Nao("combat", L["in combat: nothing was changed. Switch after the fight."])
        return out
    end

    local specAtual = Data.GetCurrentSpecIndex()
    local trocaSpec = preset.spec ~= nil and preset.spec ~= specAtual
    if trocaSpec then
        local pode, motivo, recarga = Data.CanChangeSpec()
        if not pode then
            if recarga then
                Nao("spec", L["changing specialization is on cooldown."], SegundosDeRecarga(SpecSpellID()))
            else
                Nao("spec", motivo or L["the game refused to change specialization now; wait a few seconds."])
            end
        elseif GetUnitSpeed and (GetUnitSpeed("player") or 0) > 0 then
            Nao("spec", L["stand still: changing specialization is a cast, and moving cuts it."])
        end
    end

    if preset.talent then
        local specAlvo = Data.GetSpecByIndex(preset.spec or specAtual)
        -- DELETED since the preset was saved: its own reason, before anything else.
        if specAlvo then
            local loadouts = Data.GetLoadouts(specAlvo.id)
            if #loadouts > 0 then
                local existe = false
                for _, l in ipairs(loadouts) do if l.configID == preset.talent then existe = true end end
                if not existe then Nao("talent", L["that talent loadout no longer exists."]) end
            end
        end
        local jaTem = not trocaSpec and specAlvo and Data.GetActiveLoadoutID(specAlvo.id) == preset.talent
        if not jaTem and C_ClassTalents and C_ClassTalents.CanEditTalents then
            local ok, pode, erro = pcall(C_ClassTalents.CanEditTalents)
            if ok and pode == false then
                Nao("talent", (type(erro) == "string" and erro ~= "") and erro or L["talents cannot be changed here."])
            end
        end
    end

    if preset.gear and Data.GetEquippedSetID() ~= preset.gear then
        local problema = Data.GearSetProblem(preset.gear)
        if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo and not Data.GearSetCounts(preset.gear) then
            Nao("gear", L["that gear set no longer exists."])
        elseif problema then
            Nao("gear", format(L["%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."],
                problema.nome or "?", problema.perdidas))
        elseif C_EquipmentSet and C_EquipmentSet.EquipmentSetContainsLockedItems then
            local ok, travado = pcall(C_EquipmentSet.EquipmentSetContainsLockedItems, preset.gear)
            if ok and travado then Nao("gear", L["some items of the set are locked (a trade, the bank, a repair)."]) end
        end
    end

    if preset.transmog and Data.GetActiveOutfitID() ~= preset.transmog then
        if not Data.OutfitIndex(preset.transmog) then
            Nao("transmog", L["that transmog outfit no longer exists."])
        elseif not byClick then
            Nao("transmog", L["the appearance only changes by clicking the preset (window, or its macro on the bar)."])
        else
            local motivo = Data.TransmogBlockedBy(preset.transmog)
            if motivo then
                local s = (motivo == L["changing appearance is on cooldown."]) and SegundosDeRecarga(TransmogSpellID()) or nil
                Nao("transmog", motivo, s)
            end
        end
    end
    return out
end

---The warning, where the player is looking: the red line in the middle of the screen (the game's
---own error line -- the macro on the bar is clicked with the eyes on the fight), chat, and the
---window's status.
function Data.Warn(preset, blockers, report)
    local nome = preset and preset.name or "?"
    local cab = format(L["%s was NOT loaded — nothing was changed:"], nome)
    local primeiro = blockers[1] and blockers[1].text or ""
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, nome .. ": " .. primeiro, 1, 0.1, 0.1)
    end
    ns.Print(cab)
    for _, b in ipairs(blockers) do print("    - " .. b.text) end
    -- In the window the preset is already selected: the reason alone, the game's own words.
    if report then report(primeiro, true) end
    if ns.Log then
        local passos = {}
        for _, b in ipairs(blockers) do passos[#passos + 1] = b.step end
        ns.Log.Add("recusado", { motivo = "pre-voo", conjunto = nome, passos = table.concat(passos, ","),
            texto = primeiro, segundos = blockers[1] and blockers[1].seconds })
    end
end

function Data.Apply(preset, report, byClick)
    if not preset then return false end

    -- In combat nothing is queued any more: the user asked for "nothing, and a warning".
    if InCombatLockdown() then
        Data.Warn(preset, Data.Preflight(preset, byClick), report)
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

    -- (!) CONJUNTO DE ITENS QUEBRADO NÃO TROCA — avisa e manda consertar primeiro.
    --
    -- Relato de 22/09: o jogador trocou uma peça e vendeu a anterior sem salvar o conjunto. O
    -- jogo põe o nome do conjunto em vermelho; o addon trocava assim mesmo, mas o passo nunca
    -- fechava com o "V", porque com peça perdida o `isEquipped` do jogo nunca fica `true`.
    --
    -- ⚠️ E O "V" QUE FALTA É O MENOR DOS PROBLEMAS. O jogo não deixa o slot vazio: ele **mantém
    -- equipado o que já estava lá**. Ou seja, a troca "dá certo" e você sai com a peça do papel
    -- ANTERIOR num conjunto do papel novo — o berloque de dano no conjunto de tanque — sem nada
    -- na tela dizendo isso. Palavras do usuário: *"na troca ele mantém a atual equipada e pode
    -- estar errado porque o usuário não salvou ainda a certa"*.
    --
    -- Um "V" que não aparece é confusão; uma peça errada em combate é prejuízo. Por isso a
    -- corrente nem começa: o bloqueio existe para o jogador **confirmar e salvar** o conjunto
    -- certo antes de trocar, e aí a troca sair de fato correta.
    local problema = preset.gear and Data.GearSetProblem(preset.gear)
    if problema then
        local msg = format(L["%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."],
            problema.nome or "?", problema.perdidas)
        if problema.slots then
            msg = msg .. "  (" .. table.concat(problema.slots, ", ") .. ")"
        end
        ns.Print(msg)
        -- A SAÍDA, em uma linha. Recusar sem dizer o caminho é só uma parede.
        if problema.consertavel then
            ns.Print(L["You are already wearing the rest of it — use /rs fix to update the set."])
        else
            ns.Print(L["Open the equipment manager, fix the set and save it, then switch."])
        end
        if report then report(msg, true) end
        if ns.Log then
            ns.Log.Add("recusado", {
                motivo = "conjunto de itens com peca perdida",
                conjunto = problema.nome or "?",
                perdidas = problema.perdidas,
                consertavel = problema.consertavel and "sim" or "nao",
            })
        end
        return false
    end

    -- THE REST OF THE PRE-FLIGHT (the missing piece above keeps its longer message and the way
    -- out). One "no" and nothing starts.
    local impedimentos = Data.Preflight(preset, byClick)
    if #impedimentos > 0 then
        Data.Warn(preset, impedimentos, report)
        return false
    end

    if Data.IsLoaded(preset) then
        -- CLIQUE QUE NÃO FEZ NADA TAMBÉM É INFORMAÇÃO. Sem esta linha, um clique que não virou
        -- corrente ficava invisível no diário — e "cliquei e não aconteceu nada" é relato comum.
        if ns.Log then
            ns.Log.Add("recusado", { motivo = "ja esta carregado", conjunto = preset.name or "?" })
        end
        if report then
            report(format(L["Nothing to change — %s is already loaded."], preset.name or "?"), false)
        end
        return false
    end

    running = {
        preset = preset, steps = { "spec", "talent", "gear", "transmog" }, at = 0,
        report = report, byClick = byClick and true or false,
        progress = {},
        -- QUEM MARCA A HORA É QUEM COMEÇA. A janela pode ser aberta no meio da troca, e um
        -- relógio zerado na abertura contaria uma espera menor do que a real.
        startedAt = GetTime and GetTime() or 0,

        -- O QUE JÁ ESTAVA CERTO ANTES DE A CORRENTE COMEÇAR.
        --
        -- `Steps.*` devolve `"skip"` por três razões diferentes, e as três chegavam à tela como a
        -- mesma frase — "nada a mudar". Numa delas isso é mentira, e justamente na mais comum:
        --
        --   1. o conjunto não define o campo         → não é passo, e nem vira linha (`GetProgress`)
        --   2. já estava certo antes de começar      → "nada a mudar" é verdade
        --   3. **ficou certo DURANTE a corrente**    → mudou, e a tela dizia que não
        --
        -- O caso 3 é o da aparência: quem troca a roupa é o clique seguro, no primeiro instante;
        -- quando o passo dela finalmente roda, dois ou três passos depois, a roupa já está certa e
        -- `Steps.transmog` devolve `"skip"`. O painel então anunciava **"Aparência — nada a
        -- mudar"** sobre a peça que aquele mesmo clique acabara de trocar — o oposto exato do que
        -- este painel existe para dizer.
        --
        -- O retrato tirado agora separa os dois: pulado só é "nada a mudar" se já estava assim
        -- ANTES. O que virou no meio do caminho é conclusão, e é assim que aparece.
        already = {
            spec = preset.spec and Data.GetCurrentSpecIndex() == preset.spec or nil,
            gear = preset.gear and Data.GetEquippedSetID() == preset.gear or nil,
            transmog = preset.transmog and Data.GetActiveOutfitID() == preset.transmog or nil,
            -- O talento depende da spec, e a spec pode virar no meio. Só dá para afirmar que ele
            -- "já estava certo" quando a corrente não vai mexer na especialização.
            talent = preset.talent and (not preset.spec
                or preset.spec == Data.GetCurrentSpecIndex()) and (function()
                    local spec = Data.GetSpecByIndex(Data.GetCurrentSpecIndex())
                    return spec and Data.GetActiveLoadoutID(spec.id) == preset.talent or nil
                end)() or nil,
        },
    }

    -- O RETRATO DE ANTES. É a linha que responde "a troca nem precisava acontecer" e "ela pedia
    -- algo que não existe mais" — dois casos que já apareceram e que o chat não mostrava.
    if ns.Log then ns.Log.Apply(preset, byClick) end
    if report then report(format(L["Loading %s..."], preset.name or "?"), false) end

    Data.EnsureListener()
    -- O painel flutuante abre aqui, e não dentro do `RunNext`: se abrisse lá, uma troca em que
    -- todos os passos fecham no mesmo quadro piscaria na tela sem chegar a ser lida.
    if ns.Progress then ns.Progress.Start() end
    RunNext()
    return true
end

function Data.IsApplying()
    return running ~= nil
end

---O estado de cada passo da troca, na ordem em que acontecem — a da troca em curso, ou o retrato
---da última que terminou.
---
---É a API mínima para a janela desenhar o progresso: a lista dos passos, e uma tabela com o
---contexto que ela precisa para escrever uma linha de estado. A janela **não** enxerga `running`,
---prazos nem a mecânica dos eventos — se enxergasse, duas partes do addon saberiam a mesma coisa,
---e a segunda divergiria na primeira mudança.
---
---Estados possíveis, e são exatamente os que a corrente já produz — nenhum inventado:
---
---  `pending`  ainda não chegou a vez
---  `doing`    em andamento (inclui o passo que espera o jogo confirmar)
---  `done`     o jogo confirmou
---  `skipped`  não havia o que fazer — **não é falha**, e a tela não pode dizer que é
---  `failed`   não deu, e o motivo já foi para o relatório e para o diário
---
---`info.live` separa as duas leituras: `true` é troca acontecendo agora, `false` é o retrato do
---fim. A janela precisa da diferença para saber quando parar a animação e quando devolver o
---editor — e ler "acabou" como "nunca começou" apagaria o resultado bem na hora de mostrá-lo.
---
---@return table[]|nil passos lista de `{ key, label, state }`
---@return table|nil info `{ preset, live, startedAt, tries }`
function Data.GetProgress()
    local src = running or lastRun
    if not src then return nil end

    -- FORA O QUE O CONJUNTO NÃO PEDE. Um conjunto só de itens abria quatro linhas, três delas
    -- dizendo "nada a mudar" — o que faz a troca parecer maior do que é e enterra a única linha
    -- que importa no meio de ruído. É a mesma regra que o `Subtitle` da lista já pratica: só
    -- entra o que o conjunto define.
    local out = {}
    for _, key in ipairs(src.steps) do
        if src.preset and src.preset[key] then
            out[#out + 1] = {
                key = key,
                label = StepName(key),
                state = (src.progress and src.progress[key]) or "pending",
            }
        end
    end

    return out, {
        preset = src.preset,
        live = running ~= nil,
        startedAt = src.startedAt or 0,
        -- Quantas vezes o passo de especialização já insistiu. **A janela não desenha isto** —
        -- o usuário pediu para tirar o contador da tela, e ele está certo: é mecânica interna,
        -- e o jogador não decide nada com ela. Fica aqui porque é o diário e o `/rs log` que a
        -- leem, e porque tirá-la do `info` obrigaria a corrente a expor `running` para isso.
        tries = src.specTries or src.tries or 0,
    }
end

--------------------------------------------------------------------------------
-- Confirmação: os eventos que fecham cada passo
--------------------------------------------------------------------------------
---O ouvinte só existe enquanto o addon precisa dele. Registrar `TRAIT_CONFIG_UPDATED` e
---`EQUIPMENT_SWAP_FINISHED` o tempo todo faria o addon acordar em toda troca manual do
---jogador, e não há nada a fazer nesses casos.
-- Os eventos de cast que o ouvinte escuta. Todos só interessam do jogador e com corrente em curso.
local CAST_EVENTS = {
    UNIT_SPELLCAST_SUCCEEDED   = true,
    UNIT_SPELLCAST_STOP        = true,
    UNIT_SPELLCAST_FAILED      = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
}

---Roda de novo o passo em curso quando o que o fazia esperar acabou.
---
---O mesmo desfecho que `RunNext` dá a um passo, sem avançar o índice — e com o mesmo `pcall`,
---pela mesma razão: erro de Lua aqui dentro deixaria `running` preso e o botão mudo.
RerunStep = function(name)
    local okStep, outcome, message = pcall(Steps[name], running.preset)
    if not okStep then
        if ns.Log then ns.Log.Step(name, "erro de lua", tostring(outcome)) end
        message, outcome = L["an internal error interrupted this step."], "fail"
    elseif ns.Log then
        ns.Log.Step(name, outcome or "wait", message)
    end
    NoteOutcome(name, outcome)

    if outcome == "skip" then
        RunNext()
    elseif outcome == "abort" then
        Finish(false, message)
    elseif outcome == "fail" then
        if not running then return end
        running.failures = running.failures or {}
        running.failures[#running.failures + 1] = message
        RunNext()
    end
end

-- Quantas vezes o cast de troca de spec pode ser cortado antes de o addon desistir. Três porque
-- cada corte é uma ação do jogador (andar, ser interrompido) e repetir três vezes já é sinal de que
-- ele não quer esperar parado.
local SPEC_CAST_CUT_MAX = 3

---O cast que acabou de falhar era o de trocar de especialização?
---
---`IsSpecializationActivateSpell` é o predicado que a própria janela de talentos usa para
---reconhecer o cast dela (`Blizzard_ClassSpecializationsFrame.lua:185-190`). A magia aprendida
---fica como reserva, para o caso de o predicado não existir neste cliente.
local function IsSpecCast(spellID)
    if issecretvalue and issecretvalue(spellID) then return false end
    if type(spellID) ~= "number" then return false end

    if IsSpecializationActivateSpell then
        local ok, ehDeSpec = pcall(IsSpecializationActivateSpell, spellID)
        if ok then return ehDeSpec and true or false end
    end
    return spellID == SpecSpellID()
end

---O cast de troca de spec foi cortado: tenta de novo, em vez de esperar o prazo inteiro.
---
---⚑ A BLIZZARD DESCOBRE ISSO ASSIM, e nós não descobríamos: a janela nativa escuta
---`UNIT_SPELLCAST_FAILED/INTERRUPTED` filtrando pelo predicado da magia
---(`Blizzard_ClassSpecializationsFrame.lua:69-70,185-190`), porque
---`SPECIALIZATION_CHANGE_CAST_FAILED` **não é consumido por nenhum arquivo da UI 12.1.0**. Sem
---isto, andar durante a troca custava os 45 segundos do prazo e terminava com "o jogo não
---confirmou a tempo" — o erro mais caro da lista, porque o jogador não fez nada de errado.
local function SpecCastCut(event)
    running.specCastCuts = (running.specCastCuts or 0) + 1
    if ns.Log then
        ns.Log.Add("cast cortado", {
            passo = "spec", evento = event, vez = running.specCastCuts,
        })
    end

    if running.specCastCuts > SPEC_CAST_CUT_MAX then
        if running.progress then running.progress.spec = "failed" end
        running.failures = running.failures or {}
        running.failures[#running.failures + 1] = L["the specialization change failed."]
        -- O DESFECHO TAMBÉM VAI PARA O DIÁRIO. O evento já ia; o que o passo fez com ele, não.
        if ns.Log then ns.Log.Step("spec", "fail", L["the specialization change failed."]) end
        RunNext()
        return
    end

    Report(L["Switching specialization..."], false)
    RerunStep("spec")
end

---Fecha o passo de talentos quando a gravação termina, e diz no diário QUAL sinal fechou e em
---quanto tempo. É esse registro que confere a janela do eco com dado de verdade.
local function CloseTalentCommit(por, commit)
    if ns.Log then
        ns.Log.Add("gravou", {
            passo = "talent", por = por,
            segundos = commit and format("%.1f", GetTime() - commit.since) or nil,
        })
    end
    running.commit = nil
    ConfirmTalent()
    RunNext()
end

function Data.EnsureListener()
    if listener then return listener end

    listener = CreateFrame("Frame", ADDON .. "ApplyListener")
    listener:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    listener:RegisterEvent("SPECIALIZATION_CHANGE_CAST_FAILED")
    listener:RegisterEvent("TRAIT_CONFIG_UPDATED")
    listener:RegisterEvent("CONFIG_COMMIT_FAILED")
    listener:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    listener:RegisterEvent("UNIT_SPELLCAST_STOP")
    listener:RegisterEvent("UNIT_SPELLCAST_FAILED")
    listener:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    listener:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
    listener:RegisterEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
    -- A CORRENTE MORRE NO `/reload` E NO LOGOUT, e morria calada: `running` é memória, o `Finish`
    -- não roda, e o diário terminava no último passo sem dizer que foi interrompido. Quem lê
    -- depois não distingue "ficou pela metade" de "o addon travou".
    listener:RegisterEvent("PLAYER_LEAVING_WORLD")
    listener:RegisterEvent("PLAYER_LOGOUT")

    listener:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
        -- REGISTRA ANTES DE DECIDIR, inclusive o evento que chega sem corrente em curso. É o que
        -- responde a hipótese que eu não tinha como testar: estes eventos são GLOBAIS e disparam
        -- quando o JOGADOR mexe à mão ou quando outro addon mexe. Se o log mostrar um evento
        -- fechando um passo que não era nosso, é isso.
        -- OS DOIS ARGUMENTOS. `EQUIPMENT_SWAP_FINISHED` traz `result, setID`, e sem o segundo
        -- não dá para saber se o evento era do nosso conjunto — foi exatamente a pergunta que
        -- ficou sem resposta ao ler o diário de 02:05.
        local emCurso = running and running.steps[running.at] or nil
        if CAST_EVENTS[event] then
            -- O CAST SÓ INTERESSA COM CORRENTE EM CURSO, e só o do jogador. Ele dispara a cada
            -- magia de qualquer unidade: registrar tudo varreria o diário de 400 linhas em minutos
            -- de jogo. Com corrente, grava o `spellID` — é ele que diz, na próxima troca real, se
            -- o fim do cast de gravação chegou e em que ordem com o `TRAIT_CONFIG_UPDATED`.
            if not running or arg1 ~= "player" then return end
            if ns.Log then ns.Log.Event(event, emCurso, true, arg3) end
        elseif ns.Log then
            ns.Log.Event(event, emCurso, running ~= nil, arg1, arg2)
        end

        -- A INTERRUPÇÃO GANHA LINHA, e ela é gravada mesmo sem corrente em curso não — só com.
        -- `PLAYER_LOGOUT` é o último instante em que dá para escrever em SavedVariables, então
        -- esta linha é a única chance de o arquivo dizer que a troca ficou pela metade.
        if event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then
            if running and ns.Log then
                ns.Log.Add("interrompido", {
                    passo = emCurso or "nenhum", motivo = event,
                    conjunto = running.preset and running.preset.name or "?",
                })
            end
            return
        end

        if not running then return end
        local step = running.steps[running.at]

        -- TODOS OS RAMOS CONFEREM O PASSO EM CURSO, e este não conferia. Qualquer cast de troca
        -- de spec que falhasse — o clique do próprio jogador na janela de talentos, outro addon —
        -- matava a corrente de onde ela estivesse. E `Finish` virou anotação: falhar a spec não
        -- deve impedir os itens de entrar.
        if event == "SPECIALIZATION_CHANGE_CAST_FAILED" and step == "spec" then
            -- TENTA DE NOVO EM VEZ DE ANOTAR FALHA. A semântica deste evento não está em lugar
            -- nenhum da fonte da Blizzard (ninguém o consome, e ele não tem carga útil), mas a
            -- família é a mesma das outras recusas deste addon: transitória. O teto de `SpecCastCut`
            -- é que decide quando parar de insistir.
            SpecCastCut(event)

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
            --
            -- ⚑ O DADO CHEGOU (11/09), E DESFAZ METADE DA RETIRADA. Os eventos que fechavam o
            -- passo eram o ECO da troca de spec, com o mesmo id do verdadeiro — ver
            -- `COMMIT_ECHO_WINDOW`. Aceitar qualquer um pedia os itens com a gravação em curso, e
            -- o jogo recusava: três vezes em três.
            --
            -- A regra agora é a da própria Blizzard — o evento só confirma o commit que ela mesma
            -- abriu (`Blizzard_SharedTalentFrame.lua:358`) —, mais a janela do eco:
            --   - SEM `running.commit`, o passo está na INSISTÊNCIA (`Error` sem motivo): o jogo
            --     recusou o `LoadConfig`, e o evento que chega é eco. As três correntes do diário
            --     que fecharam assim (15:51:07, 21:59:36, 00:00:26) anunciaram "pronto" sem nada
            --     que prove que os talentos entraram — e o `ConfirmTalent` ainda marcava o loadout
            --     como selecionado. Agora a insistência segue e pergunta de novo;
            --   - COM `running.commit`, o evento só vale depois da janela.
            local commit = running.commit
            if commit and (GetTime() - commit.since) >= COMMIT_ECHO_WINDOW then
                CloseTalentCommit("evento", commit)
            end

        elseif event == "UNIT_SPELLCAST_SUCCEEDED" and step == "talent" then
            -- O FIM DO CAST DE GRAVAÇÃO, o sinal que a janela de talentos do jogo usa
            -- (`Blizzard_ClassTalentsFrame.lua:345-350`). `issecretvalue` ANTES do `==`: o
            -- `spellID` deste evento vem opaco sob restrição (`UnitDocumentation.lua:4702`), e
            -- comparar valor opaco é erro.
            if running.commit and not (issecretvalue and issecretvalue(arg3))
                and arg3 == COMMIT_SPELL_ID then
                CloseTalentCommit("cast", running.commit)
            end

        elseif event == "CONFIG_COMMIT_FAILED" and step == "talent" then
            -- A GRAVAÇÃO FALHOU — e a Blizzard encerra o commit dela no mesmo evento
            -- (`Blizzard_SharedTalentFrame.lua:346-349`). Sem este ramo, a falha só seria
            -- percebida pelo prazo do passo. Marca "failed" ANTES do `RunNext`, pela mesma razão
            -- do prazo em `Arm`: senão ele promove o passo a "done".
            if running.commit then
                running.commit = nil
                if running.progress then running.progress.talent = "failed" end
                running.failures = running.failures or {}
                running.failures[#running.failures + 1] = L["the talent loadout could not be loaded."]
                -- O DESFECHO NO DIÁRIO, e não só o evento: era uma das lacunas do mapa.
                if ns.Log then
                    ns.Log.Step("talent", "fail", L["the talent loadout could not be loaded."])
                end
                RunNext()
            end

        elseif CAST_EVENTS[event] and event ~= "UNIT_SPELLCAST_SUCCEEDED" and step == "spec"
            and IsSpecCast(arg3) then
            -- O CAST DE TROCA DE SPEC FOI CORTADO (andar corta, e é o caso do `Core.lua:201-202`).
            SpecCastCut(event)

        elseif CAST_EVENTS[event] and event ~= "UNIT_SPELLCAST_SUCCEEDED" and step == "gear" then
            -- O CAST ACABOU, ou foi cortado — é agora que `UnitCastingInfo` deixa de responder
            -- (`CastingBarFrame.lua:459,482-483`). SUCCEEDED fica de fora de propósito: é ele que
            -- chega com o cast ainda constando, e foi exatamente ele que derrubou os itens.
            if running.gearWaitsCast then
                running.gearWaitsCast = nil
                RerunStep("gear")
            end

        elseif event == "TRANSMOG_DISPLAYED_OUTFIT_CHANGED" and step == "transmog" then
            -- O EVENTO NÃO DIZ QUAL conjunto entrou — não tem carga útil
            -- (`TransmogOutfitInfoDocumentation.lua:818-821`). Então ele é o sinal de que
            -- ALGO mudou, e quem responde "mudou para o certo?" continua sendo a leitura.
            --
            -- E se mudou para o ERRADO, isso não é falha a repetir: é o jogador tendo trocado a
            -- aparência à mão no meio da aplicação. O relatório diz o que houve e a corrente
            -- segue, como em todo passo que não deu.
            local ativa = Data.GetActiveOutfitID()
            if ativa ~= running.preset.transmog then
                local porque = Data.TransmogBlockedBy(running.preset.transmog)
                -- ⚑ AS TRÊS COISAS QUE FALTAVAM NO DIÁRIO. O evento não tem carga útil, e nós só
                -- gravávamos a nossa conclusão: lendo depois não dava para separar "o jogador
                -- trocou a roupa à mão" de "uma porta do jogo estava fechada".
                if ns.Log then
                    ns.Log.Call("transmog", "divergiu",
                        "ativa=" .. tostring(ativa),
                        "desejada=" .. tostring(running.preset.transmog),
                        porque or "nenhuma porta fechada")
                end
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
                -- ⚑ E AQUI SE PERGUNTA POR QUÊ, no único instante em que a resposta existe.
                --
                -- O diário de 09/09 registrou esta recusa (17:22:02, conjunto 1) e não tinha como
                -- explicá-la: a mesma corrente, com o mesmo conjunto, tinha funcionado às
                -- 00:00:26. Sem a contabilidade do conjunto no momento da recusa, as duas linhas
                -- do diário são indistinguíveis — e a próxima rodada recomeçaria a adivinhação.
                if ns.Log then
                    ns.Log.Call("gear", "recusou; estado de " .. tostring(running.preset.gear),
                        Data.DescribeGearSet(running.preset.gear) or "sem resposta")
                end

                running.failures = running.failures or {}
                running.failures[#running.failures + 1] =
                    Data.GearFailureReason(running.preset.gear)
            end
            RunNext()
        end
    end)

    return listener
end

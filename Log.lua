-- RocketSwap | Log.lua
-- Diário da corrente de aplicação, gravado em SavedVariables.
--
-- POR QUE ELE EXISTE. Pergunta literal do usuário depois de a troca falhar de novo: *"tu tá
-- salvando logs para poder entender os problemas?"*. A resposta era **não** — e por isso as três
-- rodadas anteriores foram eu adivinhando qual passo tinha falhado e ele me contando por escrito.
--
-- Addon não escreve arquivo arbitrário, mas SavedVariables vira um `.lua` legível em
--   WTF\Account\<conta>\SavedVariables\RocketSwap.lua
-- que se lê de fora do jogo. É como o que aconteceu chega até aqui sem passar pela memória de
-- ninguém. O padrão é o do `RocketMeter/Log.lua`, que o `CLAUDE.md` manda reaproveitar.
--
-- O QUE ELE PRECISA RESPONDER, lendo o arquivo e nada mais: *por que não trocou?* Isso exige, em
-- cada passo, três coisas — o que o addon PEDIU, o que o jogo RESPONDEU, e como o passo FECHOU.
-- Sem as três não dá para distinguir "o jogo recusou" de "o addon nem pediu" de "o jogo aceitou e
-- não fez", que são exatamente as três hipóteses que já custaram uma rodada cada.
--
-- REGRA DE OURO, herdada do medidor: nunca guardar secret value aqui. Guarda-se **fato sobre** o
-- dado, nunca o dado cru.
local ADDON, ns = ...

local Log = {}
ns.Log = Log

-- Uma corrida gera ~12 linhas (início, 4 passos × pedido/resposta, eventos, fim). 400 guarda
-- umas trinta trocas, que é bastante para o usuário reproduzir sem o arquivo virar um monstro.
local MAX_ENTRIES = 400

local function Store()
    RocketSwapLogDB = RocketSwapLogDB or { entries = {} }
    RocketSwapLogDB.entries = RocketSwapLogDB.entries or {}
    return RocketSwapLogDB
end

---Descreve um valor sem nunca guardá-lo cru.
---
---`issecretvalue` vem ANTES do `type`: para um valor opaco `type()` responde o tipo real, então
---testar só o tipo deixaria o `tostring` receber um secret.
local function Describe(value)
    if value == nil then return "nil" end
    if issecretvalue(value) then return "SECRET" end
    local t = type(value)
    if t == "number" or t == "string" or t == "boolean" then return tostring(value) end
    return t
end

---Grava uma linha.
---@param event string o que aconteceu, em uma palavra ("pediu", "respondeu", "evento", "fim")
---@param data table|nil os campos daquele momento
function Log.Add(event, data)
    local entries = Store().entries

    entries[#entries + 1] = {
        time = date("%H:%M:%S"),
        event = event,
        combat = InCombatLockdown() and true or false,
        data = data,
    }

    -- Anel: mantém só as últimas, para o arquivo não crescer sem limite.
    while #entries > MAX_ENTRIES do
        tremove(entries, 1)
    end
end

--------------------------------------------------------------------------------
-- Os pontos da corrente
--------------------------------------------------------------------------------
---O retrato do que o jogador tem AGORA, contra o que o conjunto pede.
---
---Esta é a linha mais importante do arquivo: com ela dá para ver que a troca nem precisava
---acontecer, ou que ela pedia algo que não existe mais — dois casos que já apareceram e que o
---chat não mostrava.
function Log.Apply(preset, byClick)
    local specIndex = ns.Data.GetCurrentSpecIndex()
    local spec = ns.Data.GetSpecByIndex(specIndex)

    Log.Add("aplicar", {
        preset = preset and preset.name or "?",
        peloClique = byClick and true or false,

        querSpec = Describe(preset and preset.spec),
        temSpec = Describe(specIndex),

        querTalento = Describe(preset and preset.talent),
        temTalento = Describe(spec and ns.Data.GetActiveLoadoutID(spec.id)),

        querItens = Describe(preset and preset.gear),
        temItens = Describe(ns.Data.GetEquippedSetID()),

        querAparencia = Describe(preset and preset.transmog),
        temAparencia = Describe(ns.Data.GetActiveOutfitID()),
    })
end

---O passo começou, e o que ele decidiu fazer.
function Log.Step(step, outcome, message)
    Log.Add("passo", {
        passo = step,
        resultado = outcome,                       -- skip | wait | fail
        motivo = message and tostring(message) or nil,
    })
end

---O jogo respondeu alguma coisa a uma chamada nossa.
---
---`chamada` e `retorno` juntos são o que separa "o jogo recusou" de "o addon nem pediu".
function Log.Call(step, call, ...)
    local retornos = {}
    for i = 1, select("#", ...) do
        retornos[i] = Describe((select(i, ...)))
    end

    Log.Add("chamada", {
        passo = step,
        chamada = call,
        retorno = #retornos > 0 and table.concat(retornos, ", ") or "nada",
    })
end

---Um evento chegou. `paraNos` diz se ele fechou o passo em curso ou foi ignorado.
---
---Isto responde a hipótese que eu não tinha como testar: eventos como `TRAIT_CONFIG_UPDATED`
---são GLOBAIS e disparam quando o jogador mexe à mão ou quando outro addon mexe. Se o log
---mostrar um evento fechando um passo que não era o nosso, é isso.
function Log.Event(event, step, paraNos, arg1, arg2)
    Log.Add("evento", {
        evento = event,
        passoEmCurso = step or "nenhum",
        paraNos = paraNos and true or false,
        arg1 = arg1 ~= nil and Describe(arg1) or nil,
        -- `EQUIPMENT_SWAP_FINISHED` traz `result, setID`; sem o segundo nao da para saber se o
        -- evento era do NOSSO conjunto -- foi a pergunta que ficou sem resposta ao ler o diario.
        arg2 = arg2 ~= nil and Describe(arg2) or nil,
    })
end

---A corrente terminou.
function Log.Finish(ok, message, failures)
    Log.Add("fim", {
        ok = ok and true or false,
        mensagem = message and tostring(message) or nil,
        falhas = failures and table.concat(failures, " | ") or nil,
    })
end

--------------------------------------------------------------------------------
function Log.Clear()
    RocketSwapLogDB = { entries = {} }
end

function Log.Count()
    return #Store().entries
end

---As últimas linhas, para o chat. Ler no jogo cobre o caso simples sem precisar de `/reload`.
function Log.Tail(howMany)
    local entries = Store().entries
    local out = {}
    for i = math.max(1, #entries - (howMany or 12) + 1), #entries do
        local e = entries[i]
        local parts = {}
        for k, v in pairs(e.data or {}) do
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
        table.sort(parts)
        out[#out + 1] = ("%s  %-9s %s"):format(e.time, e.event, table.concat(parts, "  "))
    end
    return out
end

function Log.Init()
    local store = Store()
    store.version = ns.version
    store.locale = GetLocale()
    store.started = date("%Y-%m-%d %H:%M:%S")
end

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

local L = ns.L

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
--------------------------------------------------------------------------------
-- Erros inesperados
--------------------------------------------------------------------------------
-- ⚑ O DIÁRIO SÓ SABIA O QUE A GENTE MANDOU ELE ANOTAR. Erro de Lua ficava fora dele — quem
-- guardava era o !BugGrabber, addon de terceiro, num arquivo de 534 KB com os erros de todo
-- mundo. Em 09/09/2026 isso custou caro nos dois lados: um `for candidate = 0, 3` no diagnóstico
-- do medidor levantava **uma vez por combate**, 1628 vezes acumuladas, e ninguém tinha visto.
--
-- Agora cada addon guarda os erros DELE, no diário dele, junto do que estava acontecendo.
--
-- ⚑ E SÃO DOIS CAMINHOS, NÃO UM, porque o `!BugGrabber` **desliga o `seterrorhandler`**:
-- `real_seterrorhandler(grabError)` e logo abaixo `function seterrorhandler() end`
-- (`!BugGrabber/BugGrabber.lua:573-574`). Instalar um handler com ele presente é uma chamada que
-- não faz nada e não avisa — a captura pareceria ligada e o arquivo sairia vazio para sempre.
--
--   1. com !BugGrabber: assina `BugGrabber.BugGrabbed` no `EventRegistry` e copia o que é nosso.
--      É o caminho melhor: ele já traz pilha e locais prontos;
--   2. sem ele: encadeia no handler que estiver valendo — e **confere que pegou**, comparando
--      `geterrorhandler()` com o nosso. Sem essa conferência o caso 1 passaria despercebido.
--
-- `store.captura` grava qual dos dois valeu. Isso não é enfeite: sem esse campo, "o arquivo não
-- tem erro nenhum" é ambíguo entre *não houve erro* e *não estávamos capturando*.
local MAX_ERROS = 40

local capturaInstalada = false

---Só os quadros DESTE addon, e no máximo seis.
---
---A pilha inteira do jogo tem trinta linhas de `FrameXML` que não dizem nada sobre o nosso
---defeito; o que interessa é onde ELE está. Se nenhuma linha for nossa, devolve `nil` — e é assim
---que o filtro decide que o erro é de outro addon.
local function NossosQuadros(stack)
    if type(stack) ~= "string" then return nil end

    local linhas, achou = {}, false
    for linha in stack:gmatch("[^\r\n]+") do
        if linha:find("AddOns\\" .. ADDON, 1, true) or linha:find("AddOns/" .. ADDON, 1, true) then
            achou = true
            if #linhas < 6 then
                linhas[#linhas + 1] = (linha:gsub("^%s+", ""))
            end
        end
    end

    if not achou then return nil end
    return table.concat(linhas, " <- ")
end

---Grava um erro nosso. Repetição vira contagem, não linha nova.
---
---⚑ A CONTAGEM É O PONTO. O caso que motivou isto repetiu 1628 vezes; sem agrupar, o anel de 300
---linhas seria varrido pelo mesmo erro e apagaria justamente o contexto que explica ele.
local function RegistrarErro(mensagem, stack)
    if type(mensagem) ~= "string" then return end

    local nossos = NossosQuadros(stack)
    -- A mensagem também identifica: `Window.lua:882: ...` já diz de quem é, mesmo sem pilha.
    local pelaMensagem = mensagem:find("AddOns\\" .. ADDON, 1, true)
        or mensagem:find("AddOns/" .. ADDON, 1, true)
    if not nossos and not pelaMensagem then return end

    local store = Store()
    store.erros = store.erros or {}

    for _, e in ipairs(store.erros) do
        if e.mensagem == mensagem then
            e.vezes = (e.vezes or 1) + 1
            e.ultima = date("%Y-%m-%d %H:%M:%S")
            return
        end
    end

    store.erros[#store.erros + 1] = {
        mensagem = mensagem,
        pilha = nossos,
        vezes = 1,
        primeira = date("%Y-%m-%d %H:%M:%S"),
        ultima = date("%Y-%m-%d %H:%M:%S"),
        versao = ns.version,
        combate = InCombatLockdown() and true or false,
        -- ONDE A CORRENTE ESTAVA. Um erro sozinho diz o quê; com a última linha do diário ao lado,
        -- diz também o quando — e foi o "quando" que respondeu as duas investigações de 09/09.
        depoisDe = (function()
            local ultimo = Store().entries[#Store().entries]
            return ultimo and (ultimo.time .. " " .. tostring(ultimo.event)) or nil
        end)(),
    }

    while #store.erros > MAX_ERROS do tremove(store.erros, 1) end
end

---Liga a captura. Idempotente: chamar de novo não instala dois handlers.
---@return string qual caminho valeu ("buggrabber", "handler" ou "nenhuma")
function Log.CaptureErrors()
    if capturaInstalada then return Store().captura or "nenhuma" end
    capturaInstalada = true

    local store = Store()

    -- CAMINHO 1: o !BugGrabber já capturou tudo; a gente só copia o que é nosso.
    if BugGrabber and BugGrabber.GetErrorByID and EventRegistry then
        EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", function(_, tableID)
            -- `pcall` porque isto roda DENTRO do tratamento de um erro: estourar aqui é como se
            -- perde o erro original, e o jogador vê um defeito nosso no lugar do defeito real.
            pcall(function()
                local erro = BugGrabber:GetErrorByID(tableID)
                if erro then RegistrarErro(erro.message, erro.stack) end
            end)
        end, Log)
        store.captura = "buggrabber"
        return store.captura
    end

    -- CAMINHO 2: encadeia no handler que estiver valendo.
    if type(seterrorhandler) == "function" then
        local anterior = type(geterrorhandler) == "function" and geterrorhandler() or nil
        local meu
        meu = function(mensagem, ...)
            pcall(RegistrarErro, mensagem, debugstack and debugstack(2) or nil)
            if anterior then return anterior(mensagem, ...) end
        end

        seterrorhandler(meu)

        -- ⚑ CONFERE QUE PEGOU. Ver a nota do topo: com o !BugGrabber presente esta chamada é um
        -- `function() end`, e sem esta linha a captura se declararia ligada estando desligada.
        if type(geterrorhandler) == "function" and geterrorhandler() == meu then
            store.captura = "handler"
            return store.captura
        end
    end

    store.captura = "nenhuma"
    return store.captura
end

---Esquece que a captura foi instalada, para o harness poder exercitar os TRÊS mundos
---(com !BugGrabber, sem ele, e com o `seterrorhandler` neutralizado sem ele).
---
---Gancho de teste declarado, no estilo do `Picker.__probe` — e ele existe por necessidade: a
---escolha do caminho acontece UMA vez, no carregamento, e sem poder desfazê-la o harness só
---conseguiria testar o mundo em que ele mesmo carregou.
function Log.__resetCapture()
    capturaInstalada = false
    Store().captura = nil
end

---Quantos erros distintos estão guardados, e quantas ocorrências no total.
function Log.ErrorCount()
    local distintos, total = 0, 0
    for _, e in ipairs(Store().erros or {}) do
        distintos = distintos + 1
        total = total + (e.vezes or 1)
    end
    return distintos, total
end

---O resumo dos erros no chat. Responde "aconteceu alguma coisa?" sem `/reload` e sem sair do
---jogo — que é o que o arquivo exige, porque SavedVariables só é escrito no logout.
---
---⚑ E ELE DIZ SE ESTÁ CAPTURANDO. "Nenhum erro" e "não estou olhando" são estados diferentes e
---parecem iguais no silêncio; sem esta linha, o segundo passaria por bom notícia.
function ns.PrintErrorSummary()
    local distintos, total = Log.ErrorCount()
    local modo = Store().captura or "nenhuma"

    if modo == "nenhuma" then
        ns.Print(L["errors are NOT being captured on this client."])
        return
    end

    if distintos == 0 then
        ns.Print(format(L["no error captured (capture: %s)."], modo))
        return
    end

    ns.Print(format(L["%d error(s) captured, %d occurrence(s):"], distintos, total))
    for _, e in ipairs(Store().erros or {}) do
        print(format("  |cffff5555x%d|r %s", e.vezes or 1, e.mensagem))
        if e.pilha then print("      " .. e.pilha) end
    end
end

function Log.ClearErrors()
    Store().erros = {}
end

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

    -- A captura entra AQUI, e não no `PLAYER_LOGIN`: erro que acontece durante a
    -- carga do addon é justamente o que ninguém vê passar.
    Log.CaptureErrors()
end

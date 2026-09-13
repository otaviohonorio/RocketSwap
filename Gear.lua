-- RocketSwap | Gear.lua
-- Descobre, peça por peça, se o que você está vestindo é de PvP ou de PvE.
--
-- NÃO EXISTE API QUE RESPONDA ISSO. Nem `C_Item`, nem `C_PaperDollInfo`, nem `C_PvP`. O único
-- sinal por peça é uma LINHA DE TOOLTIP, cujo texto vem da global `PVP_ITEM_LEVEL_TOOLTIP`:
--
--   enUS  "Equip: Increases item level to a minimum of %d in Arenas, Battlegrounds, and War Mode."
--   ptBR  "Equipar: aumenta o nível do item para um mínimo de %d em Arenas, Campos de Batalha
--          e no Modo de Guerra."
--
-- Quatro decisões aqui vieram de erros que outros addons cometeram e que estão em disco:
--
--   1. LER PELO SLOT, NÃO PELO LINK. `C_TooltipInfo.GetInventoryItem("player", slot)` em vez de
--      `GetHyperlink(link)`. Todos os getters de `C_TooltipInfo` têm
--      `SecretArguments = "AllowedWhenUntainted"`: passar um link SECRET a partir de código de
--      addon **levanta erro**, não devolve nil. E link de item não é categoricamente não-secret
--      no 12.x — um addon instalado blinda contra isso (`AlterEgo/Data.lua:1148,1255`). Os
--      contextos onde isso morderia são justamente arena, encontro e M+, que é onde este
--      recurso trabalha.
--
--   2. PADRÃO SEM ÂNCORA. O `fmtToPattern` do EnhanceQoL devolve `"^" .. pat .. "$"`
--      (`General/functions.lua:2745`) e por isso **não casa** quando a linha vem embrulhada em
--      código de cor (`|cffffffff...|r`). Reproduzido em LuaJIT: com âncora dá miss, sem
--      âncora dá match nos dois casos.
--
--   3. NÃO FILTRAR POR `line.type`. O enum `TooltipDataLineType` tem 50 valores e **nenhum é
--      de PvP**. O próprio Syndicator trata `row.type` como possivelmente nil
--      (`CheckItem.lua:551`).
--
--   4. TRÊS ESTADOS, NÃO DOIS. `true` (é de PvP), `false` (não é), `nil` (**não sei**). Em
--      coreano a string traz uma diretiva gramatical (`%d|1으로;로;`) que nenhum padrão
--      derivado casa — ali "não achei a linha" NÃO significa "não é peça de PvP". Um addon
--      que confunde os dois grita em 16 slots de uma vez.
local ADDON, ns = ...

local Gear = {}
ns.Gear = Gear

-- Os slots que valem. `INVSLOT_FIRST_EQUIPPED..LAST` é 1..19 e inclui camisa (4) e tabardo
-- (19), que não têm atributo nem versão de PvP — avisar sobre eles seria avisar sobre peça
-- que não existe. A Blizzard não expõe uma tabela dos 16 úteis; esta é nossa.
local SLOTS = {
    1,  2,  3,      -- cabeça, pescoço, ombros
    5,  6,  7,  8,  -- peito, cintura, pernas, pés
    9,  10, 11, 12, -- pulsos, mãos, anel 1, anel 2
    13, 14,         -- berloque 1, berloque 2
    15,             -- costas
    16, 17,         -- mão principal, mão secundária
}

Gear.SLOTS = SLOTS

--------------------------------------------------------------------------------
---Monta o padrão a partir da global, sem âncora.
---
---Escapa os mágicos, troca `%d` por `%d+` e `%s` por `.+`, e transforma a **diretiva
---gramatical** (`|1forma1;forma2;`) em coringa.
---
---⚑ O COMENTÁRIO E O CÓDIGO SE CONTRADIZIAM AQUI, e o comentário é que estava certo: ele dizia
---"a diretiva vira coringa" e o código a **removia**.
---
---O ALCANCE, MEDIDO — e é menor do que parece à primeira vista, então vale registrar o número em
---vez da impressão. Remover só quebra quando a diretiva está no **meio** da string; quando está
---no fim, o casamento não é ancorado e o prefixo já basta:
---
---     global                      remover   coringa
---     diretiva no FIM             casa      casa
---     diretiva no MEIO            NÃO casa  casa
---
---A forma coreana conhecida (`PvP 장비 레벨 %d|1으로;로;`) tem a diretiva no fim — ou seja, o
---defeito **não** estava quebrando o cliente coreano hoje. O que estava errado era a regra: a
---diretiva não é texto literal, e apagá-la só funcionava por acidente de posição.
local function BuildPattern(text)
    if type(text) ~= "string" or text == "" then return nil end

    -- A diretiva vira coringa: o que vem depois do número muda COM o número, então não dá para
    -- fixar uma das formas nem para apagar as duas.
    local clean = text:gsub("|%d+[^;]*;[^;]*;", "\1")

    local pattern = clean:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    pattern = pattern:gsub("%%%%d", "%%d+")
    pattern = pattern:gsub("%%%%s", ".+")
    pattern = pattern:gsub("\1", ".-")
    return pattern
end

local pvpPattern

local function Pattern()
    if pvpPattern == nil then
        pvpPattern = BuildPattern(PVP_ITEM_LEVEL_TOOLTIP) or false
    end
    return pvpPattern or nil
end

---O padrão, para o despejo de `/rs gear <slot>` poder dizer QUAL linha casa.
---
---`Debug` no nome porque produção não usa: quem decide é `IsPvPItem`. É a mesma regra que já
---governa os outros ganchos deste projeto — código que sobrevive ao único consumidor vira
---armadilha para a próxima leitura.
function Gear.DebugPattern()
    return Pattern()
end

---Esquece o padrao e o autoteste dele.
---
---Existe para o teste poder trocar a global do jogo e conferir o comportamento em outro idioma:
---o padrao e memorizado na primeira leitura, entao sem isto o segundo idioma nunca seria montado.
---In-game nada chama isto -- a global nao muda no meio da sessao.
function Gear.__ResetPattern()
    pvpPattern = nil
    Gear.__patternWorksReset()
end

--------------------------------------------------------------------------------
-- Cache por link. A leitura de tooltip é cara demais para rodar a cada evento.
--
-- O EnhanceQoL tem um bug aqui que não vamos copiar: ele guarda `{nil, nil}` quando a tooltip
-- volta vazia e depois faz `if cached then return cached[1], cached[2] end` — a tabela é
-- truthy, então o falso negativo fica gravado para sempre (`ItemInventory.lua:1477-1504`).
-- Aqui, resultado desconhecido **não entra no cache**.
local cache = {}

function Gear.ClearCache()
    cache = {}
end

---A deteccao esta viva neste cliente?
---
---`Pattern()` sai de uma global do jogo (`PVP_ITEM_LEVEL_TOOLTIP`). Se ela nao existir ou nao
---render padrao, TODA peca volta `nil` e o addon cala pelos dois lados -- sem erro, sem log,
---sem nada a que se agarrar. Perguntar isso e a primeira coisa que um diagnostico faz.
function Gear.PatternReady()
    return Pattern() ~= nil
end

---O padrão CASA com a linha que ele foi feito para achar?
---
---⚑ ESTE É O SINAL QUE FALTAVA, e ele é o que permite desarmar a comporta `LooksReliable` sem
---transformar o addon num gritador.
---
---O problema que ela tentava resolver é real e é assimétrico. Um `true` só nasce de
---`text:match(pattern)`; nenhum modo de falha de leitura sabe fabricar um `true` — só um
---`false`. Logo:
---
---  * em PvE, "todas erradas" = 16 casamentos genuínos. Nunca é ambíguo.
---  * em PvP, "todas erradas" = nenhum casamento — que é **exatamente** o que a falha produz.
---
---Por isso a comporta só mordia de um lado, e mordia justamente o caso comum: quem entra numa
---arena vindo do PvE está com o equipamento inteiro de PvE.
---
---A saída é não perguntar ao equipamento, e sim **ao próprio padrão**: montar uma linha
---sintética a partir da mesma global de onde ele saiu e ver se ele a encontra. Se encontra, a
---detecção está provada e "todas erradas" é leitura, não falha. Se não encontra, o padrão está
---quebrado neste cliente e o silêncio continua sendo a resposta certa.
---
---Não depende de o jogador possuir uma peça de PvP sequer — que é o furo de qualquer heurística
---baseada no que ele está vestindo.
local patternWorks

function Gear.__patternWorksReset()
    patternWorks = nil
end

function Gear.PatternWorks()
    if patternWorks ~= nil then return patternWorks end

    local pattern = Pattern()
    if not pattern then
        patternWorks = false
        return false
    end

    -- A LINHA SINTÉTICA sai da mesma global, com um número no lugar do `%d`. É o mesmo texto que
    -- o jogo escreve na tooltip, montado por `format` em vez de lido de um item.
    local ok, linha = pcall(format, PVP_ITEM_LEVEL_TOOLTIP, 684)
    if not ok or type(linha) ~= "string" then
        patternWorks = false
        return false
    end

    -- A diretiva gramatical não passa por `format`: ela é resolvida pelo cliente ao desenhar.
    -- Aqui ela vira o texto cru, e o coringa do padrão é justamente o que a atravessa.
    patternWorks = linha:match(pattern) ~= nil
    return patternWorks
end

---Esta peça é de PvP?
---@return boolean|nil  true = é, false = não é, nil = não deu para saber
function Gear.IsPvPItem(slot)
    local link = GetInventoryItemLink("player", slot)
    if link == nil or issecretvalue(link) then return nil end

    local hit = cache[link]
    if hit ~= nil then return hit end

    local pattern = Pattern()
    if not pattern then return nil end

    if not C_TooltipInfo or not C_TooltipInfo.GetInventoryItem then return nil end

    -- Pelo SLOT, e dentro de pcall: ver a decisão 1 no topo do arquivo.
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    if #data.lines == 0 then return nil end

    local found = false
    for _, line in ipairs(data.lines) do
        -- O Syndicator não guarda `leftText` contra nil (`CheckItem.lua:903`) e por isso tem um
        -- erro latente. Guardamos.
        local text = line.leftText
        if text ~= nil and not issecretvalue(text) and type(text) == "string" then
            if text:match(pattern) then
                found = true
                break
            end
        end
    end

    cache[link] = found
    return found
end

--------------------------------------------------------------------------------
---Varre o equipamento e devolve o que está fora do lugar.
---
---@param wantPvP boolean true = estamos em PvP (peça sem a linha é erro);
---                       false = estamos em PvE (peça com a linha é erro)
---@param ignored table|nil slots que o usuário mandou calar
---@return table erros  lista de { slot = n, link = "..." }
---@return number lidos  quantos slots deram resposta (nem nil, nem vazios)
---@return number vestidos quantos slots têm peça
function Gear.Wrong(wantPvP, ignored)
    local wrong, read, worn = {}, 0, 0

    for _, slot in ipairs(SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link ~= nil and not issecretvalue(link) then
            worn = worn + 1

            local isPvP = Gear.IsPvPItem(slot)
            if isPvP ~= nil then
                read = read + 1
                -- Desconhecido nunca conta como errado: é a diferença entre um lembrete e
                -- um addon que grita quando a leitura falha.
                if isPvP ~= wantPvP and not (ignored and ignored[slot]) then
                    wrong[#wrong + 1] = { slot = slot, link = link }
                end
            end
        end
    end

    return wrong, read, worn
end

---A leitura é confiável nesta varredura?
---
---⚑ ESTA COMPORTA CALAVA O CASO MAIS COMUM DO PvP. Relato do usuário, 08/09/2026: *"o de pve no
---pvp, ainda não vi funcionar, quando dou fila em BG, arena, ele não avisa nada sobre meus
---itens"*.
---
---A regra antiga era `#wrong < read`: se TODOS os slots lidos deram errado, presumia falha de
---detecção. Medido varrendo de 0 a 16 peças de PvP, ela cala **exatamente uma** das 17
---configurações de cada lado — e no lado do PvP essa uma é `n = 0`, equipamento de PvE inteiro,
---que é precisamente quem entra numa arena vindo do PvE. Não era um filtro de ruído: era um
---recorte em cima do caso comum.
---
---A ambiguidade que ela tentava resolver é real, mas só existe de um lado (ver
---`Gear.PatternWorks`, que explica por quê). E ela se desfaz sem perguntar ao equipamento:
---**o padrão testa a si mesmo**. Se ele acha a linha que foi feito para achar, "todas erradas" é
---leitura boa; se não acha, o silêncio continua certo.
---
---O que NÃO é coberto, e vale registrar em vez de fingir: tooltip **não carregada** também
---produz `false` em todo slot, e uma tooltip parcial tem linhas (só não a de PvP), então passa
---pela guarda de `#data.lines == 0` e conta como leitura. A mitigação é a que já existe —
---resultado desconhecido não entra no cache — mais o fato de a checagem se repetir em vários
---eventos. Uma janela no login segue possível.
function Gear.LooksReliable(wrong, read)
    if read < 3 then return false end
    if #wrong < read then return true end

    -- TODAS ERRADAS: só é leitura de verdade se a detecção provar que sabe achar a linha.
    return Gear.PatternWorks()
end

--------------------------------------------------------------------------------
---Nome legível de um slot, para o aviso dizer ONDE está o problema.
---
---`_G` é consultado porque as globais de slot (`INVTYPE_*` não servem; as certas são as
---`..._SLOT`) variam de nome por peça, e um nome que não existe vira o número do slot em vez
---de quebrar.
local SLOT_GLOBAL = {
    [1] = "HEADSLOT",     [2] = "NECKSLOT",      [3] = "SHOULDERSLOT",
    [5] = "CHESTSLOT",    [6] = "WAISTSLOT",     [7] = "LEGSSLOT",
    [8] = "FEETSLOT",     [9] = "WRISTSLOT",     [10] = "HANDSSLOT",
    [11] = "FINGER0SLOT", [12] = "FINGER1SLOT",  [13] = "TRINKET0SLOT",
    [14] = "TRINKET1SLOT",[15] = "BACKSLOT",     [16] = "MAINHANDSLOT",
    [17] = "SECONDARYHANDSLOT",
}

function Gear.SlotName(slot)
    local key = SLOT_GLOBAL[slot]
    local name = key and _G and _G[key]
    if type(name) == "string" and name ~= "" then return name end
    return tostring(slot)
end

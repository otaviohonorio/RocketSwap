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
---Escapa os mágicos, troca `%d` por `%d+` e `%s` por `.+`, e **remove diretiva gramatical**
---(`|1forma1;forma2;`), que existe em alguns idiomas e não é literal.
local function BuildPattern(text)
    if type(text) ~= "string" or text == "" then return nil end

    -- A diretiva vira coringa: o que vem depois do número muda com o número.
    local clean = text:gsub("|%d+[^;]*;[^;]*;", "")

    local pattern = clean:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    pattern = pattern:gsub("%%%%d", "%%d+")
    pattern = pattern:gsub("%%%%s", ".+")
    return pattern
end

local pvpPattern

local function Pattern()
    if pvpPattern == nil then
        pvpPattern = BuildPattern(PVP_ITEM_LEVEL_TOOLTIP) or false
    end
    return pvpPattern or nil
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
---Se TODOS os slots lidos deram errado, é muito mais provável que a detecção tenha falhado
---(idioma cujo padrão não casa, tooltip não carregada) do que o jogador estar com dezesseis
---peças erradas. Nesse caso o addon cala a boca — é o mesmo raciocínio de "não achei a linha
---não quer dizer que não é peça de PvP", aplicado ao conjunto.
function Gear.LooksReliable(wrong, read)
    if read < 3 then return false end
    return #wrong < read
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

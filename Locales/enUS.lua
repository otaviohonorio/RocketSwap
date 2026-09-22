-- RocketSwap | Locales/enUS.lua
-- Base da localização. Este arquivo carrega SEMPRE, em qualquer idioma de cliente.
--
-- Mesma estrutura do RocketMeter (padronizado em 05/09/2026), em duas camadas:
--
--   1. A CHAVE É O TEXTO EM INGLÊS. Sem tradução, a própria chave aparece na tela — então o
--      inglês é o fallback automático de todo idioma que ainda não tem arquivo aqui.
--
--   2. `FROM_GAME` puxa do próprio cliente os rótulos que a Blizzard já traduziu, o que vale
--      para os ~11 idiomas de uma vez e usa **a palavra que o jogador já lê na interface**.
--
-- Depois deste arquivo carrega o do idioma (ptBR.lua), que sobrescreve o que quiser. A
-- precedência final é: nossa escolha explícita > palavra do jogo > chave em inglês.
local ADDON, ns = ...

local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})

ns.L = L

--------------------------------------------------------------------------------
-- Rótulos que o jogo já traduziu
--------------------------------------------------------------------------------
-- Esta tabela é curta **de propósito**. O vocabulário deste addon é quase todo frase nossa
-- ("Nenhum conjunto ainda", "Trocando de especialização..."), e para as palavras do jogo que
-- pareciam candidatas óbvias a evidência mandou parar. Ver o bloco de recusas abaixo.
--
-- O que este addon já fazia certo antes desta tabela existir: `Gear.lua:177-190` lê os nomes
-- de slot de `_G["HEADSLOT"]` e afins, com o número do slot como último recurso. Os 16 slots
-- do aviso de equipamento já saíam traduzidos em todos os idiomas.
local FROM_GAME = {
    ["Specialization"] = "SPECIALIZATION",
    ["Talents"]        = "TALENTS",
    ["Appearance"]     = "APPEARANCE_LABEL",
    ["Delete"]         = "DELETE",
    ["version"]        = "GAME_VERSION_LABEL",
}

-- O que NÃO entrou, e por quê — todas conferidas contra o build 12.1.0.69587:
--
--   "Ready check:"  READY_CHECK em pt-BR é **"Todos prontos?"**, uma pergunta. O rótulo é um
--                   prefixo ("Ready check: Gélido · SBA ST"), e daria "Todos prontos?: ...".
--   "Gear"          Nenhuma global limpa, e tem a armadilha de nome descrita no ptBR.lua: em
--                   pt-BR o jogo chama **loadout de talentos** de "equipamento" e **conjunto
--                   de itens** de "conjunto". Este addon foge das duas de propósito, porque
--                   ele existe para quem já confunde as duas coisas.
--   "Load"          Não existe global `LOAD`. `EQUIPSET_EQUIP` é "Equipar", e o botão faz
--                   mais do que equipar — troca spec e talentos também.
--   "(none)"        NONE é "Nenhum", sem os parênteses que o nosso rótulo usa.
--   "Warnings"      Só existe PING_TYPE_WARNING, singular ("Alerta"), do sistema de ping.

ns.FROM_GAME = FROM_GAME

---Esta global serve como rótulo?
---
---Três guardas, cada uma contra uma falha diferente:
---
---  * **não é string** → a global não existe neste cliente. Esta guarda **não pode** ser
---    simplificada: sem ela `text:find` recebe `nil` e **levanta erro na carga do arquivo**.
---    Como é aqui que `ns.L` nasce, o addon inteiro morre junto.
---  * **string vazia** → existe mas não tem texto; viraria um rótulo em branco.
---  * **tem `%s`/`%d`** → é modelo de frase, não rótulo, e apareceria cru na tela.
---
---Nos três casos a chave fica em paz e o inglês continua valendo.
---@return string|nil texto, string|nil motivo da recusa
local function Usable(tag)
    local text = _G[tag]
    if type(text) ~= "string" then return nil, "ausente" end
    if text == "" then return nil, "vazia" end
    if text:find("%%") then return nil, "modelo de frase" end
    return text
end

---Escreve os rótulos do jogo em `L`. Roda **uma vez**, na carga deste arquivo, antes do
---arquivo de idioma — que sobrescreve o que quiser depois.
function ns.ApplyGameStrings()
    for key, tag in pairs(FROM_GAME) do
        local text = Usable(tag)
        if text then
            rawset(L, key, text)
        end
    end
end

---Relatório para o `/rs i18n`. **Só lê** — reaplicar aqui apagaria o que o arquivo de idioma
---escreveu por cima, sem ninguém entender por quê.
---@return table lista de { key, tag, text, why }, ordenada pela global
function ns.CheckGameStrings()
    local report = {}
    for key, tag in pairs(FROM_GAME) do
        local text, why = Usable(tag)
        report[#report + 1] = { key = key, tag = tag, text = text, why = why }
    end
    table.sort(report, function(a, b) return a.tag < b.tag end)
    return report
end

ns.ApplyGameStrings()

-- Painel flutuante de progresso da troca (0.29.0)
L["turns the swap progress panel on or off"] = "turns the swap progress panel on or off"
L["swap progress panel on."] = "swap progress panel on."
L["swap progress panel off."] = "swap progress panel off."

-- Conjunto de itens com peça perdida (0.31.0)
L["%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."] = "%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."
L["You are already wearing the rest of it — use /rs fix to update the set."] = "You are already wearing the rest of it — use /rs fix to update the set."
L["Open the equipment manager, fix the set and save it, then switch."] = "Open the equipment manager, fix the set and save it, then switch."
L["%s updated with what you are wearing."] = "%s updated with what you are wearing."
L["nothing to fix: no gear set is missing items you are wearing."] = "nothing to fix: no gear set is missing items you are wearing."
L["updates a broken gear set with what you are wearing"] = "updates a broken gear set with what you are wearing"
L["%s: %d item(s) missing"] = "%s: %d item(s) missing"
L["Save set"] = "Save set"
L["Equipment Manager"] = "Equipment Manager"

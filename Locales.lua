-- RocketSwap | Locales.lua
-- As chaves SÃO o texto em inglês: sem tradução, a própria chave aparece na tela.
local ADDON, ns = ...

ns.L = setmetatable({}, {
    __index = function(_, key) return key end,
})

if GetLocale() ~= "ptBR" then return end

local L = ns.L

L["Presets"] = "Conjuntos"
L["New preset"] = "Novo conjunto"
L["Load"] = "Carregar"
L["Delete"] = "Apagar"
L["Specialization"] = "Especialização"

-- ARMADILHA DE NOME: a janela de talentos do jogo, em pt-BR, chama um loadout de talentos de
-- "equipamento" ("+ Novo equipamento"), enquanto a ficha do personagem chama um conjunto de
-- itens de "conjunto" ("+ Novo Conjunto"). A mesma palavra para as duas coisas, em telas
-- diferentes. Aqui as duas palavras são evitadas: "Talentos" e "Itens", sem ambiguidade —
-- justamente para quem já se confunde entre as duas.
L["Talents"] = "Talentos"
L["Gear"] = "Itens"

L["(none)"] = "(nenhum)"
-- Estado vazio (redesenho de 05/09/2026). O texto responde à pergunta que o BOTÃO levanta
-- ("vou ter que preencher tudo?") em vez de descrever o produto — e a resposta é verdade no
-- código: `UI.New` já nasce com a spec, o loadout e o conjunto que estão valendo.
L["No presets yet"] = "Nenhum conjunto ainda"
L["The first one starts with the spec, talents and gear you have right now."] =
    "O primeiro já nasce com a especialização, os talentos e os itens que você está usando agora."
L["Create the first preset"] = "Criar o primeiro conjunto"
L["Preset name"] = "Nome do conjunto"
L["Unnamed"] = "Sem nome"

L["Loading %s..."] = "Carregando %s..."
L["Switching specialization..."] = "Trocando de especialização..."
L["Loading talents..."] = "Carregando talentos..."
L["Equipping gear..."] = "Equipando os itens..."
L["%s is ready."] = "%s pronto."
L["Nothing to change — %s is already loaded."] = "Nada a trocar — %s já está carregado."

L["in combat: will apply when the fight ends."] = "em combate: aplico quando a luta acabar."
L["the specialization change failed."] = "a troca de especialização falhou."
L["the talent loadout could not be loaded."] = "não deu para carregar os talentos."
L["the gear set could not be equipped."] = "não deu para equipar o conjunto de itens."
L["some items of this set are locked (in use, or in the mail)."] =
    "algumas peças deste conjunto estão travadas (em uso, ou no correio)."
L["you are casting something — try again in a second."] =
    "você está conjurando algo — tente de novo daqui a pouco."
L["timed out waiting for the game to confirm."] = "o jogo não confirmou a tempo."

L["preset deleted."] = "conjunto apagado."

L["opens the window"] = "abre a janela"
L["loads a preset by name"] = "carrega um conjunto pelo nome"
L["lists the presets"] = "lista os conjuntos"
L["no preset with that name."] = "nenhum conjunto com esse nome."
L["commands:"] = "comandos:"
L["loaded. %d preset(s). Type /rs."] = "carregado. %d conjunto(s). Digite /rs."
L["Left click: open. Right click: load the last preset."] =
    "Clique: abrir. Botão direito: carregar o último conjunto."

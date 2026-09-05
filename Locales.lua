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
L["Appearance"] = "Aparência"

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
-- Transmog opcional (0.3.0)
L["Changing appearance..."] = "Trocando a aparência..."
L["this client cannot switch transmog outfits."] =
    "este cliente não sabe trocar conjuntos de aparência."
L["that transmog outfit no longer exists."] = "esse conjunto de aparência não existe mais."
L["the transmog outfit could not be applied."] = "não deu para aplicar a aparência."

-- Aviso de equipamento e resumo no ready check (0.4.0)
L["PvE gear in a PvP match."] = "Equipamento de PvE numa partida de PvP."
L["PvP gear in PvE content."] = "Equipamento de PvP em conteúdo de PvE."
L["...and %d more."] = "...e mais %d."
L["Load %s"] = "Carregar %s"
L["Don't warn here"] = "Não avise aqui"
L["ready check:"] = "conferência:"
L["(no talent loadout)"] = "(sem loadout de talentos)"
L["(no gear set)"] = "(sem conjunto de itens)"
L["gear warning on."] = "aviso de equipamento ligado."
L["gear warning off."] = "aviso de equipamento desligado."
L["ready check summary on."] = "resumo no ready check ligado."
L["ready check summary off."] = "resumo no ready check desligado."
L["all warnings re-enabled."] = "todos os avisos religados."
L["what you are wearing:"] = "o que você está usando:"
L["context:"] = "contexto:"
L["(open world)"] = "(mundo aberto)"
L["shows what each slot is reading as"] = "mostra como cada slot está sendo lido"
L["turns the gear warning on or off"] = "liga ou desliga o aviso de equipamento"
L["turns the ready check summary on or off"] = "liga ou desliga o resumo no ready check"
L["re-enables warnings you silenced"] = "religa os avisos que você silenciou"
L["Warn about wrong gear"] = "Avisar equipamento errado"
L["In an arena with PvE gear, or in a dungeon with PvP gear, the addon says which slots are wrong."] =
    "Numa arena com equipamento de PvE, ou numa masmorra com equipamento de PvP, o addon diz quais slots estão errados."
L["Show my setup on ready check"] = "Resumo no ready check"
L["When the leader starts a ready check, the addon prints your spec, talent loadout and gear set."] =
    "Quando o líder manda o ready check, o addon mostra sua especialização, seus talentos e seu conjunto de itens."

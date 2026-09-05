-- RocketSwap | Locales/ptBR.lua
-- Sobrescreve o que o enUS.lua deixou. Uma chave ausente aqui NÃO é um buraco: ela cai no
-- rótulo do jogo (quando `FROM_GAME` cobre) ou na própria chave, que já é o texto em inglês.
local ADDON, ns = ...

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
L["Show my setup on ready check"] = "Resumo no ready check"
L["Warnings"] = "Avisos"
L["These two work without any preset — they are what the addon does on the day you install it."] =
    "Os dois funcionam sem nenhum conjunto criado — é o que o addon faz no dia em que você o instala."
L["Wrong gear:"] = "Equipamento errado:"
L["In an arena or battleground it flags every slot WITHOUT the PvP item level line; in a dungeon or raid, every slot WITH it. It names the slots, and offers to load a preset if you have one that fits."] =
    "Em arena ou campo de batalha, marca todo slot SEM a linha de nível de item de PvP; em masmorra ou raide, todo slot COM ela. Diz quais slots são, e oferece carregar um conjunto se você tiver um que sirva."
L["Ready check:"] = "Ready check:"
L["When the leader starts one, it prints your specialization, talent loadout and gear set — so you can confirm before the pull."] =
    "Quando o líder manda, mostra sua especialização, seus talentos e seu conjunto de itens — para conferir antes de puxar."
L["It stays quiet in combat, once the gates are open, and whenever the reading is not reliable. Type /rs gear to see what it reads on each slot."] =
    "Ele cala em combate, depois que os portões abrem, e sempre que a leitura não for confiável. Digite /rs gear para ver como cada slot está sendo lido."

-- Conferencia dos rotulos que vem do jogo (0.5.0). Mesmo motivo do /rs gear: a falha e
-- silenciosa — a global some e o rotulo so continua em ingles.
L["checks the labels taken from the game"] = "confere os rotulos que vem do jogo"
L["locale %s, %d game label(s):"] = "idioma %s, %d rotulo(s) vindos do jogo:"
L["%d game label(s) are not usable here."] = "%d rotulo(s) do jogo nao servem neste cliente."
L["version"] = "versão"

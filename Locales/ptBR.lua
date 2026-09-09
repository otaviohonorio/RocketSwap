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
L["%d item(s) of this set are not available right now."] =
    "faltam %d peça(s) deste conjunto — o jogo não as encontra agora."
L["some items of this set are locked (in use, or in the mail)."] =
    "algumas peças deste conjunto estão travadas (em uso, ou no correio)."
L["you are casting something — try again in a second."] =
    "você está conjurando algo — tente de novo daqui a pouco."
L["timed out waiting for the game to confirm."] = "o jogo não confirmou a tempo."
-- Com o NOME do passo (0.9.0): numa corrente de quatro, "o jogo nao confirmou a tempo" obriga o
-- jogador a adivinhar de que passo se trata -- e foi o que aconteceu no relato de 06/09.
L["%s: the game did not confirm in time."] = "%s: o jogo não confirmou a tempo."

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
-- As duas chaves que sairam na 0.10.0 -- "Trocando a aparencia..." e "este cliente nao sabe
-- trocar" -- pressupunham que o addon TROCAVA. Ele nao troca: a API e protegida, e quem troca e
-- o clique do jogador no botao seguro. Frase que promete o que nao acontece e pior que frase
-- nenhuma.
L["the appearance only changes by clicking Load (Blizzard protects the API)."] =
    "a aparência só troca pelo botão Carregar (a Blizzard protege a API)."
L["that transmog outfit no longer exists."] = "esse conjunto de aparência não existe mais."
L["the transmog outfit could not be applied."] = "não deu para aplicar a aparência."

-- As tres portas que recusam a troca SEM devolver erro (0.7.0). A UI nativa do conjunto
-- consulta as tres antes de deixar clicar; sem elas o addon so sabia dizer "nao deu".
-- SEM OS SEGUNDOS (0.13.0). Contar quanto falta exige `startTime` e `duration`, que são SECRET
-- dentro de mítica+ — e foi essa conta que travava a corrente inteira. `isActive` responde a
-- mesma pergunta sem ler campo secreto nenhum.
L["changing appearance is on cooldown."] = "trocar de aparência está em recarga."
L["a style event is running; appearances are locked."] =
    "há um evento de estilo em andamento; as aparências estão travadas."
L["that appearance set is locked."] = "esse conjunto de aparência está travado."

-- Aviso de equipamento e resumo no ready check (0.4.0)
L["PvE gear in a PvP match."] = "Equipamento de PvE numa partida de PvP."
-- Modo guerra nao e partida: o jogador esta no mundo aberto, exposto a PvP enquanto faz
-- PvE. Dizer "partida" ali seria falso, e o mesmo texto para as duas situacoes vira ruido.
L["PvE gear with War Mode on."] = "Modo Guerra ligado, e voce esta de equipamento de PvE."
L["PvP gear in PvE content."] = "Equipamento de PvP em conteúdo de PvE."
L["...and %d more."] = "...e mais %d."
L["Load %s"] = "Carregar %s"
L["Don't warn here"] = "Não avise aqui"
L["ready check:"] = "conferência:"
-- As duas frases longas saíram na 0.11.2: com o rótulo na frente elas repetiam a própria
-- etiqueta, e arrastavam "loadout" (que o cliente traduz como "equipamento") e "conjunto" (que
-- aqui é o nome dos presets). O resumo usa `L["(none)"]`, que já existe e já é o que os combos
-- do editor mostram no mesmo caso.
-- O TÍTULO NOMEIA O CONTEÚDO, e não o ritual que abriu a caixa.
--
-- "Conferência" (0.11.2) dizia o que estava ACONTECENDO — o líder pediu conferência — e não
-- o que o jogador estava olhando. Pedido do usuário em 08/09/2026: *"tem um título
-- 'conferência', poderia trocar por algo melhor"*.
--
-- ⚑ E NÃO É "CONJUNTO ATUAL", que foi a primeira ideia. Duas razões, e as duas são do
-- próprio addon: (a) `conjunto` já é o nome dos PRESETS aqui (`L["Presets"]`), então o
-- título prometeria o contêiner e entregaria os campos; (b) a caixa **não** mostra um
-- preset — ela lê a especialização, os talentos e os itens que estão valendo AGORA, que
-- podem não bater com preset nenhum. Aliás, é exatamente esse descasamento que o addon
-- existe para revelar: um título dizendo "conjunto atual" mentiria justo na hora em que
-- a informação importa.
--
-- A frase escolhida já existia no addon, em `/rs gear`, para este mesmo conteúdo. Mesmo
-- vocabulário nos dois lugares, que é a regra que já governa os rótulos aqui dentro.
L["What you are using"] = "O que você está usando"
L["gear warning on."] = "aviso de equipamento ligado."
L["gear warning off."] = "aviso de equipamento desligado."
L["ready check summary on."] = "resumo no ready check ligado."
L["ready check summary off."] = "resumo no ready check desligado."
L["all warnings re-enabled."] = "todos os avisos religados."
L["what you are wearing:"] = "o que você está usando:"
L["context:"] = "contexto:"
L["(open world)"] = "(mundo aberto)"
L["shows what each slot is reading as"] = "mostra como cada slot está sendo lido"
L["shows the appearance sets and tests the switch"] =
    "mostra os conjuntos de aparência e testa a troca"
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

-- Falha parcial e motivo vindo do jogo (0.6.0)
L["talents: %s"] = "talentos: %s"
L["%s loaded, except: %s"] = "%s carregado, menos: %s"

-- O diário da troca (0.12.0)
L["log cleared."] = "diário limpo."
L["the log is empty: load a preset and look again."] =
    "o diário está vazio: carregue um conjunto e olhe de novo."
L["log: %d entries. The last ones:"] = "diário: %d linhas. As últimas:"
L["type /reload so the file is written, then send:"] =
    "digite /reload para o arquivo ser escrito, e mande:"
L["shows the log of the last swaps"] = "mostra o diário das últimas trocas"

-- A corrente honesta (0.13.0)
L["the talents were staged but not applied; open the talent window and apply."] =
    "os talentos foram preparados mas não aplicados; abra a janela de talentos e aplique."
L["an internal error interrupted this step."] = "um erro interno interrompeu este passo."
L["the specialization did not change, so the talents were left alone."] =
    "a especialização não trocou, então os talentos não foram mexidos."
-- O jogo recusa trocar de spec quando a anterior foi ha pouco. O diario real mostrou isso em
-- quatro das nove trocas: sempre a segunda, poucos segundos depois da primeira.
L["the game refused to change specialization now; wait a few seconds."] =
    "o jogo não deixou trocar de especialização agora; espere alguns segundos."
L["still applying %s: waiting for %s."] = "ainda aplicando %s: esperando %s."
-- A recusa da troca de spec e TRANSITORIA: o addon espera e insiste, em vez de devolver erro.
L["Waiting for the game to allow the specialization change..."] =
    "Esperando o jogo liberar a troca de especialização..."
L["the game kept refusing to change specialization."] =
    "o jogo continuou recusando a troca de especialização."
L["click Load to switch to %s completely."] =
    "clique em Carregar para trocar para %s por completo."

-- O progresso da troca: a janela mostrando que sao ETAPAS (0.18.0)
L["Switching to %s"] = "Trocando para %s"
-- "pulado" nao e falha, e o rotulo diz por que -- senao o passo pulado fica igual ao que ainda
-- nao comecou, e a pessoa termina sem saber se a aparencia foi aplicada ou esquecida.
L["%s — nothing to change"] = "%s — nada a mudar"

-- LoadConfig recusado SEM motivo declarado e transitorio: o addon insiste (0.18.2)
L["Waiting for the game to accept the talents..."] =
    "Esperando o jogo aceitar os talentos..."
L["the game kept refusing to load the talents."] =
    "o jogo continuou recusando carregar os talentos."

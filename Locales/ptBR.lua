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
-- diferentes. Por isso, enquanto os campos apareciam SOLTOS numa linha só separada por pontos,
-- as duas palavras eram evitadas e o rótulo de itens era "Itens".
--
-- ⛑ EM 22/09 ISSO MUDOU, e a mudança de tela é que permitiu: no card os quatro rótulos ficam
-- EMPILHADOS E VÍSIVEIS AO MESMO TEMPO. "Talentos:" e "Equipamento:" um embaixo do outro não
-- têm como ser confundidos entre si — a ambiguidade vinha de a palavra aparecer sozinha, sem o
-- irmão ao lado para contrastar. Pedido do usuário, e o contexto novo o sustenta.
L["Talents"] = "Talentos"
L["Gear"] = "Equipamento"
L["Appearance"] = "Aparência"

-- "Resumo ..." nos dois, e sem "setup": os rótulos são irmãos (mesma informação, gatilho
-- diferente), e rótulo irmão com forma diferente obriga a ler os dois para notar que dizem a
-- mesma coisa.
--
-- ⛑ "READY CHECK" FICA EM INGLÊS (22/09), por decisão do usuário e com razão: é como o jogador
-- brasileiro chama a coisa. A regra do projeto é evitar palavra em inglês com equivalente em
-- português — mas a mesma regra abre exceção para jargão do próprio jogo, e este é um. Conferido
-- no cliente: o termo em inglês é **Ready Check**, com o comando `/readycheck` e o evento
-- `READY_CHECK`. "Verificação de prontidão" é correto e ninguém fala.
L["Show my setup when a PvP queue pops"] = "Resumo quando a fila de PvP chamar"
L["PvP queue is up — check before you enter"] = "A fila de PvP chamou — confira antes de entrar"
L["PvP queue is up:"] = "fila de PvP chamou:"
L["PvP queue pop summary on."] = "resumo no convite da fila de PvP ligado."
L["PvP queue pop summary off."] = "resumo no convite da fila de PvP desligado."
L["turns the PvP queue pop summary on or off"] = "liga ou desliga o resumo no convite da fila de PvP"
-- O CONVITE DA FILA É O ÚLTIMO MOMENTO ÚTIL: dentro da arena a restrição de addon fecha a troca
-- do começo ao fim da partida. Daí o resumo aparecer aqui e não só no ready check.
L["PvP queue pop:"] = "Convite da fila de PvP:"
L["When the arena or battleground invite shows up, it prints the same summary — the last moment when you can still fix the build."] =
    "Quando aparece o convite da arena ou do campo de batalha, ele mostra o mesmo resumo — é o último momento em que ainda dá para ajustar talentos e itens."

L["(none)"] = "(nenhum)"
-- A opção que esvazia o campo Aparência (21/10): o campo vazio fica em branco, e a opção diz o que o
-- conjunto faz então — não mexe na roupa. "(nenhum)" lia como "sem aparência" e nem concordava com o
-- rótulo ("Aparência: (nenhum)").
L["Keep current"] = "Manter a atual"
-- O conjunto que está no corpo com peça trocada. `(nenhum)` era falso aqui — ver o comentário em
-- `Alert.Summary`. "peças" e não "itens" de propósito: "Itens" é o RÓTULO do campo, e
-- "Itens: Gélido (13 de 14 itens)" repetiria a etiqueta dentro do valor.
L["%s (%d of %d pieces)"] = "%s (%d de %d peças)"
-- Estado vazio (redesenho de 05/09/2026). O texto responde à pergunta que o BOTÃO levanta
-- ("vou ter que preencher tudo?") em vez de descrever o produto — e a resposta é verdade no
-- código: `UI.New` já nasce com a spec, o loadout e o conjunto que estão valendo.
L["No presets yet"] = "Nenhum conjunto ainda"
L["The first one starts with the spec, talents and gear you have right now."] =
    "O primeiro já vem com a especialização, os talentos e os itens que você está usando agora."
L["Create the first preset"] = "Criar o primeiro conjunto"
L["Preset name"] = "Nome do conjunto"
L["Unnamed"] = "Sem nome"

L["Loading %s..."] = "Carregando %s..."
L["Switching specialization..."] = "Trocando de especialização..."
L["Loading talents..."] = "Carregando talentos..."
L["Equipping gear..."] = "Equipando os itens..."
L["%s is ready."] = "%s pronto."
L["Nothing to change — %s is already loaded."] = "Nada a trocar — %s já está carregado."

L["in combat: will apply when the fight ends."] = "em combate: será aplicado quando a luta acabar."
L["the talent loadout could not be loaded."] = "não foi possível carregar os talentos."
L["the gear set could not be equipped."] = "não foi possível equipar o conjunto de itens."
L["%d item(s) of this set are not available right now."] =
    "faltam %d peça(s) deste conjunto — o jogo não as encontra agora."
L["some items of this set are locked (in use, or in the mail)."] =
    "algumas peças deste conjunto estão bloqueadas (em uso ou no correio)."
L["you are casting something — try again in a second."] =
    "você está conjurando algo — tente de novo daqui a pouco."
-- APAGADO É DIFERENTE DE RECUSADO, e cada um manda o jogador procurar em lugar diferente. A
-- aparência já tinha a frase dela; estas duas faltavam, e no lugar delas saía a genérica.
L["that talent loadout no longer exists."] = "esse conjunto de talentos não existe mais."
L["that gear set no longer exists."] = "esse conjunto de itens não existe mais."
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
-- ⛑ O CLIQUE DIREITO MUDOU (23/09): antes ele TROCAVA de conjunto, e um usuário reportou
-- em vídeo que "trocava a spec sozinha". Agora ele lista os conjuntos, como manda a
-- convenção de ícone de minimapa.
L["Switch to"] = "Trocar para"
-- Transmog opcional (0.3.0)
-- As duas chaves que sairam na 0.10.0 -- "Trocando a aparencia..." e "este cliente nao sabe
-- trocar" -- pressupunham que o addon TROCAVA. Ele nao troca: a API e protegida, e quem troca e
-- o clique do jogador no botao seguro. Frase que promete o que nao acontece e pior que frase
-- nenhuma.
L["the appearance only changes by clicking Load (Blizzard protects the API)."] =
    "a aparência só muda pelo botão Carregar (a Blizzard protege a API)."
L["that transmog outfit no longer exists."] = "essa roupa não existe mais."
L["the transmog outfit could not be applied."] = "não foi possível aplicar a roupa."

-- As tres portas que recusam a troca SEM devolver erro (0.7.0). A UI nativa do conjunto
-- consulta as tres antes de deixar clicar; sem elas o addon so sabia dizer "nao deu".
-- SEM OS SEGUNDOS (0.13.0). Contar quanto falta exige `startTime` e `duration`, que são SECRET
-- dentro de mítica+ — e foi essa conta que travava a corrente inteira. `isActive` responde a
-- mesma pergunta sem ler campo secreto nenhum.
L["changing appearance is on cooldown."] = "trocar de aparência está em recarga."
L["a style event is running; appearances are locked."] =
    "há um evento de estilo em andamento; as aparências estão bloqueadas."
L["that appearance set is locked."] = "essa roupa está bloqueada."

-- Aviso de equipamento e resumo no ready check (0.4.0)
L["PvE gear in a PvP match."] = "Equipamento de PvE numa partida de PvP."
-- Modo guerra nao e partida: o jogador esta no mundo aberto, exposto a PvP enquanto faz
-- PvE. Dizer "partida" ali seria falso, e o mesmo texto para as duas situacoes vira ruido.
L["PvE gear with War Mode on."] = "Modo de Guerra ligado, e você está com equipamento de PvE."
L["PvP gear in PvE content."] = "Equipamento de PvP em conteúdo de PvE."
L["...and %d more."] = "...e mais %d."
L["Load %s"] = "Carregar %s"
L["Don't warn here"] = "Não avisar aqui"
L["ready check:"] = "Ready Check:"
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
L["war mode warning on."] = "aviso com Modo de Guerra ligado."
L["war mode warning off."] = "aviso com Modo de Guerra desligado."
L["ready check summary on."] = "resumo no Ready Check ligado."
L["ready check summary off."] = "resumo no Ready Check desligado."
L["all warnings re-enabled."] = "todos os avisos religados."
L["what you are wearing:"] = "o que você está usando:"
L["context:"] = "contexto:"
L["(open world)"] = "(mundo aberto)"
L["shows what each slot is reading as"] =
    "mostra como cada espaço está sendo lido (/rs gear <espaço> mostra a dica daquele espaço)"
L["shows the appearance sets and tests the switch"] =
    "mostra as roupas e testa a troca"
L["turns the gear warning on or off"] = "liga ou desliga o aviso de equipamento"
L["turns the ready check summary on or off"] = "liga ou desliga o resumo no Ready Check"
L["re-enables warnings you silenced"] = "religa os avisos que você silenciou"
L["Warn about wrong gear"] = "Avisar sobre equipamento errado"
-- Desmarcada por padrão (12/09). O rótulo diz ONDE o aviso passa a valer, não o que ele é: quem
-- lê a lista de caixas já sabe que se trata do aviso de equipamento pela caixa de cima.
L["Warn with War Mode on too"] = "Avisar também com Modo de Guerra ligado"
L["Show my setup on Ready Check"] = "Resumo no Ready Check"
L["Warnings"] = "Avisos"
L["These two work without any preset — they are what the addon does on the day you install it."] =
    "Os dois funcionam sem nenhum conjunto criado — é o que o addon faz no dia em que você o instala."
L["Wrong gear:"] = "Equipamento errado:"
L["In the open world with War Mode on it stays quiet unless you tick the second box: out there most of the time is questing, not fighting players."] =
    "No mundo aberto com Modo de Guerra ligado ele fica em silêncio, a não ser que você marque a segunda " ..
    "caixa: lá fora a maior parte do tempo é missão, não combate contra jogadores."
L["In an arena or battleground it flags every slot WITHOUT the PvP item level line; in a dungeon or raid, every slot WITH it. It names the slots, and offers to load a preset if you have one that fits."] =
    "Em arena ou campo de batalha, marca todo espaço SEM a linha de nível de item de PvP; em masmorra ou raide, todo espaço COM ela. Diz quais espaços são e oferece carregar um conjunto, se você tiver um que sirva."
L["Ready check:"] = "Ready Check:"
L["When the leader starts one, it prints your specialization, talent loadout and gear set — so you can confirm before the pull."] =
    "Quando o líder inicia um, mostra sua especialização, seus talentos e seu conjunto de itens — para conferir antes de puxar."
L["It stays quiet in combat, once the gates are open, and whenever the reading is not reliable. Type /rs gear to see what it reads on each slot."] =
    "Ele fica em silêncio em combate, depois que os portões abrem e sempre que a leitura não for confiável. Digite /rs gear para ver como cada espaço está sendo lido."

-- Conferencia dos rotulos que vem do jogo (0.5.0). Mesmo motivo do /rs gear: a falha e
-- silenciosa — a global some e o rotulo so continua em ingles.
L["checks the labels taken from the game"] = "confere os rótulos que vêm do jogo"
L["locale %s, %d game label(s):"] = "idioma %s, %d rótulo(s) vindos do jogo:"
L["%d game label(s) are not usable here."] = "%d rótulo(s) do jogo não servem neste cliente."
L["version"] = "versão"

-- Falha parcial e motivo vindo do jogo (0.6.0)
L["talents: %s"] = "talentos: %s"
L["%s loaded, except: %s"] = "%s carregado, menos: %s"

-- O diário da troca (0.12.0)
L["log cleared."] = "diário limpo."
L["the log only exists in development builds."] = "o diário só existe na versão de desenvolvimento."
L["the log is empty: load a preset and look again."] =
    "o diário está vazio: carregue um conjunto e olhe de novo."
L["log: %d entries. The last ones:"] = "diário: %d linhas. As últimas:"
L["type /reload so the file is written, then send:"] =
    "digite /reload para gravar o arquivo e depois envie:"
L["shows the log of the last swaps"] = "mostra o diário das últimas trocas"

-- A corrente honesta (0.13.0)
L["the talents were staged but not applied; open the talent window and apply."] =
    "os talentos foram preparados mas não aplicados; abra a janela de talentos e aplique."
L["an internal error interrupted this step."] = "um erro interno interrompeu este passo."
L["the specialization did not change, so the talents were left alone."] =
    "a especialização não mudou, então os talentos ficaram como estavam."
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
L["Switching to %s. Wait for it to finish."] = "Trocando para %s. Espere até terminar."
L["you are in %s: leave the form to change specialization."] = "você está em %s: saia da forma para trocar de especialização."
L["you are shapeshifted: leave the form to change specialization."] = "você está transformado: saia da forma para trocar de especialização."
L["%s was NOT loaded: the specialization did not change, and nothing after it was touched."] = "%s NÃO foi carregado: a especialização não mudou, e nada depois dela foi alterado."
-- "pulado" nao e falha, e o rotulo diz por que -- senao o passo pulado fica igual ao que ainda
-- nao comecou, e a pessoa termina sem saber se a aparencia foi aplicada ou esquecida.
L["%s — nothing to change"] = "%s — nada a mudar"

-- LoadConfig recusado SEM motivo declarado e transitorio: o addon insiste (0.18.2)
L["Waiting for the game to accept the talents..."] =
    "Esperando o jogo aceitar os talentos..."
L["the game kept refusing to load the talents."] =
    "o jogo continuou se recusando a carregar os talentos."

-- Captura de erro no diario (RocketMeter 0.80.0 / RocketSwap 0.21.0)
L["errors are NOT being captured on this client."] =
    "os erros NÃO estão sendo capturados neste cliente."
L["no error captured (capture: %s)."] = "nenhum erro capturado (captura: %s)."
L["%d error(s) captured, %d occurrence(s):"] = "%d erro(s) capturado(s), %d ocorrência(s):"

-- Painel flutuante de progresso da troca (0.29.0)
L["turns the swap progress panel on or off"] = "liga ou desliga o painel de progresso da troca"
L["swap progress panel on."] = "painel de progresso da troca ligado."
L["swap progress panel off."] = "painel de progresso da troca desligado."

-- Conjunto de itens com peça perdida (0.31.0)
L["%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."] = "%s: %d item(ns) faltando — o espaço fica com a peça atual, que pode ser a errada. Salve o conjunto antes."
L["You are already wearing the rest of it — use /rs fix to update the set."] = "Você já está vestindo o resto dele — use /rs fix para salvar o conjunto."
L["Open the equipment manager, fix the set and save it, then switch."] = "Abra o gerenciador de equipamentos, ajuste o conjunto e salve; depois troque."
L["%s updated with what you are wearing."] = "%s salvo com o que você está vestindo."
L["nothing to fix: no gear set is missing items you are wearing."] = "nada a consertar: nenhum conjunto está sem uma peça que você esteja vestindo."
L["updates a broken gear set with what you are wearing"] = "salva o conjunto incompleto com o que você está vestindo"
L["%s: %d item(s) missing"] = "%s: %d item(ns) faltando"
L["Save set"] = "Salvar conjunto"
L["Equipment Manager"] = "Gerenciador"

-- Colunas dos avisos (0.34.0)
L["Turn on the wrong gear warning first."] = "Ligue primeiro o aviso de equipamento errado."

-- Colunas dos avisos por conteudo (0.35.0)
L["PvE"] = "PvE"
L["PvP"] = "PvP"

-- Macro por conjunto (Macro.lua, 25/09)
L["in combat: the preset's macro will be made when the fight ends."] = "em combate: a macro do conjunto será criada quando o combate acabar."
L["macro renamed: %s"] = "macro renomeada: %s"
L["this character's macros are full (%d of %d): the preset has no macro."] = "as macros do personagem estão cheias (%d de %d): o conjunto ficou sem macro."
L["macro created in this character's macros and placed on your action bar: %s"] = "macro criada nas macros do personagem e colocada na barra de ações: %s"
L["macro created in this character's macros (no empty slot on a visible bar, drag it from /macro): %s"] = "macro criada nas macros do personagem (não há espaço vazio numa barra visível; arraste-a pelo /macro): %s"
L["macro deleted with the preset: %s"] = "macro apagada junto com o conjunto: %s"
L["makes a macro for each preset, on this character"] = "cria a macro de cada conjunto, neste personagem"
L["Action Bar %d"] = "Barra de ações %d"
L["%s, button %d"] = "%s, botão %d"
L["Give the preset a name first."] = "Dê um nome ao conjunto primeiro."
L["(required)"] = "(obrigatório)"
L["A preset needs a name: the previous one was kept."] = "O conjunto precisa de nome: o nome anterior foi mantido."
L["Could not make the macro (this character's macros may be full)."] = "Não foi possível criar a macro (as macros do personagem podem estar cheias)."
L["Drop the macro on an action bar slot."] = "Solte a macro num espaço da barra de ações."
L["Drag to an action bar to make it a button."] = "Arraste para uma barra de ações para criar um botão."

-- Troca tudo ou nada (Data.lua, 26/09)
L["%d min %d s"] = "%d min %d s"
L["%d s"] = "%d s"
L["(you can switch in %s)"] = "(você poderá trocar em %s)"
L["in combat: nothing was changed. Switch after the fight."] = "em combate: nada foi trocado. Troque depois da luta."
L["changing specialization is on cooldown."] = "a troca de especialização está em recarga."
L["stand still: changing specialization is a cast, and moving cuts it."] = "fique parado: a troca de especialização é um lançamento, e andar a interrompe."
L["talents cannot be changed here."] = "não é possível trocar talentos aqui."
L["some items of the set are locked (a trade, the bank, a repair)."] = "há itens do conjunto bloqueados (numa troca, no banco, num reparo)."
L["the appearance only changes by clicking the preset (window, or its macro on the bar)."] = "a aparência só muda clicando no conjunto (na janela ou na macro dele na barra)."
L["%s was NOT loaded — nothing was changed:"] = "%s NÃO foi carregado — nada foi trocado:"
L["in a PvP match -- the countdown included -- the game blocks switches made by addons. Switch before accepting the queue."] = "numa partida de PvP — inclusive na contagem — o jogo bloqueia trocas feitas por addon. Troque antes de aceitar a fila."
L["during a boss encounter the game blocks switches made by addons."] = "durante o encontro com um chefe o jogo bloqueia trocas feitas por addon."
L["during a Mythic+ keystone the game blocks switches made by addons."] = "durante uma chave de Mítica+ o jogo bloqueia trocas feitas por addon."

-- Doação (Donate.lua, 26/09)
L["Link copied — paste it in your browser."] = "Link copiado — cole no navegador."
L["Thank you for supporting Rocket Swap! Press Ctrl+C to copy the link, then paste it in your browser."] = "Obrigado por apoiar o Rocket Swap! Aperte Ctrl+C para copiar o link e cole no navegador."
L["Click: open the donation link, ready to copy"] = "Clique: abrir o link de doação, pronto para copiar"
L["Support the project"] = "Apoiar o projeto"
L["Report a problem"] = "Relatar um problema"
L["Report a problem on"] = "Relatar um problema em"
L["Click: choose where to report a problem"] = "Clique: escolher onde relatar um problema"
L["Rocket Swap %s — report a problem on %s.|n|nPress Ctrl+C to copy the link, then paste it in your browser. Say what you were doing and what happened."] =
    "Rocket Swap %s — relatar um problema em %s.|n|nAperte Ctrl+C para copiar o link e cole no navegador. Conte o que você estava fazendo e o que aconteceu."

-- Botões para as janelas do jogo e título do nome (UI.lua, 27/09)
L["Equipment"] = "Equipamentos"
L["e.g. Raid, M+, Arena"] = "Ex.: Raide, M+, Arena"
L["Opens the game's talent window, to create or edit a loadout."] = "Abre a janela de talentos do jogo, para criar ou editar um conjunto de talentos."
L["Opens the character sheet on the equipment manager, to create or save a set."] = "Abre a ficha do personagem no gerenciador de equipamentos, para criar ou salvar um conjunto."

-- the minimap tooltip, the same in every Rocket addon (13/10)
L["Click: open the window"] = "Clique: abrir a janela"
L["Right-click: pick a preset"] = "Clique direito: escolher um conjunto"
-- (25/10) the Rocket SBA Lab's builds as presets (Data.RocketPairs, UI.FromRocketLab)
L["From Rocket SBA Lab"] = "Do Rocket SBA Lab"
L["Rocket SBA Lab saves each build's talents and items in the game, under the build's name. This joins the two of each one into a preset here."] =
    "O Rocket SBA Lab salva no jogo os talentos e os itens de cada build, com o nome dela. Este botão junta os dois de cada uma num conjunto daqui."
L["Click: create or update the presets"] = "Clique: criar ou atualizar os conjuntos"
L["The game has no talents and items of Rocket SBA Lab yet."] = "O jogo ainda não tem talentos e itens do Rocket SBA Lab."
L["The Rocket SBA Lab presets are already up to date."] = "Os conjuntos do Rocket SBA Lab já estão em dia."
L["Rocket SBA Lab: %d preset(s) created, %d updated."] = "Rocket SBA Lab: %d conjunto(s) criado(s), %d atualizado(s)."

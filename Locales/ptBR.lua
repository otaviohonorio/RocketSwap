-- RocketSwap | Locales/ptBR.lua
-- Overrides what enUS.lua left. A key absent here is NOT a hole: it falls to the
-- game's label (when `FROM_GAME` covers it) or to the key itself, which is already the English text.
local ADDON, ns = ...

if GetLocale() ~= "ptBR" then return end

local L = ns.L

L["Presets"] = "Conjuntos"
L["New preset"] = "Novo conjunto"
L["Load"] = "Carregar"
L["Delete"] = "Apagar"
L["Specialization"] = "Especialização"

-- NAMING TRAP: the game's talent window, in pt-BR, calls a talent loadout
-- "equipamento" ("+ Novo equipamento"), while the character sheet calls an item
-- set "conjunto" ("+ Novo Conjunto"). The same word for the two things, on different
-- screens. That is why, while the fields showed LOOSE on a single line separated by dots,
-- the two words were avoided and the items label was "Itens".
--
-- ⛑ ON 22/09 THAT CHANGED, and the change of screen is what allowed it: on the card the four labels sit
-- STACKED AND VISIBLE AT THE SAME TIME. "Talentos:" and "Equipamento:" one under the other have
-- no way of being confused with each other -- the ambiguity came from the word showing alone, without the
-- sibling beside it to contrast. The user's request, and the new context supports it.
L["Talents"] = "Talentos"
L["Gear"] = "Equipamento"
L["Appearance"] = "Aparência"

-- "Resumo ..." in both, and without "setup": the labels are siblings (the same information, a different
-- trigger), and a sibling label with a different form forces one to read both to notice they say the
-- same thing.
--
-- ⛑ "READY CHECK" STAYS IN ENGLISH (22/09), by the user's decision and rightly so: it is how the Brazilian
-- player calls the thing. The project's rule is to avoid an English word that has a Portuguese
-- equivalent -- but the same rule makes an exception for the game's own jargon, and this is one. Checked
-- in the client: the English term is **Ready Check**, with the `/readycheck` command and the
-- `READY_CHECK` event. "Verificação de prontidão" is correct and nobody says it.
L["Show my setup when a PvP queue pops"] = "Resumo quando a fila de PvP chamar"
L["PvP queue is up — check before you enter"] = "A fila de PvP chamou — confira antes de entrar"
L["PvP queue is up:"] = "fila de PvP chamou:"
L["PvP queue pop summary on."] = "resumo no convite da fila de PvP ligado."
L["PvP queue pop summary off."] = "resumo no convite da fila de PvP desligado."
L["turns the PvP queue pop summary on or off"] = "liga ou desliga o resumo no convite da fila de PvP"
-- THE QUEUE INVITE IS THE LAST USEFUL MOMENT: inside the arena the addon restriction closes the swap
-- from the start to the end of the match. Hence the summary showing here and not only on the ready check.
L["PvP queue pop:"] = "Convite da fila de PvP:"
L["When the arena or battleground invite shows up, it prints the same summary — the last moment when you can still fix the build."] =
    "Quando aparece o convite da arena ou do campo de batalha, ele mostra o mesmo resumo — é o último momento em que ainda dá para ajustar talentos e itens."

L["(none)"] = "(nenhum)"
-- The option that empties the Appearance field (21/10): the empty field stays blank, and the option says what the
-- set then does -- it does not touch the outfit. "(nenhum)" read as "no appearance" and did not even agree with the
-- label ("Aparência: (nenhum)").
L["Keep current"] = "Manter a atual"
-- The set that is on the body with a swapped piece. `(nenhum)` was false here -- see the comment in
-- `Alert.Summary`. "peças" and not "itens" on purpose: "Itens" is the field's LABEL, and
-- "Itens: Gélido (13 de 14 itens)" would repeat the tag inside the value.
L["%s (%d of %d pieces)"] = "%s (%d de %d peças)"
-- Empty state (redesign of 05/09/2026). The text answers the question the BUTTON raises
-- ("will I have to fill everything in?") instead of describing the product -- and the answer is true in the
-- code: `UI.New` is already born with the spec, the loadout and the set in effect.
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
-- DELETED IS DIFFERENT FROM REFUSED, and each one sends the player to look in a different place. The
-- appearance already had its phrase; these two were missing, and in their place the generic one came out.
L["that talent loadout no longer exists."] = "esse conjunto de talentos não existe mais."
L["that gear set no longer exists."] = "esse conjunto de itens não existe mais."
L["timed out waiting for the game to confirm."] = "o jogo não confirmou a tempo."
-- With the step's NAME (0.9.0): in a chain of four, "o jogo nao confirmou a tempo" forces the
-- player to guess which step it is about -- and that is what happened in the report of 06/09.
L["%s: the game did not confirm in time."] = "%s: o jogo não confirmou a tempo."

L["preset deleted."] = "conjunto apagado."

L["opens the window"] = "abre a janela"
L["loads a preset by name"] = "carrega um conjunto pelo nome"
L["lists the presets"] = "lista os conjuntos"
L["no preset with that name."] = "nenhum conjunto com esse nome."
L["commands:"] = "comandos:"
L["loaded. %d preset(s). Type /rs."] = "carregado. %d conjunto(s). Digite /rs."
-- ⛑ THE RIGHT CLICK CHANGED (23/09): before it SWITCHED sets, and a user reported
-- on video that it "trocava a spec sozinha". Now it lists the sets, as the
-- minimap icon convention says.
L["Switch to"] = "Trocar para"
-- Optional transmog (0.3.0)
-- The two keys that left in 0.10.0 -- "Trocando a aparencia..." and "este cliente nao sabe
-- trocar" -- assumed the addon SWAPPED. It does not: the API is protected, and what swaps is
-- the player's click on the secure button. A phrase that promises what does not happen is worse than no
-- phrase at all.
L["the appearance only changes by clicking Load (Blizzard protects the API)."] =
    "a aparência só muda pelo botão Carregar (a Blizzard protege a API)."
L["that transmog outfit no longer exists."] = "essa roupa não existe mais."
L["the transmog outfit could not be applied."] = "não foi possível aplicar a roupa."

-- The three gates that refuse the swap WITHOUT returning an error (0.7.0). The native set UI
-- queries all three before allowing a click; without them the addon could only say "it did not work".
-- WITHOUT THE SECONDS (0.13.0). Counting how much is left requires `startTime` and `duration`, which are SECRET
-- inside mythic+ -- and it was that arithmetic that locked up the whole chain. `isActive` answers the
-- same question without reading any secret field.
L["changing appearance is on cooldown."] = "trocar de aparência está em recarga."
L["a style event is running; appearances are locked."] =
    "há um evento de estilo em andamento; as aparências estão bloqueadas."
L["that appearance set is locked."] = "essa roupa está bloqueada."

-- Aviso de equipamento e resumo no ready check (0.4.0)
L["PvE gear in a PvP match."] = "Equipamento de PvE numa partida de PvP."
-- War Mode is not a match: the player is in the open world, exposed to PvP while doing
-- PvE. Saying "partida" there would be false, and the same text for both situations becomes noise.
L["PvE gear with War Mode on."] = "Modo de Guerra ligado, e você está com equipamento de PvE."
L["PvP gear in PvE content."] = "Equipamento de PvP em conteúdo de PvE."
L["...and %d more."] = "...e mais %d."
L["Load %s"] = "Carregar %s"
L["Don't warn here"] = "Não avisar aqui"
L["ready check:"] = "Ready Check:"
-- The two long phrases left in 0.11.2: with the label in front they repeated their own
-- tag, and dragged along "loadout" (which the client translates as "equipamento") and "conjunto" (which
-- here is the presets' name). The summary uses `L["(none)"]`, which already exists and is already what the
-- editor's combos show in the same case.
-- THE TITLE NAMES THE CONTENT, and not the ritual that opened the box.
--
-- "Conferência" (0.11.2) said what was HAPPENING -- the leader asked for a check -- and not
-- what the player was looking at. The user's request on 08/09/2026: *"tem um título
-- 'conferência', poderia trocar por algo melhor"*.
--
-- ⚑ AND IT IS NOT "CONJUNTO ATUAL", which was the first idea. Two reasons, and both are the
-- addon's own: (a) `conjunto` is already the PRESETS' name here (`L["Presets"]`), so the
-- title would promise the container and deliver the fields; (b) the box does **not** show a
-- preset -- it reads the specialization, the talents and the items in effect NOW, which
-- may not match any preset. In fact, that mismatch is exactly what the addon
-- exists to reveal: a title saying "conjunto atual" would lie right when
-- the information matters.
--
-- The chosen phrase already existed in the addon, in `/rs gear`, for this same content. The same
-- vocabulary in both places, which is the rule that already governs the labels in here.
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
-- Unticked by default (12/09). The label says WHERE the warning comes to apply, not what it is: whoever
-- reads the list of boxes already knows it is the gear warning from the box above.
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

-- Checking the labels that come from the game (0.5.0). The same reason as /rs gear: the failure is
-- silent -- the global goes away and the label just stays in English.
L["checks the labels taken from the game"] = "confere os rótulos que vêm do jogo"
L["locale %s, %d game label(s):"] = "idioma %s, %d rótulo(s) vindos do jogo:"
L["%d game label(s) are not usable here."] = "%d rótulo(s) do jogo não servem neste cliente."
L["version"] = "versão"

-- Falha parcial e motivo vindo do jogo (0.6.0)
L["talents: %s"] = "talentos: %s"
L["%s loaded, except: %s"] = "%s carregado, menos: %s"

-- The swap's log (0.12.0)
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
-- The game refuses to switch spec when the previous switch was recent. The real log showed that in
-- four of the nine swaps: always the second, a few seconds after the first.
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

-- The swap's progress: the window showing that they are STEPS (0.18.0)
L["Switching to %s"] = "Trocando para %s"
L["Switching to %s. Wait for it to finish."] = "Trocando para %s. Espere até terminar."
L["you are in %s: leave the form to change specialization."] = "você está em %s: saia da forma para trocar de especialização."
L["you are shapeshifted: leave the form to change specialization."] = "você está transformado: saia da forma para trocar de especialização."
L["%s was NOT loaded: the specialization did not change, and nothing after it was touched."] = "%s NÃO foi carregado: a especialização não mudou, e nada depois dela foi alterado."
-- "pulado" is not a failure, and the label says why -- otherwise the skipped step looks the same as one that has not
-- started yet, and the person ends without knowing whether the appearance was applied or forgotten.
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

-- Item set with a lost piece (0.31.0)
L["%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."] = "%s: %d item(ns) faltando — o espaço fica com a peça atual, que pode ser a errada. Salve o conjunto antes."
L["You are already wearing the rest of it — use /rs fix to update the set."] = "Você já está vestindo o resto dele — use /rs fix para salvar o conjunto."
L["Open the equipment manager, fix the set and save it, then switch."] = "Abra o gerenciador de equipamentos, ajuste o conjunto e salve; depois troque."
L["%s updated with what you are wearing."] = "%s salvo com o que você está vestindo."
L["nothing to fix: no gear set is missing items you are wearing."] = "nada a consertar: nenhum conjunto está sem uma peça que você esteja vestindo."
L["updates a broken gear set with what you are wearing"] = "salva o conjunto incompleto com o que você está vestindo"
L["%s: %d item(s) missing"] = "%s: %d item(ns) faltando"
L["Save set"] = "Salvar conjunto"
L["Equipment Manager"] = "Gerenciador"

-- Warning columns (0.34.0)
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

-- Donation (Donate.lua, 26/09)
L["Link copied — paste it in your browser."] = "Link copiado — cole no navegador."
L["Thank you for supporting Rocket Swap! Press Ctrl+C to copy the link, then paste it in your browser."] = "Obrigado por apoiar o Rocket Swap! Aperte Ctrl+C para copiar o link e cole no navegador."
L["Click: open the donation link, ready to copy"] = "Clique: abrir o link de doação, pronto para copiar"
L["Support the project"] = "Apoiar o projeto"
L["Report a problem"] = "Relatar um problema"
L["Report a problem on"] = "Relatar um problema em"
L["Click: choose where to report a problem"] = "Clique: escolher onde relatar um problema"
L["Rocket Swap %s — report a problem on %s.|n|nPress Ctrl+C to copy the link, then paste it in your browser. Say what you were doing and what happened."] =
    "Rocket Swap %s — relatar um problema em %s.|n|nAperte Ctrl+C para copiar o link e cole no navegador. Conte o que você estava fazendo e o que aconteceu."

-- Buttons for the game's windows and the name title (UI.lua, 27/09)
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

-- (26/10) The summary card of the ready check and of the PvP queue (Alert.lua)
L["complete set"] = "conjunto completo"
L["1 piece not from the set"] = "1 peça fora do conjunto"
L["%d pieces not from the set"] = "%d peças fora do conjunto"
L["Different from the saved piece: %s"] = "Diferente da peça salva: %s"
L["PvP queue is up"] = "A fila de PvP chamou"
L["Ready check"] = "Todos prontos?"  -- the game's READY_CHECK
L["Swapped on purpose? Save the gear set in the %s."] = "Trocou de propósito? Salve o conjunto de itens no %s."
L["The preset %s uses: %s"] = "O conjunto %s usa: %s"
L["Inside the match you can't switch."] = "Dentro da partida não dá para trocar."
L["Does not match the preset %s."] = "Não confere com o conjunto %s."
L["The preset %s: the gear is not complete."] = "Conjunto %s: o equipamento não está completo."
L["Matches the preset %s."] = "Confere com o conjunto %s."

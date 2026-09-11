# -*- coding: utf-8 -*-
"""Sabota uma coisa de cada vez e confere que o check CERTO reprova.

    python tests/sabotar.py        (da pasta do addon)

POR QUE ISTO EXISTE. A skill `wow-ui-design` e explicita: *contar linhas `ok` nao e criterio de
aprovacao*. Um `nil` numa constante recem-renomeada mata o harness no meio e as linhas `ok`
anteriores continuam la. Pior: um check pode estar medindo a si mesmo -- ja aconteceu aqui, um
`editorVisivel == false or painel:IsShown()` que era verdade sempre que o painel estava aberto.

O unico jeito de saber se um teste testa alguma coisa e QUEBRAR o que ele deveria pegar e ver o
defeito reaparecer exatamente onde ele disse que apareceria. Cada linha da tabela abaixo e um
defeito real que ja existiu ou que a proxima refatoracao pode reintroduzir.

Cada sabotagem roda numa COPIA; nada aqui toca o addon.
"""
import io, os, shutil, subprocess, sys, tempfile

SRC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA = os.environ.get("LUAJIT") or "C:/Users/ofhon/AppData/Local/Programs/LuaJIT/bin/luajit.exe"
if not os.path.exists(LUA):
    LUA = "luajit"      # o que estiver no PATH

# (nome, arquivo, de, para, label do check que TEM que reprovar)
SABOTAGENS = [
    # ------------------------------------------------------------------ o aviso de PvE em PvP
    # Quatro comportas caiavam esse aviso, e o usuario relatou o sintoma em 08/09/2026:
    # "o de pve no pvp, ainda nao vi funcionar, quando dou fila em BG, arena, ele nao avisa nada".

    ("a comporta volta a presumir falha quando tudo esta errado", "Gear.lua",
     u"    if #wrong < read then return true end",
     u"    if #wrong < read then return true end\n"
     u"    do return false end",
     "de PvE inteiro numa arena, a leitura vale"),

    # A outra metade da comporta tinha razao: com o padrao quebrado, TODA peca le `false`.
    ("a comporta para de exigir que a deteccao se prove", "Gear.lua",
     u"    return Gear.PatternWorks()",
     u"    return true",
     "padrao que nao se prova volta a calar"),

    # ⚑ SABOTA A FUNCAO INTEIRA, e nao a linha final. O teste que cobre o caso negativo e o da
    # global ausente, que sai pelos `return` adiantados -- trocar so a ultima linha nao mudaria a
    # resposta dele, e a sabotagem passaria batido dizendo que o teste existe.
    ("o autoteste do padrao responde sim para tudo", "Gear.lua",
     u"    if patternWorks ~= nil then return patternWorks end",
     u"    do return true end",
     "sem a global do jogo, a deteccao nao se prova"),

    # O comentario dizia "coringa" e o codigo REMOVIA: cola os dois lados e nunca casa.
    ("a diretiva gramatical volta a ser removida", "Gear.lua",
     u'    local clean = text:gsub("|%d+[^;]*;[^;]*;", "\\1")',
     u'    local clean = text:gsub("|%d+[^;]*;[^;]*;", "")',
     "diretiva no meio: o padrao ainda se prova"),

    ("a fila volta a valer so no estouro", "Alert.lua",
     u'            if status ~= nil and status ~= "none" and status ~= "error" then',
     u'            if status == "confirm" or status == "active" then',
     "na fila (queued) o contexto e de PvP"),

    ("o modo guerra volta a nao contar", "Alert.lua",
     u"        if ok and ligado then return \"warmode\" end",
     u"        if false then return \"warmode\" end",
     "com modo guerra ligado, o contexto existe"),

    # Com War Mode o contexto nao e "pvp", entao quem perguntar `context == \"pvp\"` joga o modo
    # guerra silenciosamente para o lado do PvE -- e passa a cobrar equipamento de PvE de quem
    # esta exposto.
    ("o modo guerra cai do lado do PvE", "Alert.lua",
     u"    return context == \"pvp\" or context == \"warmode\"",
     u"    return context == \"pvp\"",
     "de PvE com modo guerra ligado, o aviso aparece"),

    # Saber nao depende de poder consertar: a restricao de PvP fica ativa a partida inteira.
    ("o aviso volta a depender de poder consertar", "Alert.lua",
     u"    if InCombatLockdown() then return end\n"
     u"\n"
     u"    local wrong, read = ns.Gear.Wrong(WantsPvP(context), ns.db.mutedSlots)",
     u"    if not CanFix() then return end\n"
     u"\n"
     u"    local wrong, read = ns.Gear.Wrong(WantsPvP(context), ns.db.mutedSlots)",
     "durante a restricao de PvP o aviso ainda aparece"),

    ("prazo vencido vira visto verde", "Data.lua",
     u'if running.progress then running.progress[passo] = "failed" end',
     u'-- sabotado',
     "prazo vencido e FALHA, nao conclusao"),

    # DUAS DEFESAS PARA A MESMA COISA, e isso e de proposito: o passo abandonado e marcado pelo
    # `NoteOutcome` do caminho de insistencia E pelo laco do `Finish`. Sabotar so uma nao reprova
    # nada -- a outra cobre --, e foi assim que descobri que elas se sobrepoem.
    #
    # A sabotagem tira AS DUAS. E o unico jeito de o teste provar que ele mede a propriedade
    # ("passo abandonado aparece como falha") em vez de medir uma implementacao dela.
    ("as duas redes do passo abandonado", "Data.lua",
     u'        NoteOutcome("spec", outcome)',
     u'        -- sabotado',
     "o passo abandonado e falha, nao andamento",
     # segunda substituicao, no mesmo arquivo
     (u'            if running.progress and running.progress[key] == "doing" then\n'
      u'                running.progress[key] = "failed"\n'
      u'            end',
      u'            -- sabotado')),

    ("'pulado' volta a fundir as tres razoes", "Data.lua",
     u'running.progress[name] = (running.already or {})[name] and "skipped" or "done"',
     u'running.progress[name] = "skipped"',
     "a aparencia mudou no meio do caminho"),

    ("o retrato de antes some", "Data.lua",
     u'transmog = preset.transmog and Data.GetActiveOutfitID() == preset.transmog or nil,',
     u'transmog = nil,',
     "o que ja estava certo antes e que e 'nada a mudar'"),

    ("linha para passo que o conjunto nao pede", "Data.lua",
     u'if src.preset and src.preset[key] then',
     u'if true then',
     "com motivo, falha na hora"),

    ("o contador de tentativa volta para a tela", "UI.lua",
     u'        panel.clock:SetText(secs .. "s")',
     u'        panel.clock:SetText("tentativa " .. ((info.tries or 0) + 1) .. ", " .. secs .. "s")',
     "e ainda assim o relogio so conta segundos"),

    ("desiste na primeira recusa do LoadConfig", "Data.lua",
     u"local TALENT_RETRY_MAX = 5",
     u"local TALENT_RETRY_MAX = 0",
     "recusado sem motivo, o talento continua em andamento"),

    ("insiste mesmo com motivo declarado", "Data.lua",
     u'        if type(changeError) == "string" and changeError ~= "" then\n'
     u'            return "fail", TalentError(changeError)\n'
     u'        end\n'
     u'        return RetryTalent(preset)',
     u'        return RetryTalent(preset)',
     "o motivo do jogo chega ao jogador"),

    ("passo que desiste vira visto verde", "Data.lua",
     u'        NoteOutcome("talent", outcome)',
     u"        -- sabotado",
     "e o passo ficou como falha"),

    ("linhas grudadas (ritmo de 18)", "UI.lua",
     u'local PROGRESS_ROW = 22 ',
     u'local PROGRESS_ROW = 18 ',
     "vao entre linhas"),

    ("titulo colado no bloco", "UI.lua",
     u'local PROGRESS_TITLE_GAP = 13 ',
     u'local PROGRESS_TITLE_GAP = 4 ',
     "o titulo se separa do bloco em pelo menos o dobro"),

    ("atlas com nome errado", "UI.lua",
     u'done    = { atlas = "common-icon-checkmark",    alpha = 0.85 },',
     u'done    = { atlas = "common-icon-checkmarkX",   alpha = 0.85 },',
     "o atlas de done existe"),

    ("SetAtlasSafe que aprova qualquer nome", "Core.lua",
     u'    if not texture or not atlas or not texture.SetAtlas then return false end',
     u'    if true then return true end',
     "atlas inventado reprova"),

    ("o editor nao cede a coluna", "UI.lua",
     u'local has = preset ~= nil and not (frame.progress and frame.progress:IsShown())',
     u'local has = preset ~= nil',
     "o editor sai de cena enquanto o painel esta nela"),

    ("o resultado some no instante do fim", "UI.lua",
     u'local PROGRESS_HOLD = 5',
     u'local PROGRESS_HOLD = 0',
     "a troca que terminou ainda mostra o resultado"),

    ("pulsa a lista inteira", "UI.lua",
     u'local deve = passo.state == "doing" and info.live',
     u'local deve = info.live',
     "pulsa exatamente um passo"),

    ("o relogio congela", "UI.lua",
     u'        panel.clock:SetText(secs .. "s")',
     u'        panel.clock:SetText("")',
     "o relogio anda"),

    ("a janela nao tem quadro", "UI.lua",
     u'        UI.RefreshProgress()\n    end)',
     u'    end)',
     "e o quadro seguinte fecha o painel sozinho"),

    ("altura fixa em quatro vagas", "UI.lua",
     u'    panel:SetHeight(PROGRESS_ROW * #passos + PROGRESS_TITLE_GAP + PROGRESS_TITLE_INK)',
     u'    panel:SetHeight(PROGRESS_ROW * 4 + PROGRESS_TITLE_GAP + PROGRESS_TITLE_INK)',
     "a altura acompanha as tres etapas"),

    ("o pulado nao diz por que", "UI.lua",
     u'''            row.label:SetText(passo.state == "skipped"
                and format(L["%s \\u2014 nothing to change"], passo.label)
                or passo.label)'''.replace(u"\\u2014", u"\u2014"),
     u'            row.label:SetText(passo.label)',
     "e o rotulo diz por que"),

    ("o painel fora da coluna", "UI.lua",
     u'panel:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X, -60)',
     u'panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -60)',
     "o painel nasce na coluna do editor"),

    ("o painel invade os Avisos", "UI.lua",
     u'panel:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X, -60)',
     u'panel:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X, -230)',
     "com as quatro etapas ele ainda para antes dos Avisos"),
    # ------------------------------------------------ captura de erro no diario (09/09/2026)
    # ⚑ A CONFERENCIA DO HANDLER. O !BugGrabber faz `function seterrorhandler() end`, entao
    # instalar um handler com ele presente e uma chamada que nao faz nada e nao avisa. Sem esta
    # linha a captura se declara ligada estando desligada -- e "o arquivo nao tem erro nenhum"
    # vira mentira, que e a pior falha possivel num instrumento de diagnostico.
    ("a captura deixa de conferir se o handler pegou", "Log.lua",
     u"        if type(geterrorhandler) == \"function\" and geterrorhandler() == meu then",
     u"        if true then",
     "seterrorhandler mudo e sem BugGrabber: admite que nao captura"),

    # O FILTRO. Sem ele o diario enche do erro dos outros addons -- e, pior, faz parecer que o
    # defeito e nosso.
    ("o diario passa a guardar erro alheio", "Log.lua",
     u"    if not nossos and not pelaMensagem then return end",
     u"    -- sabotado",
     "erro de outro addon nao entra"),

    # ENCADEAR, E NAO SUBSTITUIR. Roubar o erro de quem ja tratava apaga o BugSack/ElvUI do
    # jogador: estragar a ferramenta dos outros para ter a nossa.
    ("a captura rouba o erro do handler anterior", "Log.lua",
     u"            if anterior then return anterior(mensagem, ...) end",
     u"            return",
     "  e o handler anterior continua sendo chamado"),

    # AGRUPAR REPETICAO. O caso real repetiu 1628 vezes; sem agrupar, o mesmo erro varre o anel
    # e apaga justamente o contexto que explica ele.
    ("erro repetido vira linha nova", "Log.lua",
     u"        if e.mensagem == mensagem then",
     u"        if false then",
     "repeticao vira contagem, nao linha nova"),

    # ------------------------------------------------- o passo de itens (diario de 09/09/2026)
    # O RETORNO VOLTA A SER JOGADO FORA. Sem ele a recusa imediata vira 20 segundos de espera por
    # um evento que ninguem vai mandar, e o jogador ouve "o jogo nao confirmou a tempo".
    ("o passo de itens ignora o retorno de novo", "Data.lua",
     u"    if equipou == false then\n"
     u"        return \"fail\", Data.GearFailureReason(preset.gear)\n"
     u"    end",
     u"    -- sabotado",
     "recusa imediata nao fica esperando evento"),

    # A CHAMADA SOME DO DIARIO. Foi exatamente esta cegueira que deixou a falha de 17:22:02
    # indistinguivel do sucesso de 00:00:26 no mesmo dia.
    ("a chamada de equipar some do diario", "Data.lua",
     u"        ns.Log.Call(\"gear\", \"UseEquipmentSet(\" .. tostring(preset.gear) .. \")\", ok, equipou)",
     u"        local _ = ok",
     "o diario registra a chamada de equipar"),

    # E O ESTADO DO CONJUNTO NA HORA DA RECUSA: sem ele nao da para separar "faltou peca" de
    # "o jogo recusou por outro motivo", que e a pergunta que o diario existe para responder.
    ("o estado do conjunto some da recusa", "Data.lua",
     u"                    ns.Log.Call(\"gear\", \"recusou; estado de \" .. tostring(running.preset.gear),\n"
     u"                        Data.DescribeGearSet(running.preset.gear) or \"sem resposta\")",
     u"                    local _ = running",
     "  e o diario guarda o estado do conjunto na hora da recusa"),

    # A MENSAGEM VOLTA A SER SEMPRE GENERICA, jogando fora a unica causa que a API prova.
    ("a falha deixa de contar as pecas perdidas", "Data.lua",
     u"    if c and type(c.perdidas) == \"number\" and c.perdidas > 0 then",
     u"    if false then",
     "a falha diz quantas pecas faltam"),

    # ----------------------------------- gravar talento e um cast (diario de 11/09/2026)
    # O ECO VOLTA A FECHAR O PASSO. E o defeito relatado: os itens pedidos com a gravacao em curso,
    # e o jogo recusando -- tres vezes em tres no diario.
    ("o eco da troca de spec volta a fechar a gravacao", "Data.lua",
     u"            if commit and (GetTime() - commit.since) >= COMMIT_ECHO_WINDOW then",
     u"            if commit then",
     "o eco da troca de spec nao pede os itens"),

    # O EVENTO VOLTA A CONFIRMAR O QUE NINGUEM GRAVOU: na insistencia o jogo recusou o LoadConfig,
    # e fechar no eco anunciava "pronto" e marcava o loadout como selecionado.
    ("o evento confirma sem gravacao nossa", "Data.lua",
     u"            local commit = running.commit\n",
     u"            local commit = running.commit or { since = -math.huge }\n",
     "o eco nao confirma o que o jogo recusou"),

    # QUALQUER CAST FECHA A GRAVACAO: o jogador lanca magia o tempo todo.
    ("qualquer magia fecha a gravacao", "Data.lua",
     u"                and arg3 == COMMIT_SPELL_ID then",
     u"                then",
     "cast alheio nao fecha a gravacao"),

    ("cast de outra unidade fecha a gravacao", "Data.lua",
     u"            if not running or arg1 ~= \"player\" then return end",
     u"            if not running then return end",
     "cast alheio nao fecha a gravacao"),

    # O SINAL DA BLIZZARD DEIXA DE SER OUVIDO: sobra so a reserva, 2 s depois no melhor caso.
    ("o fim do cast deixa de ser ouvido", "Data.lua",
     u"    listener:RegisterEvent(\"UNIT_SPELLCAST_SUCCEEDED\")\n",
     u"",
     "o fim do cast de gravacao libera os itens"),

    ("a gravacao que falha deixa de ser ouvida", "Data.lua",
     u"    listener:RegisterEvent(\"CONFIG_COMMIT_FAILED\")\n",
     u"",
     "gravacao que falha vira falha anotada"),

    # A FALHA VIRA VISTO VERDE: sem o "failed", o `RunNext` promove o passo a "done".
    ("a gravacao que falha vira concluida", "Data.lua",
     u"                if running.progress then running.progress.talent = \"failed\" end\n",
     u"",
     "gravacao que falha vira falha anotada"),

    # A GRAVACAO NAO E MARCADA: nada mais confirma o passo, e a corrente so anda pelo prazo.
    ("o passo de talentos nao marca a gravacao", "Data.lua",
     u"    running.commit = { since = GetTime() }",
     u"    running.commit = nil",
     "agora sim equipou o conjunto de PvP"),
]


FIM = "Tudo carregou e rodou sem erro de Lua."


def rodar(tmp):
    r = subprocess.run([LUA, "tests/harness.lua"], cwd=tmp,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return r.stdout.decode("utf-8", "replace")


# ⚑ CADA COPIA E APAGADA NO FIM, e isto ja foi defeito: sem a limpeza, cada rodada deixava uma
# copia inteira do addon no temp do sistema. Depois de 845 copias acumuladas nesta sessao, a suite
# passou a REPROVAR SABOTAGENS DIFERENTES A CADA RODADA -- e uma suite instavel nao vale nada:
# ela nao distingue "o teste nao pega" de "deu azar agora".
#
# O sintoma enganava: parecia que os testes e que estavam fracos.
# ⚑ UMA COPIA POR SUITE, e nao uma por sabotagem -- isto ja foi defeito duas vezes.
#
# A versao antiga fazia `copytree` do addon inteiro a cada sabotagem, e nunca apagava: depois de
# 845 copias acumuladas no temp do sistema, a suite passou a REPROVAR SABOTAGENS DIFERENTES A CADA
# RODADA. E uma suite instavel nao vale nada -- ela deixa de distinguir "o teste nao pega" de "deu
# azar agora", e o sintoma enganava: parecia que os testes e que estavam fracos.
#
# Agora e uma copia so, feita uma vez; cada sabotagem escreve o arquivo, roda, e RESTAURA o
# original a partir do texto guardado em memoria. Vinte copytree viram um.
def preparar():
    base = tempfile.mkdtemp(prefix="sab_")
    destino = os.path.join(base, "a")
    shutil.copytree(SRC, destino)
    return base, destino


def ler(destino, arquivo):
    return io.open(os.path.join(destino, arquivo), encoding="utf-8").read().replace("\r\n", "\n")


def escrever(destino, arquivo, texto):
    io.open(os.path.join(destino, arquivo), "w", encoding="utf-8", newline="\n").write(texto)


base, destino = preparar()
originais = {}

falhas = []
try:
    for entrada in SABOTAGENS:
        # A sexta posicao (opcional) e uma SEGUNDA substituicao no mesmo arquivo, para quando a
        # propriedade tem mais de uma defesa e sabotar so uma nao reprova nada.
        nome, arquivo, de, para, label = entrada[:5]
        extra = entrada[5] if len(entrada) > 5 else None

        if arquivo not in originais:
            originais[arquivo] = ler(destino, arquivo)
        txt = originais[arquivo]

        if txt.count(de) != 1:
            print("  ?     %-42s ANCORA NAO BATE (%d)" % (nome, txt.count(de)))
            falhas.append(nome)
            continue
        txt = txt.replace(de, para, 1)

        if extra:
            if txt.count(extra[0]) != 1:
                print("  ?     %-42s SEGUNDA ANCORA NAO BATE (%d)" % (nome, txt.count(extra[0])))
                falhas.append(nome)
                continue
            txt = txt.replace(extra[0], extra[1], 1)

        escrever(destino, arquivo, txt)
        try:
            saida = rodar(destino)
        finally:
            # O ORIGINAL VOLTA SEMPRE, inclusive se a rodada estourar: uma sabotagem que vaza para
            # a proxima faria a suite acusar defeitos que nao existem.
            escrever(destino, arquivo, originais[arquivo])

        chegou_ao_fim = FIM in saida

        if label is None:
            if chegou_ao_fim:
                print("  FALHA %-42s o harness passou inteiro com o defeito" % nome)
                falhas.append(nome)
            else:
                print("  ok    %-42s parou o harness" % nome)
            continue

        esperado = "  ERRO  " + label
        if esperado in saida:
            print("  ok    %-42s reprovou em: %s" % (nome, label))
        else:
            outro = [l for l in saida.splitlines() if l.startswith("  ERRO")]
            print("  FALHA %-42s esperava reprovar em %r; veio %r" % (nome, label, outro[:1]))
            falhas.append(nome)
finally:
    shutil.rmtree(base, ignore_errors=True)

print()
print("sabotagens que NAO foram pegas: %d" % len(falhas))
for f in falhas:
    print("  - " + f)
sys.exit(1 if falhas else 0)

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
]


def rodar(tmp):
    r = subprocess.run([LUA, "tests/harness.lua"], cwd=tmp,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return r.stdout.decode("utf-8", "replace")


falhas = []
for entrada in SABOTAGENS:
    # A sexta posicao (opcional) e uma SEGUNDA substituicao no mesmo arquivo, para quando a
    # propriedade tem mais de uma defesa e sabotar so uma nao reprova nada.
    nome, arquivo, de, para, label = entrada[:5]
    extra = entrada[5] if len(entrada) > 5 else None

    tmp = tempfile.mkdtemp(prefix="sab_")
    shutil.copytree(SRC, os.path.join(tmp, "a"), dirs_exist_ok=True)
    tmp = os.path.join(tmp, "a")

    alvo = os.path.join(tmp, arquivo)
    txt = io.open(alvo, encoding="utf-8").read().replace("\r\n", "\n")
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

    io.open(alvo, "w", encoding="utf-8", newline="\n").write(txt)

    saida = rodar(tmp)
    fim = "Tudo carregou e rodou sem erro de Lua." in saida

    if label is None:
        print("  --    %-42s %s" % (nome, "passou inteiro" if fim else "quebrou algo"))
        continue

    esperado = "  ERRO  " + label
    if esperado in saida:
        print("  ok    %-42s reprovou em: %s" % (nome, label))
    else:
        outro = [l for l in saida.splitlines() if l.startswith("  ERRO")]
        print("  FALHA %-42s esperava reprovar em %r; veio %r" % (nome, label, outro[:1]))
        falhas.append(nome)

print()
print("sabotagens que NAO foram pegas: %d" % len(falhas))
for f in falhas:
    print("  - " + f)
sys.exit(1 if falhas else 0)

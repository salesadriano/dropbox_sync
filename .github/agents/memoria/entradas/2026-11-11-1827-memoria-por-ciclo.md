---
id: 2026-11-11-1827-memoria-por-ciclo
tipo: decisao
escopo: projeto
titulo: Memoria do sync gravada ao fim de cada ciclo; gravacao final so em execucao sem ciclo falho
data: 2026-11-11
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, dba
status: ativa
ref: docs/reviews/2026-11-11-1827-registro-sync-ciclos-exclusao-indevida.md
---

Decisao do solicitante (2026-11-11, log `docs/prompts/2026-11-11_1827_sync-ciclos-exclusao-indevida.md`), emenda `RF-38(b)` sobre `2026-10-31-1200-sync-em-blocos`: no `sync` em ciclos, a memoria (`lib/state`, `memoria-*`) e gravada ao fim de cada ciclo com o mapa inteiro (visto ate ali mais as entradas carregadas dos diretorios ainda nao processados); so a gravacao final (so visitadas) remove o que sumiu da origem; travessia parcial e simulacao nao gravam; o cursor/retrato do `--receber` continua so no fim (RF-192).

Decisoes do Tech Lead: memoria descartada nao grava por ciclo (so no fim, como antes, RF-41(f)); em modo de ciclos com ciclo falho NAO ha gravacao final (achado QA-F101-01: a final depois de ciclo falho perdia as entradas dos diretorios nao processados).

O relato de origem (arquivos de ciclo anterior marcados `a apagar` no ciclo 2, `sync --enviar --espelhar`) nao foi reproduzido com duble de remoto mutavel; a regressao ficou coberta por teste e a causa segue aberta ate o solicitante trazer a saida do ciclo 2.

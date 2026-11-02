---
id: 2026-11-02-1200-aceite-testes-qa-porte-bash-42
tipo: aceite
escopo: projeto
titulo: Solicitante aceita as suites do QA ajustadas para a linha legada bash 4.2 e a suite nova de exclusao sem localidade
data: 2026-11-02
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-11-01-1200-validacao-qa-porte-bash-42.md
---

Aceite do solicitante pela regra 12 (AskUserQuestion, 2026-11-02, "Accept the suites (Recommended)"), na demanda `suporte-bash-42`, PARTE B (branch `feature/porte-bash-42`, linha `support/bash-4.2`). Mudancas so de construcao incompativel com o bash 4.2, pulo de ambiente (localidade `C.UTF-8`, `python3`, `openssl`, `env --default-signal`) e harness (fifo e `stty sane` para o `script` 2.23, troca de inode por create+mv); nenhum assert removido. A suite nova prova que nada nao ASCII e apagado sem a localidade (`QA-B42-01`, `DIV-391`).

Na mesma rodada o solicitante decidiu que o retorno da correcao `QA-B42-01` a linha principal sera demanda propria, depois da PARTE B, entrando na release 2.3.0.

sha256 (arvore aceita):

- `tests/integracao/qa_cache_unico_p3_test.sh`: `9bcba5854dd58dd9638ab9f8b9f192941f6864f3a10e762599bcdd944c6bd054`
- `tests/integracao/qa_compartilhamento_b5_test.sh`: `9379eff75d96f3c796c4225b03b643e1747d2d9b6d9c45c3827c85081c6d274a`
- `tests/integracao/qa_confinamento_remoto_b1b_test.sh`: `a124134826f79467a7afbf75c4ba24242daa037b8d73f65d383b2b947e88e2a6`
- `tests/integracao/qa_consulta_diagnostico_b1_test.sh`: `45ebf4dc751a3d30ada66e4e92fab297e55e53d057846fe28b8dd90827154312`
- `tests/integracao/qa_cursor_b7b_test.sh`: `e762c6837d92258d6ffe9b0145b5c727f2c2daf458155e8d83307061b3436588`
- `tests/integracao/qa_debug_transferencias_b12_test.sh`: `12ba9c02cc5909f3e54e8dbd540808c7f4dc7d6a4f2140604a15b0441ec50a14`
- `tests/integracao/qa_docs_aliases_p4_test.sh`: `74c8dceff3c1557fc25e7b83f808651f0b8f0ee5ece0d03f4baa789c89cbae91`
- `tests/integracao/qa_exclusao_sem_localidade_b42_test.sh`: `649577d9dd49cda804016b18d931ff6ca55b5b44168da0360d7f631e9e816c3b`
- `tests/integracao/qa_filtros_banda_b4_test.sh`: `cb09104cad84bb330a72448f7d092119f526329be732e3d46d984b867ed63dbd`
- `tests/integracao/qa_freebsd_b13_test.sh`: `06206b91b87f2107604b95f917ea03bd82b5a5d4bf046b202581611cd662adf3`
- `tests/integracao/qa_instalador_linha_b22_test.sh`: `59486514e44cd4cc64778e6dab1311947cc09c27225a215ce73495fd1f2b4e98`
- `tests/integracao/qa_leitura_exata_b14_test.sh`: `34be413186db1773750ce5f46a59397b5220c4a9acb78585f7f27b4aa1e3f52e`
- `tests/integracao/qa_paralelo_upload_b19_test.sh`: `9ea24e3e6fb231d968e2d12f1c402d4fa26b94050295f7d780ebfc66f3a1ecd4`
- `tests/integracao/qa_perfis_b8_test.sh`: `2aa733ce1f590f551fb92a3f68f6ecd529721c0eea61e0257898006f06136df4`
- `tests/integracao/qa_recuperacao_b3_test.sh`: `3d9ccd0b7a6cb3f2e309098dec8172ab67d3f5a28f27a3ec26655ded042ecd02`
- `tests/integracao/qa_regex_portavel_b17_test.sh`: `f4f82122bea265da7efaeed4d8b7d4f8de7a8a809a432824ef624bc7ea1ce18d`
- `tests/integracao/qa_retencao_b6_test.sh`: `0c0a8a2870cc2b397d75b1d971b4aa3953a704134bba2396906401eb11c4f611`
- `tests/integracao/qa_retomada_b7a_test.sh`: `6215eeec64face1d759d0da64db4509b8644f0fb31038ee52e363f8df8d096dd`
- `tests/integracao/qa_robustez_rede_p2_test.sh`: `110d26b7c7063a5a3bee64ecefab0a5f282e8a6a0c644d605ea2faada126b6a8`
- `tests/integracao/qa_sync_blocos_b21_test.sh`: `e2fcbcd6cdeae90d59ecb23171615ba898cc025586af7c54d872f818526c72b6`
- `tests/integracao/qa_trava_tmp_b2_test.sh`: `4e414ac5d52218976ff921bd5b6649100f79556dc6699efc6b12cdb31d9e12ba`

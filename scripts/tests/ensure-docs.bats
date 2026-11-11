#!/usr/bin/env bats
# Testes de scripts/ensure-docs.sh (estrutura docs/: nunca apaga nem sobrescreve).
# Esqueleto da auditoria 2026-11-08 (secao 7 de docs/reviews/2026-11-08-1640-execucao-da-auditoria.md).

@test "segunda execucao nao sobrescreve README existente e imprime estrutura docs completa" {
  skip "pendente: provar que README com conteudo proprio sobrevive a nova execucao e que a saida e 'estrutura docs/ completa'; e que a criacao do zero cria docs, prompts, reviews e sources com README e imprime 'criado:' por item"
}

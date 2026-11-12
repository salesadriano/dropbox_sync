#!/usr/bin/env bats
# Testes de scripts/validate-skill-links.sh (gate da pipeline que confere referencias locais das skills).
# Esqueletos da auditoria 2026-11-08 (secao 7 de docs/reviews/2026-11-08-1640-execucao-da-auditoria.md):
# cada caso e `skip "pendente: ..."` ate o teste ser escrito.

@test "referencia local inexistente em SKILL.md sai 1 e acusa Broken local reference em stderr" {
  skip "pendente: provar exit 1 e 'Broken local reference: ... -> references/x.md' quando references/x.md nao existe"
}

@test "arvore sem referencia quebrada sai 0 e imprime All local skill references are valid" {
  skip "pendente: provar exit 0 e a mensagem de sucesso numa arvore valida"
}

@test "referencia com glob ou ancora e ignorada ou normalizada sem falso positivo" {
  skip "pendente: provar que referencia com *, ? ou #secao nao acusa falso positivo"
}

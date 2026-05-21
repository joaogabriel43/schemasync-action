# SchemaSync Action Architecture

### ADR-001: Composite Action for Simplicity
**Status:** Aceito
**Data:** 2026-05
**Contexto:** O SchemaSync precisa de uma action leve para integrar o motor com o GitHub PRs.
**Decisão:** Usar Action do tipo `composite` que dependa apenas de `bash`, `curl`, `jq` e `git`. Proibido Node.js ou Docker.
**Justificativa:** Execução super rápida em runners hospedados (ubuntu-latest já possui as dependências). Zero steps de build ou docker-pull reduz latência no CI/CD.

### ADR-002: Idempotência de Comentários
**Status:** Aceito
**Data:** 2026-05
**Contexto:** Evitar flood de comentários em PRs a cada novo commit.
**Decisão:** O script pesquisa nos comentários existentes da issue/PR por "## 🛡️ SchemaSync Report" usando a GitHub REST API e faz `PATCH` (update) se existir, ou `POST` se for a primeira vez.

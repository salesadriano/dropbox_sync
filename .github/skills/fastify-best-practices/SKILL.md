---
name: fastify-best-practices
description: "Fastify (Node.js) implementation skill for routes, plugins, JSON Schema validation, hooks, serialization, error handling, Pino logging, WebSockets, and production deployment in TypeScript or JavaScript. Use when the stack is explicitly Fastify. Prefer nodejs-best-practices for framework-agnostic Node.js decisions and nestjs-best-practices when the stack is NestJS. Trigger terms: Fastify, fastify.config, server.ts, app.ts, reply.from, inject()."
metadata:
  tags: fastify, nodejs, typescript, backend, api, server, http
  source: mcollina/skills
---

# Fastify Best Practices

## Security Handoff

This skill does not replace security hardening.

- If work touches authentication, authorization, secrets, sensitive data, session/cookies, CSP/CORS, or API exposure, also apply `security-best-practices` and `api-security-best-practices`.
- Never include secrets, tokens, credentials, or private keys in examples, fixtures, diagrams, logs, or generated artifacts.
- `rules/cors-security.md` and `rules/authentication.md` cover the Fastify mechanics only; the security posture itself stays owned by the security skills above.

## Scope Boundary

Use this skill when the project is a Fastify server.

Prefer [`nodejs-best-practices`](../nodejs-best-practices/SKILL.md) for framework-agnostic Node.js runtime, async, and architecture decisions, and [`nestjs-best-practices`](../nestjs-best-practices/SKILL.md) when the stack is NestJS. For test protocol and coverage gates, `rules/testing.md` describes the Fastify `inject()` mechanics only — the mandatory delivery protocol stays in [`protocolo-tdd`](../protocolo-tdd/SKILL.md).

## When to use

Use this skill when you need to:
- Develop backend applications using Fastify
- Implement Fastify plugins and route handlers
- Get guidance on Fastify architecture and patterns
- Use TypeScript with Fastify (strip types)
- Implement testing with Fastify's inject method
- Configure validation, serialization, and error handling

## Quick Start

A minimal, runnable Fastify server to get started immediately:

```ts
import Fastify from 'fastify'

const app = Fastify({ logger: true })

app.get('/health', async (request, reply) => {
  return { status: 'ok' }
})

const start = async () => {
  await app.listen({ port: 3000, host: '0.0.0.0' })
}
start()
```

## Recommended Reading Order for Common Scenarios

- **New to Fastify?** Start with `plugins.md` → `routes.md` → `schemas.md`
- **Adding authentication:** `plugins.md` → `hooks.md` → `authentication.md`
- **Improving performance:** `schemas.md` → `serialization.md` → `performance.md`
- **Setting up testing:** `routes.md` → `testing.md`
- **Going to production:** `logging.md` → `configuration.md` → `deployment.md`

## How to use

Read individual rule files for detailed explanations and code examples:

- [rules/plugins.md](rules/plugins.md) - Plugin development and encapsulation
- [rules/routes.md](rules/routes.md) - Route organization and handlers
- [rules/schemas.md](rules/schemas.md) - JSON Schema validation
- [rules/error-handling.md](rules/error-handling.md) - Error handling patterns
- [rules/hooks.md](rules/hooks.md) - Hooks and request lifecycle
- [rules/authentication.md](rules/authentication.md) - Authentication and authorization
- [rules/testing.md](rules/testing.md) - Testing with inject()
- [rules/performance.md](rules/performance.md) - Performance optimization
- [rules/logging.md](rules/logging.md) - Logging with Pino
- [rules/typescript.md](rules/typescript.md) - TypeScript integration
- [rules/decorators.md](rules/decorators.md) - Decorators and extensions
- [rules/content-type.md](rules/content-type.md) - Content type parsing
- [rules/serialization.md](rules/serialization.md) - Response serialization
- [rules/cors-security.md](rules/cors-security.md) - CORS and security headers
- [rules/websockets.md](rules/websockets.md) - WebSocket support
- [rules/database.md](rules/database.md) - Database integration patterns
- [rules/configuration.md](rules/configuration.md) - Application configuration
- [rules/deployment.md](rules/deployment.md) - Production deployment
- [rules/http-proxy.md](rules/http-proxy.md) - HTTP proxying and reply.from()

## Core Principles

- **Encapsulation**: Fastify's plugin system provides automatic encapsulation
- **Schema-first**: Define schemas for validation and serialization
- **Performance**: Fastify is optimized for speed; use its features correctly
- **Async/await**: All handlers and hooks support async functions
- **Minimal dependencies**: Prefer Fastify's built-in features and official plugins

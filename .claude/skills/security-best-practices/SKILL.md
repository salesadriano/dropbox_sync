---
name: security-best-practices
description: Implement web application and browser-facing security baselines such as HTTPS, headers, cookies, CORS, CSP, secret handling, and common vulnerability prevention. Use for cross-cutting hardening; prefer api-security-best-practices when the task is specifically API authentication, authorization, validation, or throttling.
metadata:
  tags: security, HTTPS, CORS, XSS, SQL-injection, CSRF, OWASP
  platforms: Claude, ChatGPT, Gemini
---


# Security Best Practices

> **Scope boundary:** Use this skill for browser-facing and cross-cutting web hardening such as HTTPS, cookies, security headers, CSP, CORS, CSRF, secrets handling, and safe output handling. For API-specific authentication, authorization, schema validation, quotas, throttling, and rate limiting, use [`api-security-best-practices`](../api-security-best-practices/SKILL.md). For framework-specific hardening, prefer the corresponding framework skill.


## When to use this skill

- **New project**: consider security from the start
- **Security audit**: inspect and fix vulnerabilities
- **Browser-facing app**: harden cookies, headers, CSP, CORS, and CSRF
- **Compliance**: comply with GDPR, PCI-DSS, etc.

## Instructions

### Step 1: Enforce HTTPS and security headers

**Express.js security middleware**:
```typescript
import express from 'express';
import helmet from 'helmet';
import crypto from 'crypto';

const app = express();

// Generate a fresh cryptographically random nonce for every request.
// NEVER use a static/hardcoded string — a fixed nonce is equivalent to no nonce
// and will be flagged by CSP auditing tools as a false sense of security.
app.use((req, res, next) => {
  res.locals.cspNonce = crypto.randomBytes(16).toString('base64');
  next();
});

// Helmet: automatically set security headers
app.use((req, res, next) =>
  helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        // Use a function so helmet picks up the per-request nonce from res.locals
        scriptSrc: ["'self'", `'nonce-${res.locals.cspNonce}'`, "https://trusted-cdn.com"],
        styleSrc: ["'self'", `'nonce-${res.locals.cspNonce}'`],
        imgSrc: ["'self'", "data:", "https:"],
        connectSrc: ["'self'", "https://api.example.com"],
        fontSrc: ["'self'", "https:", "data:"],
        objectSrc: ["'none'"],
        mediaSrc: ["'self'"],
        frameSrc: ["'none'"],
      },
    },
    hsts: {
      maxAge: 31536000,
      includeSubDomains: true,
      preload: true
    }
  })(req, res, next)
);

// Enforce HTTPS
app.use((req, res, next) => {
  if (process.env.NODE_ENV === 'production' && !req.secure) {
    return res.redirect(301, `https://${req.headers.host}${req.url}`);
  }
  next();
});

```

### Step 2: Input validation (SQL Injection, XSS prevention)

**Joi validation**:
```typescript
import Joi from 'joi';

const userSchema = Joi.object({
  email: Joi.string().email().required(),
  password: Joi.string().min(8).pattern(/^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]/).required(),
  name: Joi.string().min(2).max(50).required()
});

app.post('/api/users', async (req, res) => {
  // 1. Validate input
  const { error, value } = userSchema.validate(req.body);

  if (error) {
    return res.status(400).json({ error: error.details[0].message });
  }

  // 2. Prevent SQL Injection: Parameterized Queries
  // ❌ Bad example
  // db.query(`SELECT * FROM users WHERE email = '${email}'`);

  // ✅ Good example
  const user = await db.query('SELECT * FROM users WHERE email = ?', [value.email]);

  // 3. Prevent XSS: Output Encoding
  // React/Vue escape automatically; otherwise use a library
  import DOMPurify from 'isomorphic-dompurify';
  const sanitized = DOMPurify.sanitize(userInput);

  res.json({ user: sanitized });
});
```

### Step 3: Prevent CSRF

**CSRF Token**:
```typescript
import csrf from 'csurf';
import cookieParser from 'cookie-parser';

app.use(cookieParser());

// CSRF protection
const csrfProtection = csrf({ cookie: true });

// Provide CSRF token
app.get('/api/csrf-token', csrfProtection, (req, res) => {
  res.json({ csrfToken: req.csrfToken() });
});

// Validate CSRF on all POST/PUT/DELETE requests
app.post('/api/*', csrfProtection, (req, res, next) => {
  next();
});

// Use on the client
// fetch('/api/users', {
//   method: 'POST',
//   headers: {
//     'CSRF-Token': csrfToken
//   },
//   body: JSON.stringify(data)
// });
```

### Step 4: Manage secrets

**.env (never commit)**:
```bash
# Database
DATABASE_URL=postgresql://user:password@localhost:5432/mydb

# JWT
ACCESS_TOKEN_SECRET=your-super-secret-access-token-key-min-32-chars
REFRESH_TOKEN_SECRET=your-super-secret-refresh-token-key-min-32-chars

# API Keys
STRIPE_SECRET_KEY=sk_test_xxx
SENDGRID_API_KEY=SG.xxx
```

**Kubernetes Secrets**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: myapp-secrets
type: Opaque
stringData:
  database-url: postgresql://user:password@postgres:5432/mydb
  jwt-secret: your-jwt-secret
```

```typescript
// Read from environment variables
const dbUrl = process.env.DATABASE_URL;
if (!dbUrl) {
  throw new Error('DATABASE_URL environment variable is required');
}
```

### Step 5: Hand off API auth and throttling to the API security skill

For API authentication, authorization, token rotation, quotas, throttling, and DDoS controls at the API boundary, use [`api-security-best-practices`](../api-security-best-practices/SKILL.md). Keep this skill focused on browser-facing and cross-cutting web hardening.

## Constraints

### Required rules (MUST)

1. **HTTPS Only**: HTTPS required in production
2. **Separate secrets**: manage via environment variables; never hardcode in code
3. **Input Validation**: validate all user input
4. **Parameterized Queries**: prevent SQL Injection
5. **Dynamic CSP nonces**: if you allow inline scripts or styles, generate a fresh nonce per request

### Prohibited items (MUST NOT)

1. **No eval()**: code injection risk
2. **No direct innerHTML**: XSS risk
3. **No committing secrets**: never commit .env files

## OWASP Top 10 checklist

```markdown
- [ ] A01: Broken Access Control - RBAC, authorization checks
- [ ] A02: Cryptographic Failures - HTTPS, encryption
- [ ] A03: Injection - Parameterized Queries, Input Validation
- [ ] A04: Insecure Design - Security by Design
- [ ] A05: Security Misconfiguration - Helmet, change default passwords
- [ ] A06: Vulnerable Components - npm audit, regular updates
- [ ] A07: Authentication Failures - strong auth, MFA
- [ ] A08: Data Integrity Failures - signature validation, CSRF prevention
- [ ] A09: Logging Failures - security event logging
- [ ] A10: SSRF - validate outbound requests
```

## Best practices

1. **Principle of Least Privilege**: grant minimal privileges
2. **Defense in Depth**: layered security
3. **Security Audits**: regular security reviews

## References

- [OWASP Top 10 Quick Reference](references/owasp-top10.md) — per-category code examples and checklists
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [helmet.js](https://helmetjs.github.io/)
- [Security Checklist](https://github.com/shieldfy/API-Security-Checklist)
- [API Security Best Practices](../api-security-best-practices/SKILL.md) — API auth, authz, throttling, quotas, and token handling

## Metadata

### Version
- **Current version**: 1.0.0
- **Last updated**: 2025-01-01
- **Compatible platforms**: Claude, ChatGPT, Gemini

### Related skills
- [api-security-best-practices](../api-security-best-practices/SKILL.md)
- [best-practices](../best-practices/SKILL.md)

### Tags
`#security` `#OWASP` `#HTTPS` `#CORS` `#XSS` `#SQL-injection` `#CSRF` `#infrastructure`

## Examples

### Example 1: Basic usage
<!-- Add example content here -->

### Example 2: Advanced usage
<!-- Add advanced example content here -->

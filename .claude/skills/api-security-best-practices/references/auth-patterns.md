# API Security — Authentication & Authorization Patterns

## JWT Best Practices

```typescript
// ✅ Short-lived access token + long-lived refresh token
const ACCESS_EXPIRY = '15m';
const REFRESH_EXPIRY = '7d';

// ✅ Use RS256 (asymmetric) in production — allows public key distribution
import jwt from 'jsonwebtoken';

const token = jwt.sign(
  { sub: userId, role: user.role }, // minimal payload — no PII
  privateKey,
  { algorithm: 'RS256', expiresIn: ACCESS_EXPIRY, issuer: 'myapp' }
);

// ✅ Validate all claims
jwt.verify(token, publicKey, {
  algorithms: ['RS256'],
  issuer: 'myapp',
  audience: 'myapp-api'
});
```

## API Key Authentication

```typescript
// ✅ Store hashed API keys — never the raw key
import crypto from 'crypto';

function hashApiKey(key: string): string {
  return crypto.createHash('sha256').update(key).digest('hex');
}

// ✅ Prefix for identification without exposure (e.g. "sk_live_xxx")
function generateApiKey(): { key: string; hash: string } {
  const raw = `sk_live_${crypto.randomBytes(24).toString('base64url')}`;
  return { key: raw, hash: hashApiKey(raw) };
}

// Lookup by hash — O(1), safe to store in logs
const apiKey = await db.apiKey.findFirst({ where: { hash: hashApiKey(incoming) } });
```

## OAuth 2.0 Patterns

```typescript
// ✅ PKCE for public clients (SPA, mobile)
import crypto from 'crypto';

function generatePKCE() {
  const verifier = crypto.randomBytes(32).toString('base64url');
  const challenge = crypto
    .createHash('sha256')
    .update(verifier)
    .digest('base64url');
  return { verifier, challenge };
}

// ✅ Validate state parameter to prevent CSRF
const state = crypto.randomBytes(16).toString('hex');
// Store in session, verify on callback
```

## Authorization Patterns

```typescript
// ✅ Attribute-Based Access Control (ABAC) — flexible and testable
type Permission = 'read' | 'write' | 'delete' | 'admin';

function can(user: User, action: Permission, resource: Resource): boolean {
  if (user.role === 'admin') return true;
  if (resource.ownerId === user.id) return action !== 'admin';
  if (resource.isPublic) return action === 'read';
  return false;
}

// ✅ Resource-scoped queries — never fetch then filter
async function getUserDocuments(userId: string) {
  return db.document.findMany({
    where: { ownerId: userId }  // DB enforces access — not application code
  });
}
```

## Rate Limiting by Tier

```typescript
// ✅ Tiered limits: anonymous < authenticated < premium
const limits = {
  anonymous: { windowMs: 60_000, max: 10 },
  authenticated: { windowMs: 60_000, max: 100 },
  premium: { windowMs: 60_000, max: 1000 }
};

function getRateLimit(req: Request) {
  const tier = req.user?.plan ?? 'anonymous';
  return rateLimit(limits[tier]);
}
```

## Token Security Checklist

```
□ Access tokens expire in ≤ 15 minutes
□ Refresh tokens are rotated on each use
□ Refresh tokens are revoked on logout and password change
□ API keys are hashed before storage
□ JWT algorithm is explicitly set (never accept 'none')
□ PKCE used for all public OAuth clients
□ State parameter validated on OAuth callback
□ Tokens are never logged or included in URLs
```

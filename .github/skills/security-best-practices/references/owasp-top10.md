# OWASP Top 10 Quick Reference

## A01 — Broken Access Control

**Risk**: Users act outside their intended permissions.

```typescript
// ✅ Always verify ownership — never trust client-supplied IDs alone
app.get('/api/documents/:id', authenticate, async (req, res) => {
  const doc = await db.document.findFirst({
    where: { id: req.params.id, ownerId: req.user.id } // scope to user
  });
  if (!doc) return res.status(404).json({ error: 'Not found' });
  res.json(doc);
});
```

## A02 — Cryptographic Failures

**Risk**: Sensitive data exposed due to weak or missing encryption.

```typescript
// ✅ Hash passwords with bcrypt (cost factor ≥ 12)
import bcrypt from 'bcrypt';
const hash = await bcrypt.hash(password, 12);

// ✅ Encrypt sensitive fields at rest
import crypto from 'crypto';
const key = Buffer.from(process.env.ENCRYPTION_KEY!, 'hex'); // 32 bytes
const iv = crypto.randomBytes(16);
const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
```

## A03 — Injection

**Risk**: Attacker-controlled input alters query logic.

```typescript
// ❌ Never interpolate user input
db.query(`SELECT * FROM users WHERE email = '${email}'`);

// ✅ Always use parameterized queries
db.query('SELECT * FROM users WHERE email = $1', [email]);

// ✅ ORM (Prisma, TypeORM) handles parameterization automatically
const user = await prisma.user.findUnique({ where: { email } });
```

## A04 — Insecure Design

**Risk**: Missing or flawed security controls in design phase.

**Checklist**:
- [ ] Threat model created before implementation
- [ ] Rate limiting on all public endpoints
- [ ] Business logic abuse scenarios documented
- [ ] Multi-factor authentication for sensitive operations

## A05 — Security Misconfiguration

**Risk**: Insecure defaults, error messages exposing stack traces, open cloud storage.

```typescript
// ✅ Never expose error details in production
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  console.error(err); // log internally
  res.status(500).json({
    error: process.env.NODE_ENV === 'production' ? 'Internal error' : err.message
  });
});
```

## A06 — Vulnerable and Outdated Components

```bash
# Audit dependencies regularly
npm audit
npm audit fix

# Check for known vulnerabilities
npx snyk test
```

## A07 — Identification and Authentication Failures

```typescript
// ✅ Lock account after repeated failures
const MAX_ATTEMPTS = 5;
const LOCKOUT_MINUTES = 15;

// ✅ Use secure session configuration
app.use(session({
  secret: process.env.SESSION_SECRET!,
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: true,      // HTTPS only
    httpOnly: true,    // no JS access
    sameSite: 'strict',
    maxAge: 15 * 60 * 1000 // 15 minutes
  }
}));
```

## A08 — Software and Data Integrity Failures

```typescript
// ✅ Verify webhook signatures
import crypto from 'crypto';

function verifyWebhookSignature(payload: string, signature: string, secret: string): boolean {
  const expected = crypto
    .createHmac('sha256', secret)
    .update(payload)
    .digest('hex');
  return crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected));
}
```

## A09 — Security Logging and Monitoring Failures

```typescript
// ✅ Log security events with enough context
const securityLog = {
  event: 'AUTH_FAILURE',
  userId: req.body.email,
  ip: req.ip,
  userAgent: req.headers['user-agent'],
  timestamp: new Date().toISOString()
};
logger.warn(securityLog);
```

## A10 — Server-Side Request Forgery (SSRF)

```typescript
// ✅ Allowlist outbound URLs
const ALLOWED_HOSTS = ['api.partner.com', 'hooks.slack.com'];

function isAllowedUrl(url: string): boolean {
  const { hostname } = new URL(url);
  return ALLOWED_HOSTS.includes(hostname);
}

// ✅ Block internal IP ranges
import isPrivateIp from 'private-ip';
if (isPrivateIp(resolvedIp)) {
  throw new Error('SSRF attempt blocked');
}
```

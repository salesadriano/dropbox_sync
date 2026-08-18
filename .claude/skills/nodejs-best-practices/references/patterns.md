# Node.js Best Practices — Patterns Quick Reference

## Error Handling

```typescript
// ✅ Distinguish operational errors from programmer errors
class AppError extends Error {
  constructor(
    public message: string,
    public statusCode: number,
    public isOperational = true
  ) {
    super(message);
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

// ✅ Centralized error handler
process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception', err);
  if (!err.isOperational) process.exit(1); // only exit for programmer errors
});

process.on('unhandledRejection', (reason) => {
  throw reason; // convert to uncaughtException
});
```

## Async Patterns

```typescript
// ✅ Always await or return promises — never fire and forget
async function processJob(job: Job): Promise<void> {
  await saveResult(await processItem(job.item)); // chained awaits
}

// ✅ Concurrent operations with Promise.all
const [users, orders] = await Promise.all([
  db.user.findMany(),
  db.order.findMany()
]);

// ✅ Sequential with for...of (not forEach with async)
for (const item of items) {
  await processItem(item); // sequential — each waits for previous
}
```

## Stream Processing

```typescript
import { pipeline } from 'stream/promises';
import { createReadStream, createWriteStream } from 'fs';
import { createGzip } from 'zlib';

// ✅ pipeline() handles backpressure and cleanup automatically
await pipeline(
  createReadStream('input.csv'),
  new TransformStream(),
  createGzip(),
  createWriteStream('output.csv.gz')
);
```

## Configuration

```typescript
// ✅ Validate config at startup — fail fast if missing
import { z } from 'zod';

const configSchema = z.object({
  PORT: z.coerce.number().default(3000),
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(32),
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development')
});

export const config = configSchema.parse(process.env);
```

## Graceful Shutdown

```typescript
// ✅ Handle SIGTERM for container orchestration
let server: http.Server;

async function shutdown() {
  console.log('Shutting down...');
  await new Promise<void>((resolve) => server.close(() => resolve()));
  await db.disconnect();
  process.exit(0);
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
```

## Worker Threads for CPU-Intensive Work

```typescript
import { Worker, isMainThread, parentPort } from 'worker_threads';

// ✅ Never block the event loop — offload CPU work to workers
if (isMainThread) {
  const worker = new Worker(__filename, { workerData: { data: heavyData } });
  worker.on('message', (result) => console.log('Done:', result));
} else {
  const result = heavyCpuWork(parentPort!);
  parentPort!.postMessage(result);
}
```

## Performance Checklist

```
□ Enable HTTP keep-alive on outbound connections
□ Set NODE_OPTIONS=--max-old-space-size for memory-intensive apps
□ Use cluster module or PM2 for multi-core utilization
□ Profile with clinic.js before optimizing
□ Cache DNS lookups for high-frequency external calls
□ Prefer Buffer over string for binary data
```

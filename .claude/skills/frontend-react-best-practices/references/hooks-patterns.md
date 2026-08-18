# React Hooks Patterns Quick Reference

## Data Fetching

```tsx
// ✅ Custom hook encapsulates fetch logic
function useUser(id: string) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let cancelled = false; // prevent stale state on unmount
    setLoading(true);
    fetchUser(id)
      .then((data) => { if (!cancelled) setUser(data); })
      .catch((err) => { if (!cancelled) setError(err); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [id]);

  return { user, loading, error };
}
```

## Avoiding Stale Closures

```tsx
// ✅ Use useRef for stable callbacks that need latest state
function useInterval(callback: () => void, delay: number) {
  const savedCallback = useRef(callback);

  useEffect(() => { savedCallback.current = callback; }, [callback]);

  useEffect(() => {
    const id = setInterval(() => savedCallback.current(), delay);
    return () => clearInterval(id);
  }, [delay]);
}
```

## Derived State — No useEffect

```tsx
// ❌ Avoid: effect just to compute derived state
useEffect(() => {
  setFullName(`${firstName} ${lastName}`);
}, [firstName, lastName]);

// ✅ Compute during render — no effect needed
const fullName = `${firstName} ${lastName}`;

// ✅ useMemo only when computation is expensive
const sortedItems = useMemo(
  () => items.slice().sort((a, b) => a.name.localeCompare(b.name)),
  [items]
);
```

## Context — Split to Avoid Re-renders

```tsx
// ✅ Separate read and dispatch contexts
const UserStateCtx = createContext<UserState | null>(null);
const UserDispatchCtx = createContext<Dispatch | null>(null);

// Components that only dispatch never re-render on state changes
function AddButton() {
  const dispatch = useContext(UserDispatchCtx)!;
  return <button onClick={() => dispatch({ type: 'add' })}>Add</button>;
}
```

## useReducer for Complex State

```tsx
// ✅ useReducer when next state depends on multiple previous values
type Action =
  | { type: 'increment' }
  | { type: 'decrement' }
  | { type: 'reset'; payload: number };

function counter(state: number, action: Action): number {
  switch (action.type) {
    case 'increment': return state + 1;
    case 'decrement': return state - 1;
    case 'reset': return action.payload;
  }
}

const [count, dispatch] = useReducer(counter, 0);
```

## Performance Checklist

```
□ Avoid creating new objects/arrays in JSX props — memoize with useMemo
□ Stable callbacks with useCallback when passing to memoized children
□ Keys are stable IDs — never array index for dynamic lists
□ Context values are memoized to prevent consumer re-renders
□ Code-split routes and heavy components with React.lazy + Suspense
□ List virtualization (react-window) for >100 items
```

## Common Pitfalls

```tsx
// ❌ Missing cleanup in useEffect
useEffect(() => {
  const subscription = subscribe(id);
  // forgot: return () => subscription.unsubscribe();
}, [id]);

// ❌ Object dependency causes infinite loop
useEffect(() => { fetchData(options); }, [options]); // options = {} recreated every render

// ✅ Destructure to stable primitives
const { page, limit } = options;
useEffect(() => { fetchData({ page, limit }); }, [page, limit]);
```

# Python Best Practices — Patterns Quick Reference

## Type Safety

```python
# Use dataclasses or Pydantic for structured data — never raw dicts
from dataclasses import dataclass
from pydantic import BaseModel

@dataclass(frozen=True)  # immutable value object
class UserId:
    value: int

class UserCreate(BaseModel):
    name: str
    email: str
    age: int

# Use TypeAlias for domain clarity
from typing import TypeAlias
UserId: TypeAlias = int
```

## Error Handling

```python
# Explicit exception hierarchy — never catch bare Exception in production
class AppError(Exception): pass
class NotFoundError(AppError): pass
class ValidationError(AppError): pass

# Use Result type pattern for recoverable errors
from typing import Union

def find_user(user_id: int) -> Union['User', NotFoundError]:
    user = db.get(user_id)
    return user if user else NotFoundError(f"User {user_id} not found")
```

## Functional Patterns

```python
# Prefer list comprehensions over map/filter for readability
emails = [u.email for u in users if u.active]

# Use generators for large collections — avoid materializing entire sequences
def active_users(users):
    return (u for u in users if u.active)

# Partial application for dependency injection
from functools import partial

def send_email(smtp_client, to: str, subject: str, body: str): ...
send_notification = partial(send_email, smtp_client)
```

## Context Managers

```python
# Always use context managers for resources
with open('file.txt') as f:
    content = f.read()

# Custom context manager for transactions
from contextlib import contextmanager

@contextmanager
def transaction(session):
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
```

## Immutability

```python
from typing import Final, NamedTuple

MAX_RETRIES: Final = 3  # constant — never reassigned

class Point(NamedTuple):  # immutable tuple subclass
    x: float
    y: float

p = Point(1.0, 2.0)
# p.x = 5.0  ← AttributeError
```

## Module Organization

```
src/
  myapp/
    __init__.py
    domain/          # pure business logic — no I/O
      models.py
      services.py
    infrastructure/  # databases, APIs, external services
      db.py
      email.py
    api/             # HTTP layer
      routes.py
      schemas.py
    core/            # config, exceptions, utilities
      config.py
      exceptions.py
```

## Testing Patterns

```python
import pytest
from unittest.mock import MagicMock, patch

# Use fixtures for shared setup
@pytest.fixture
def user_service(db_session):
    return UserService(db=db_session)

# Parametrize for multiple cases
@pytest.mark.parametrize("email,valid", [
    ("user@example.com", True),
    ("not-an-email", False),
    ("", False),
])
def test_email_validation(email, valid):
    assert validate_email(email) == valid

# Mock external dependencies at the boundary
def test_send_welcome_email(user_service):
    with patch('myapp.infrastructure.email.SmtpClient.send') as mock_send:
        user_service.register(email="user@example.com")
        mock_send.assert_called_once()
```

## Performance

```python
# Use __slots__ for memory-efficient objects
class Point:
    __slots__ = ('x', 'y')
    def __init__(self, x: float, y: float):
        self.x, self.y = x, y

# Cache expensive pure functions
from functools import lru_cache

@lru_cache(maxsize=128)
def fibonacci(n: int) -> int:
    return n if n < 2 else fibonacci(n-1) + fibonacci(n-2)
```

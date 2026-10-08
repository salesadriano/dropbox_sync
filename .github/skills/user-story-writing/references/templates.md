# User Story Templates Quick Reference

## Standard User Story

```
As a [type of user],
I want to [perform some action],
So that [I can achieve some goal/benefit].
```

**Example:**
```
As a registered customer,
I want to save items to a wishlist,
So that I can easily find and purchase them later.
```

---

## Acceptance Criteria — Given/When/Then (Gherkin)

```gherkin
Feature: Wishlist management

  Scenario: Add item to wishlist
    Given I am logged in as a registered customer
    And I am viewing a product page
    When I click "Add to Wishlist"
    Then the item should appear in my wishlist
    And I should see a confirmation message "Item saved to wishlist"

  Scenario: Remove item from wishlist
    Given I have items in my wishlist
    When I click "Remove" next to an item
    Then the item should be removed from my wishlist
    And the wishlist count should decrease by 1

  Scenario: Wishlist persists between sessions
    Given I have added items to my wishlist
    When I log out and log back in
    Then my wishlist should contain the same items
```

---

## Story Splitting Patterns

### By User Role
```
Original: As a user, I can manage my account.

Split:
- As a customer, I can update my email address.
- As a customer, I can change my password.
- As an admin, I can deactivate user accounts.
```

### By Data / Operations (CRUD)
```
Original: As a user, I can manage products.

Split:
- As a seller, I can create a product listing.
- As a seller, I can update my product details.
- As a seller, I can archive a product.
- As a buyer, I can view product details.
```

### By Happy Path / Edge Cases
```
Sprint 1: As a user, I can log in with valid credentials. (happy path)
Sprint 2: As a user, I see a clear error if my password is wrong. (edge case)
Sprint 3: As a user, I can reset my password if I forget it. (recovery)
```

### By Platform
```
- As a mobile user, I can pay with Apple Pay.
- As a desktop user, I can pay with a saved credit card.
```

---

## Definition of Done Checklist

```markdown
- [ ] Code reviewed and approved by at least one team member
- [ ] Unit tests written and passing
- [ ] Integration tests passing
- [ ] Acceptance criteria verified by QA
- [ ] No new accessibility violations (WCAG AA)
- [ ] Feature flag managed (if applicable)
- [ ] Documentation updated
- [ ] Product Owner accepted the story
```

---

## Story Sizing Guide (Fibonacci)

| Points | Description | Example |
|--------|-------------|---------|
| 1 | Trivial change, clear path | Fix typo in error message |
| 2 | Small, well-understood | Add field to existing form |
| 3 | Medium complexity, some unknowns | New filter on existing list |
| 5 | Complex or multiple integrations | OAuth login with new provider |
| 8 | Very complex — consider splitting | Real-time notifications system |
| 13+ | Too large — must split | Entire checkout flow |

---

## Non-Functional Story Template

```
As a [user/system],
I need [non-functional requirement],
So that [business/technical reason].

Performance: The page must load in under 2 seconds for 95% of requests.
Availability: The system must maintain 99.9% uptime during business hours.
Security: User data must be encrypted at rest and in transit.
```

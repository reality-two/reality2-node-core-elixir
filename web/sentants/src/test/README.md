# Testing Guide

This directory contains test setup and utilities for the Sentants application.

## Running Tests

```bash
# Run tests once
npm test

# Run tests in watch mode
npm test -- --watch

# Run tests with UI
npm run test:ui

# Run tests with coverage
npm run test:coverage
```

## Writing Tests

### Unit Tests for TypeScript Modules

Create a `*.test.ts` file next to the module you're testing:

```typescript
import { describe, it, expect } from "vitest";
import { myFunction } from "./myModule";

describe("myFunction", () => {
  it("should do something", () => {
    expect(myFunction()).toBe("expected result");
  });
});
```

### Component Tests

For Svelte components, use `@testing-library/svelte`:

```typescript
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/svelte";
import MyComponent from "./MyComponent.svelte";

describe("MyComponent", () => {
  it("should render correctly", () => {
    render(MyComponent, { props: { name: "Test" } });
    expect(screen.getByText("Test")).toBeInTheDocument();
  });
});
```

## Test Coverage

Current test coverage focuses on:
- ✅ R2 Client constructor
- ✅ JSONPath utility function
- ✅ Type conversion utilities

### TODO: Add tests for
- [ ] GraphQL query methods (sentantAll, sentantGet, etc.)
- [ ] WebSocket subscriptions (awaitSignal, monitor)
- [ ] Svelte components (SentantCard, Map, Construct)
- [ ] Blockly custom blocks
- [ ] Error handling scenarios
- [ ] Edge cases and boundary conditions

## Best Practices

1. **Arrange-Act-Assert**: Structure tests clearly
2. **Descriptive names**: Use descriptive test names
3. **One assertion per test**: Keep tests focused
4. **Mock external dependencies**: Use vitest mocks for API calls
5. **Test behavior, not implementation**: Focus on what the code does, not how

## CI/CD Integration

To run tests in CI/CD, add to your pipeline:

```yaml
- name: Run tests
  run: npm test -- --run
```

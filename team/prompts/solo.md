# Solo

You make one change to this repository on your own: its spec, its tests and its code. The run ID and the goal are at the end of this prompt.

Write the spec and tests inside `team/specs/<run-id>/`, and nothing else in that directory:

- `spec.md`: the acceptance criteria, as a numbered list a reviewer can check.
- `*.test.ts`, or `*.test.tsx` for tests that render a component: tests that cover every criterion through behaviour, not through how the code is written.

The run first tries your tests without your code. They must fail then, on an `expect`, and a test file that can't load ends the run as `BLOCKED`. So import existing code normally, and load new code through a variable:

```ts
import { expect, it } from "vitest";

const load = (path: string) =>
  import(/* @vite-ignore */ path).catch(() => null);

it("greets by name", async () => {
  const mod = await load("@/lib/greeting");
  expect(mod?.greet("Debbie")).toBe("Hello, Debbie");
});
```

Then implement the change. You can change only `src/` and `public/`, which `allowed_paths` in `team/config.json` lists, and not everything in them: `frozen_paths` lists what's off limits, including `src/test/` and config files. You also can't change existing tests, though you can add new ones. Any other change fails the gate, so you can't add dependencies either. If the goal can't be met this way, stop and say why. Don't work around it.

Before you finish, run every command under `commands` in `team/config.json`, and fix what fails. There's one attempt. Your shell is sandboxed: it can write only in this workspace, and it has no network. Dependencies are installed.

Leave your changes in place. This isn't a git repository.

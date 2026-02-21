# CLAUDE.md — Debbie's Curious

## What is this?

A mobile-first web app with one button ("I'm Curious") that uses GPS + LLM to tell you something interesting about your current location. Named after Debbie, who always asks "What's the story about this place?" on road trips.

## Tech Stack

- **Framework:** Next.js 16 (App Router, TypeScript)
- **Styling:** CSS Modules + CSS custom properties
- **LLM:** OpenAI (gpt-4o-mini) or Anthropic, selected via `LLM_PROVIDER` env var
- **Testing:** Vitest + React Testing Library (unit/integration), Playwright (E2E)
- **PWA:** @ducanh2912/next-pwa

## Commands

```bash
npm run dev          # Dev server with Turbopack
npm run build        # Production build
npm run lint         # ESLint + Prettier check
npm run lint:fix     # Auto-fix lint + format
npm run test         # Vitest in watch mode
npm run test:run     # Vitest single run (CI)
npm run test:e2e     # Playwright E2E tests
```

## Project Structure

```
src/
├── app/              # Next.js App Router pages + API routes
├── components/       # React components (each in own folder with CSS module)
├── hooks/            # Custom React hooks
├── lib/llm/          # LLM provider abstraction (strategy pattern)
├── lib/rate-limit.ts # In-memory rate limiter
├── types/            # Shared TypeScript types
└── test/             # Test setup
```

## Key Patterns

- **LLM Provider:** Strategy pattern — `LLMProvider` interface in `lib/llm/types.ts`, factory in `lib/llm/factory.ts`. Swap providers by changing `LLM_PROVIDER` env var.
- **CSS:** Design tokens as CSS custom properties in `globals.css`. Components use CSS Modules.
- **API:** Single endpoint `POST /api/curious` accepts `{ latitude, longitude }`, returns `{ fact }`.
- **Rate Limiting:** In-memory sliding window, 10 req/min/IP.

## Environment Variables

See `.env.example` for all required variables.

# Debbie's Curious

A mobile-first web app with one button that tells you something fascinating about where you are. Named after Debbie, who always asks _"What's the story about this place?"_ on road trips.

## How It Works

1. Tap **"I'm Curious!"**
2. The app gets your GPS location
3. An LLM generates an interesting fact about your area
4. The fact is displayed and read aloud via text-to-speech

## Quick Start

```bash
# Clone and install
git clone https://github.com/jhabshoosh/debbies-curious.git
cd debbies-curious
npm install

# Configure environment
cp .env.example .env
# Edit .env with your API key

# Run dev server
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) on your phone or browser.

## Environment Variables

| Variable            | Required           | Default                    | Description                 |
| ------------------- | ------------------ | -------------------------- | --------------------------- |
| `LLM_PROVIDER`      | No                 | `openai`                   | `"openai"` or `"anthropic"` |
| `OPENAI_API_KEY`    | If using OpenAI    | -                          | Your OpenAI API key         |
| `OPENAI_MODEL`      | No                 | `gpt-4o-mini`              | OpenAI model to use         |
| `ANTHROPIC_API_KEY` | If using Anthropic | -                          | Your Anthropic API key      |
| `ANTHROPIC_MODEL`   | No                 | `claude-sonnet-4-20250514` | Anthropic model to use      |

## Scripts

```bash
npm run dev          # Dev server (Turbopack)
npm run build        # Production build
npm run start        # Production server
npm run lint         # ESLint + Prettier check
npm run lint:fix     # Auto-fix lint/format issues
npm run test         # Vitest watch mode
npm run test:run     # Vitest single run
npm run test:e2e     # Playwright E2E tests
```

## Architecture

```
User taps "I'm Curious"
  -> Browser Geolocation API gets GPS coords
  -> POST /api/curious { latitude, longitude }
  -> Rate limit check (10 req/min/IP)
  -> LLM provider generates location fact
  -> Returns { fact: "..." }
  -> FactDisplay renders text
  -> TTS auto-reads aloud (if toggle is ON)
```

### LLM Provider Abstraction

Strategy pattern with `LLMProvider` interface. Swap providers by changing `LLM_PROVIDER` env var -- no code changes needed.

### Project Structure

```
src/
  app/                    # Next.js App Router
    api/curious/route.ts  # API endpoint
    CuriousApp.tsx        # Client orchestrator
    page.tsx              # Server component shell
  components/             # UI components
    CuriousButton/        # Hero button with loading states
    FactDisplay/          # LLM response card
    ErrorMessage/         # Friendly error display
    TTSControls/          # Auto-read toggle + manual play
  hooks/                  # Custom React hooks
    useCurious.ts         # GPS -> API -> state orchestration
    useGeolocation.ts     # Geolocation API wrapper
    useTTS.ts             # Web Speech API wrapper
  lib/
    llm/                  # LLM provider abstraction
    rate-limit.ts         # In-memory sliding window
```

## Deployment

Deploy to Vercel:

1. Push to GitHub
2. Import repo in [Vercel](https://vercel.com)
3. Add environment variables in Vercel dashboard
4. Deploy

## Tech Stack

- **Next.js 16** (App Router, TypeScript)
- **CSS Modules** with CSS custom properties
- **OpenAI / Anthropic** (swappable via env var)
- **Vitest + React Testing Library** (unit/integration)
- **Playwright** (E2E)
- **PWA** via @ducanh2912/next-pwa

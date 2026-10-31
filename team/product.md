# Product brief: Debbie's Curious

## What it is

One button that tells you something fascinating about where you are, and reads it aloud. It's named after Debbie, who always asks "What's the story about this place?" on road trips.

## Who it's for

Curious travellers, especially passengers on road trips and people exploring somewhere new. The first fans are the owner's mother, aunt and their friends, mostly around 55-75 and not technical. Assume someone who has never installed an app like this, and who'd give up if it needs explaining.

It has spread only by word of mouth. The owner's estimate is fewer than 50 users so far, in the US and Israel, with no measured count. Some return, and one asked for a fix from Greece when it stopped working. Nobody has paid.

## What matters most, in order

1. **It works when someone taps it.** A traveller in another country has no one to ask. A failed tap is the worst outcome.
2. **It's true.** Never present an invented detail as fact. If little is known about a place, say something honest or broader.
3. **It's delightful.** People love this because a story feels like a knowledgeable friend talking. Dull but accurate is a failure too.
4. **It stays simple.** One button first. Anything new has to keep that first experience just as easy.

## Current state

- Stories come from a model's memory with no sources, so accuracy is unmeasured. One rough estimate is a wrong detail in 40-70% of small-place stories.
- The prompt tells the model never to say it doesn't know.
- Nothing watches for outages or spending, and an empty OpenAI balance took the app down unnoticed.
- There's no usage data, so we can't tell what people do.
- There's no privacy policy, though the app uses location.
- Location can be up to 5 minutes old, which is about 5 miles at 60 mph.
- OpenStreetMap attribution was added on 2026-10-31.

## Priorities for now

Work roughly in this order, and skip what agents can't do alone:

1. **Reliability:** a spend cap, clear messages when something fails, fresher location.
2. **Honesty:** a privacy policy, and an end to invented details, including removing the "never say I don't know" instruction.
3. **Learning:** private usage analytics and a simple thumbs up or down on stories. The owner has approved a new analytics account for this. Prefer a free plan, and no cookies if possible. Analytics must never receive a user's location.
4. **Better stories:** grounded in real sources such as Wikipedia, without losing their warmth.
5. **More to do:** only after the above, and led by what users show they want. Early fans asked for more functionality, but we don't yet know what.

## How to judge a change

- A real user would notice, or it prevents a real failure.
- It helps someone in the first 30 seconds, or gives us something we can't otherwise learn.
- It's the smallest version that tests the idea.

Prefer evidence from real use over opinion, once usage data exists. Until then, say that a choice is a judgment call.

Never raise a quality score at users' expense. Stories that are shorter, duller or more often refused can score better on accuracy while making the app worse.

## Hard limits

Agents must not do these. Each one needs the owner:

- Charge money, show ads or add a paywall
- Add a paid plan, or a new service other than analytics. The owner creates any new account, since agents can't sign up for services
- Collect anything beyond what the app needs, or share location with a new third party
- Store or log a user's precise location
- Target drivers, or encourage using the app while driving
- Treat cemeteries, memorials, disaster or massacre sites as light entertainment
- Change the app's name or its one-button first screen
- Add a language other than English. Agents can't hear whether Hebrew speech sounds right
- Change anything in `team/` or `.github/`

## Not goals, for now

Accounts, social features, trip planning, turn-by-turn guidance, a native app, or competing with curated audio tours.

## What success looks like

- Next: nobody has to report an outage, and every story can be traced to a source.
- Then: more people come back in a second week, and they arrive from people the owner doesn't know.
- Later: whether anyone would pay, tested on purpose and approved by the owner.

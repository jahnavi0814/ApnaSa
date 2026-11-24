# ApnaSa deployment evidence

## Links

- Live application: https://apna-sa.vercel.app/
- Public source repository: https://github.com/jahnavi0814/ApnaSa
- Deployed source branch: `main`
- Deployment source commit: `3ec80b9` (`Build ApnaSa social discovery MVP`)

## Verification

The live URL was opened and its ApnaSa landing page loaded successfully. The GitHub repository shows the application source on the `main` branch.

## Current deployment scope

The public landing page is deployed. Supabase has not yet been configured, so authentication and shared database features are not available on the live app. The repository includes the Supabase schema and setup instructions for enabling them.

## Complete user journey assessment

**Assessment: the product code covers the intended journey, but the live MVP does not yet complete it end to end.**

1. **Problem:** Students and young people can feel awkward approaching strangers or entering an established group at an in-person gathering.
2. **Discovery and onboarding:** The app introduces ApnaSa, then provides sign-in, profile creation, interest selection, and event-visibility preferences.
3. **Event entry:** A user can create an event and share its code, or join an event with a code.
4. **Finding people:** Event members can discover others in that event, ranked by shared interests.
5. **Joining in:** Users can find and join groups, use shared-interest conversation prompts, or play a code-based “This or That” game.
6. **Safety and control:** The app includes flows for leaving events and groups, blocking users, and submitting reports. The database schema defines access controls for community visibility and sensitive safety records.
7. **Outcome:** Deployment is confirmed for the public landing page. No real-user outcome or engagement data has been collected, and the core journey has not been verified against a configured production database.

**What remains for a complete live journey:** create a Supabase project, apply `supabase/schema.sql`, configure the Vercel `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` environment variables, configure the authentication redirect URL, redeploy, and verify the flows with separate test accounts. Until then, sign-in and shared event, group, and game data are unavailable on the deployed site.

## Engineering checks

- GitHub Actions runs `npm ci`, `npm run lint`, and `npm run build` on pushes to `main` and pull requests targeting `main`.
- These checks cover static quality and production compilation. They do not prove Supabase behavior or replace end-to-end testing with separate user accounts.

## User validation plan

Run a short, consent-based session with 5–8 college students who have not used ApnaSa. Pair participants into host and attendee roles and ask them to complete the journey without coaching: create a profile, enter a shared event, find someone by common interests, join a group, use a conversation starter or game, then leave or report/block where appropriate. Do not collect unnecessary personal information.

Record outcomes only after sessions are conducted:

- Completion rate for event entry and first group interaction.
- Time from opening the app to joining an event and group.
- A 1–5 comfort rating before and after the first interaction.
- Where participants hesitate, abandon, or misunderstand the interface.
- Any privacy or safety concern, reported without identifying details.

The current evidence pack contains no participant results. Add dated, anonymized findings and resulting product changes after research; do not present planned measures as observed outcomes.

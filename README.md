# ApnaSa

Find your people. Your way. ApnaSa is an event-based social discovery app for making comfortable, interest-led connections at college gatherings.

## Stack

- React + TypeScript + Vite
- Supabase Auth, Postgres, Row Level Security, and Realtime
- Responsive CSS with a warm cream, slate, terracotta, sage, and amber design system

## Run locally

1. Create a Supabase project.
2. Copy `.env.example` to `.env.local` and set the project URL and anon key.
3. Run `supabase/schema.sql` in the Supabase SQL editor.
4. In Supabase Auth, configure the allowed redirect URLs for your local and deployed domains. Enable email confirmation and configure an email provider before launch. Google OAuth is not enabled in this build.
5. Run `npm install` and `npm run dev`.

The app does not provide mock accounts or local-only social data. Without Supabase configuration, the public product introduction is available and account actions explain that the backend needs to be connected.

## Features

- Real email/password authentication via Supabase Auth
- Student profile onboarding, interest selection, and event visibility preference
- Event creation, host-generated share code, joining by code, event switching, and leaving
- Event-scoped member discovery ranked by shared interests
- Event groups that members can create, join, and leave
- Conversation prompts based on shared interests
- This or That game rooms with invite codes and persisted answers
- Private report submission and user blocking
- RLS policies that limit profiles to shared event communities, limit membership operations, and protect reports and block lists

## Deployment

Deploy the Vite app to Vercel (recommended) or another web-app host, configure `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`, and add the deployed callback URL in Supabase Auth. Never put a Supabase service-role key in the browser app.

### Vercel

Import the GitHub repository into Vercel and keep the Vite defaults (`npm run build`, output directory `dist`). Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` as project environment variables, then deploy. Add the resulting Vercel domain to Supabase Auth's allowed redirect URLs. If Supabase values are missing, the public introduction will load but sign-in and database features will be disabled.

Before a public launch, set up a report review process, tune email abuse protections and auth rate limits, review the SQL policies against the exact launch workflows, and complete end-to-end checks with two separate test accounts in a Supabase project.

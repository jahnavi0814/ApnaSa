import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined
export const backendReady = Boolean(url && anonKey)

// A public anon key is designed for browser use; every table must still be protected by RLS.
export const supabase = createClient(
  url || 'https://missing-project.supabase.co',
  anonKey || 'missing-anon-key',
  { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } },
)

import { useEffect, useState } from 'react'
import { isSupabaseConfigured, supabase } from './lib/supabase'

export default function App() {
  const [session, setSession] = useState(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [message, setMessage] = useState('')

  useEffect(() => {
    if (!supabase) return
    supabase.auth.getSession().then(({ data }) => setSession(data.session))
    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => setSession(nextSession))
    return () => listener.subscription.unsubscribe()
  }, [])

  async function signUp(event) {
    event.preventDefault()
    setMessage('')
    const { error } = await supabase.auth.signUp({ email, password })
    setMessage(error ? error.message : 'Account created. Check your email to confirm it, then sign in.')
  }

  async function signIn(event) {
    event.preventDefault()
    setMessage('')
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setMessage(error ? error.message : 'Signed in successfully.')
  }

  if (!isSupabaseConfigured) {
    return <main className="shell"><h1>ClearDrop Water</h1><p>Phase 1 is ready. Add your Supabase values to <code>.env.local</code>, then restart the site.</p></main>
  }

  if (session) {
    return <main className="shell"><h1>Welcome to ClearDrop Water</h1><p>You are signed in as {session.user.email}.</p><p>Customer ordering, admin tools, and rider delivery screens arrive in the next phases.</p><button onClick={() => supabase.auth.signOut()}>Sign out</button></main>
  }

  return <main className="shell"><h1>ClearDrop Water</h1><p>Safe water, delivered simply.</p><div className="forms"><form onSubmit={signIn}><h2>Sign in</h2><label>Email<input type="email" value={email} onChange={e => setEmail(e.target.value)} required /></label><label>Password<input type="password" minLength="6" value={password} onChange={e => setPassword(e.target.value)} required /></label><button>Sign in</button></form><form onSubmit={signUp}><h2>New customer?</h2><p>Use the same email and password fields, then create an account.</p><button>Create account</button></form></div>{message && <p className="message">{message}</p>}</main>
}

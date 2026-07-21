import Foundation
import Supabase

/// Supabase connection settings.
///
/// The URL and anon key are not secrets — row-level security is the security
/// boundary. The local values below are the Supabase CLI's standard local-dev
/// credentials (`supabase start`); swap in the hosted project's values before
/// TestFlight.
enum Config {
    static let supabaseURL = URL(string: "http://127.0.0.1:54321")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
}

/// Shared Supabase client used by all repositories.
let supa = SupabaseClient(
    supabaseURL: Config.supabaseURL,
    supabaseKey: Config.supabaseAnonKey
)

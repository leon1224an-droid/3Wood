import Foundation
import Supabase

/// Supabase connection settings.
///
/// The URL and anon key are not secrets — row-level security is the security
/// boundary. Debug builds talk to the Supabase CLI's local stack; Release
/// builds must point at the hosted project (fill in the values below when it
/// exists — the runtime guard makes a localhost Release build impossible to
/// miss).
enum Config {
    #if DEBUG
    static let supabaseURL = URL(string: "http://127.0.0.1:54321")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    #else
    // Hosted project (created 2026-07-26). The publishable key replaces the
    // legacy anon JWT — same role, same "not a secret" status.
    static let supabaseURL = URL(string: "https://tivzyorqxauwbnczicst.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_TCv1DZgw6l7YE_oeKyJCYg_TqKpxJk8"
    #endif
}

/// Shared Supabase client used by all repositories.
let supa: SupabaseClient = {
    #if !DEBUG
    precondition(
        Config.supabaseURL.host != "127.0.0.1" && Config.supabaseURL.host != "localhost",
        "Release build still points at the local Supabase stack — set the hosted project URL in Supa.swift."
    )
    #endif
    return SupabaseClient(
        supabaseURL: Config.supabaseURL,
        supabaseKey: Config.supabaseAnonKey
    )
}()

import Foundation

/// Supabase project credentials. Fill these in before running the app.
///
/// Both values are safe to ship in the binary:
/// - `url` is just your project URL.
/// - `anonKey` is the public RLS-scoped key — it does not bypass RLS.
///
/// Find them in: Supabase Dashboard -> Project Settings -> API.
enum SupabaseConfig {
    static let url = URL(string: "https://qjeutitqgdsasccxfxdy.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFqZXV0aXRxZ2RzYXNjY3hmeGR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwMTMzNjksImV4cCI6MjA5NTU4OTM2OX0.j2yU_6HTLh6WJaPUFsG3vdgd0cK6VHFXm6XYW_cb26U"
}

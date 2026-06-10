// Supabase Edge Function: task-suggestions
//
// Generates ephemeral, inspirational task suggestions for the iOS homescreen.
// The iOS app authenticates with its Supabase JWT; this function reads recent
// user todos server-side and calls OpenAI with OPENAI_API_KEY.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const OPENAI_SUGGESTIONS_MODEL = Deno.env.get("OPENAI_SUGGESTIONS_MODEL") ??
    "gpt-5.4-mini";

const MAX_COUNT = 5;
const MAX_EXCLUDED_TITLES = 80;
const MAX_FETCH_TODOS = 60;
const MAX_RECENT_ACTIVITY = 3;
const MAX_HISTORICAL_ACTIVITY = 6;
const MAX_MEMORIES = 10;
const TITLE_OVERLAP_THRESHOLD = 0.72;

interface SuggestionRequest {
    count?: number;
    exclude_titles?: string[];
}

interface TodoContextRow {
    title: string;
    original_title: string | null;
    status: string;
    connection_slug: string | null;
    preparation_summary: string | null;
    topic: string | null;
    collection_name: string | null;
    created_at: string;
    updated_at: string;
    completed_at: string | null;
}

interface MemoryRow {
    title: string;
    body: string;
}

interface TaskSuggestion {
    title: string;
    theme: string;
    connection_slug?: string | null;
}

interface ActivitySummary {
    theme: string;
    integration: string | null;
    summary: string;
    completed: boolean;
    topic: string | null;
    collection: string | null;
}

interface WorkProfile {
    top_integrations: Array<{ slug: string | null; count: number }>;
    top_topics: Array<{ topic: string; count: number }>;
    collections: string[];
    completed_last_7d: number;
    total_tasks: number;
    completed_count: number;
}

function corsHeaders(): HeadersInit {
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers":
            "authorization, x-client-info, apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
    };
}

function json(body: unknown, status = 200): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { ...corsHeaders(), "Content-Type": "application/json" },
    });
}

function clampCount(value: unknown): number {
    if (typeof value !== "number" || !Number.isFinite(value)) return MAX_COUNT;
    return Math.max(1, Math.min(MAX_COUNT, Math.floor(value)));
}

function cleanString(value: unknown, maxLength: number): string {
    if (typeof value !== "string") return "";
    return value.replace(/\s+/g, " ").trim().slice(0, maxLength);
}

function cleanTheme(value: unknown): string {
    const cleaned = cleanString(value, 24).replace(/[^a-zA-Z -]/g, "").trim();
    const firstWord = cleaned.split(/\s+/)[0] ?? "";
    return firstWord.length > 0 ? firstWord : "Idea";
}

function normalizeTitle(title: string): string {
    return title.toLowerCase().replace(/[^\w\s]/g, " ").replace(/\s+/g, " ").trim();
}

function titleTokens(title: string): Set<string> {
    return new Set(
        normalizeTitle(title)
            .split(" ")
            .filter((token) => token.length > 2),
    );
}

function titleOverlap(a: string, b: string): number {
    const tokensA = titleTokens(a);
    const tokensB = titleTokens(b);
    if (tokensA.size === 0 || tokensB.size === 0) return 0;
    let shared = 0;
    for (const token of tokensA) {
        if (tokensB.has(token)) shared++;
    }
    return shared / Math.max(tokensA.size, tokensB.size);
}

function buildHistoricalTitles(todos: TodoContextRow[]): Set<string> {
    const titles = new Set<string>();
    for (const todo of todos) {
        const prepared = cleanString(todo.title, 160);
        const original = cleanString(todo.original_title, 160);
        if (prepared) titles.add(normalizeTitle(prepared));
        if (original) titles.add(normalizeTitle(original));
    }
    return titles;
}

function isTooSimilarToHistory(
    title: string,
    historicalTitles: Set<string>,
): boolean {
    const normalized = normalizeTitle(title);
    if (!normalized) return true;
    if (historicalTitles.has(normalized)) return true;

    for (const historical of historicalTitles) {
        if (titleOverlap(normalized, historical) >= TITLE_OVERLAP_THRESHOLD) {
            return true;
        }
        if (
            normalized.includes(historical) ||
            historical.includes(normalized)
        ) {
            const shorter = Math.min(normalized.length, historical.length);
            const longer = Math.max(normalized.length, historical.length);
            if (shorter >= 12 && shorter / longer >= 0.65) return true;
        }
    }
    return false;
}

function themeForTodo(todo: TodoContextRow): string {
    switch (todo.connection_slug) {
        case "gmail":
            return "Email";
        case "googlecalendar":
            return "Plan";
        case "googlesheets":
            return "Sheets";
        case "slack":
            return "Update";
        case "googledocs":
            return "Write";
        case "googledrive":
            return "Docs";
        default:
            return todo.status === "done" ? "Follow-up" : "Idea";
    }
}

function summarizeTodo(todo: TodoContextRow): string {
    const summary = cleanString(todo.preparation_summary, 120);
    if (summary) return summary;
    return cleanString(todo.title, 110);
}

function compactActivity(todo: TodoContextRow): ActivitySummary {
    return {
        theme: themeForTodo(todo),
        integration: todo.connection_slug,
        summary: summarizeTodo(todo),
        completed: todo.status === "done",
        topic: cleanString(todo.topic, 40) || null,
        collection: cleanString(todo.collection_name, 60) || null,
    };
}

function buildWorkProfile(allTodos: TodoContextRow[]): WorkProfile {
    const slugCounts = new Map<string | null, number>();
    const topicCounts = new Map<string, number>();
    const collections = new Set<string>();
    const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
    let completedLast7d = 0;

    for (const todo of allTodos) {
        const slug = todo.connection_slug;
        slugCounts.set(slug, (slugCounts.get(slug) ?? 0) + 1);

        const topic = cleanString(todo.topic, 40);
        if (topic) topicCounts.set(topic, (topicCounts.get(topic) ?? 0) + 1);

        const collection = cleanString(todo.collection_name, 60);
        if (collection) collections.add(collection);

        if (todo.status === "done") {
            const completedAt = todo.completed_at ?? todo.updated_at;
            if (new Date(completedAt).getTime() >= sevenDaysAgo) {
                completedLast7d++;
            }
        }
    }

    return {
        top_integrations: [...slugCounts.entries()]
            .sort((a, b) => b[1] - a[1])
            .slice(0, 6)
            .map(([slug, count]) => ({ slug, count })),
        top_topics: [...topicCounts.entries()]
            .sort((a, b) => b[1] - a[1])
            .slice(0, 6)
            .map(([topic, count]) => ({ topic, count })),
        collections: [...collections].slice(0, 8),
        completed_last_7d: completedLast7d,
        total_tasks: allTodos.length,
        completed_count: allTodos.filter((todo) => todo.status === "done").length,
    };
}

// Sample varied todos for activity summaries — not for copy-paste titles.
function selectActivitySummaries(allTodos: TodoContextRow[]): ActivitySummary[] {
    const recentRaw = allTodos.slice(0, MAX_RECENT_ACTIVITY);
    const recentSummaries = new Set(
        recentRaw.map((todo) => normalizeTitle(summarizeTodo(todo))),
    );
    const historical: TodoContextRow[] = [];
    const seenSummaries = new Set<string>(recentSummaries);

    const bySlug = new Map<string, TodoContextRow[]>();
    for (const todo of allTodos) {
        const slug = todo.connection_slug || "general";
        if (!bySlug.has(slug)) bySlug.set(slug, []);
        bySlug.get(slug)!.push(todo);
    }

    const slugOrder = [...bySlug.entries()].sort((a, b) => b[1].length - a[1].length);
    for (const [, bucket] of slugOrder) {
        if (historical.length >= MAX_HISTORICAL_ACTIVITY) break;

        const candidates = [...bucket]
            .filter((todo) => !recentRaw.includes(todo))
            .sort((a, b) => {
                const aDone = a.status === "done" ? 0 : 1;
                const bDone = b.status === "done" ? 0 : 1;
                if (aDone !== bDone) return aDone - bDone;
                return new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime();
            });

        let picked = 0;
        for (const candidate of candidates) {
            if (picked >= 2) break;
            const key = normalizeTitle(summarizeTodo(candidate));
            if (seenSummaries.has(key)) continue;
            historical.push(candidate);
            seenSummaries.add(key);
            picked++;
        }
    }

    return [
        ...recentRaw.map(compactActivity),
        ...historical.map(compactActivity),
    ].slice(0, MAX_RECENT_ACTIVITY + MAX_HISTORICAL_ACTIVITY);
}

function sanitizeSuggestion(
    raw: unknown,
    excluded: Set<string>,
    historicalTitles: Set<string>,
): TaskSuggestion | null {
    if (!raw || typeof raw !== "object") return null;
    const record = raw as Record<string, unknown>;
    const title = cleanString(record.title, 140);
    if (!title) return null;

    const normalized = normalizeTitle(title);
    if (excluded.has(normalized)) return null;
    if (isTooSimilarToHistory(title, historicalTitles)) return null;

    return {
        title,
        theme: cleanTheme(record.theme),
        connection_slug: cleanString(record.connection_slug, 40) || null,
    };
}

function fallbackSuggestions(count: number, excluded: Set<string>): TaskSuggestion[] {
    const starters: TaskSuggestion[] = [
        { title: "Draft a reply to an email I have been putting off", theme: "Email", connection_slug: "gmail" },
        { title: "Plan my week around the most important tasks", theme: "Plan", connection_slug: "googlecalendar" },
        { title: "Research options for a decision I need to make", theme: "Research", connection_slug: null },
        { title: "Create a reminder for something I keep forgetting", theme: "Remind", connection_slug: null },
        { title: "Turn messy notes into a clear action plan", theme: "Write", connection_slug: "googledocs" },
        { title: "Find and summarize a document from my workspace", theme: "Docs", connection_slug: "googledrive" },
        { title: "Prepare a short status update I can send", theme: "Update", connection_slug: "slack" },
        { title: "Organize follow-ups from recent conversations", theme: "Follow-up", connection_slug: "gmail" },
    ];
    return starters
        .filter((s) => !excluded.has(normalizeTitle(s.title)))
        .slice(0, count);
}

function buildPrompt(
    count: number,
    todos: TodoContextRow[],
    excludedTitles: string[],
    memories: MemoryRow[],
    forbiddenTitles: string[],
): Array<{ role: "system" | "user"; content: string }> {
    const hasHistory = todos.length > 0;
    const workProfile = hasHistory ? buildWorkProfile(todos) : null;
    const recentActivity = hasHistory ? selectActivitySummaries(todos) : [];

    return [
        {
            role: "system",
            content:
                "You suggest the next thing a doit user would naturally ask their personal AI agent to do. " +
                "Base suggestions on work_profile, recent_activity, and user_memories — not on repeating past requests. " +
                "Each suggestion must be a fresh, actionable card title the user could tap to create a new task. " +
                "Suggest adjacent next steps: follow-ups, batch variants, cross-integration workflows, recurring chores, " +
                "and prep implied by collections or topics. Do not execute anything. Avoid destructive or risky actions. " +
                "Return only valid JSON.",
        },
        {
            role: "user",
            content: JSON.stringify({
                instruction:
                    `Generate ${count} concise suggested tasks as card titles. ` +
                    "When work_profile shows real history, every suggestion must feel personalized to this user's patterns.",
                cold_start_rules: hasHistory
                    ? null
                    : [
                        "There is no task history. Showcase what doit can do.",
                        "Use concrete but fill-in-friendly starter tasks.",
                        "Cover email, planning, research, reminders, writing, and organization.",
                    ],
                personalization_rules: hasHistory
                    ? [
                        "Infer what this user does with doit from work_profile and recent_activity summaries.",
                        "Never repeat or lightly rephrase any forbidden_title.",
                        "Do not output generic demo tasks when work_profile.total_tasks > 0.",
                        "Use at least 3 distinct theme values when count >= 3.",
                        "Prefer logical next actions over repeating what they already asked for.",
                        "Example: if they emailed a vendor about pricing, suggest checking for a reply — not sending the same email again.",
                    ]
                    : null,
                output_schema: {
                    suggestions: [
                        {
                            title: "string, <= 110 chars, actionable and specific",
                            theme: "one word, e.g. Email, Plan, Research, Remind, Write",
                            connection_slug: "optional known toolkit slug or null",
                        },
                    ],
                },
                constraints: [
                    "Return exactly the requested number if possible.",
                    "Do not repeat excluded_titles or forbidden_titles.",
                    "Do not include markdown.",
                    "Do not use ellipses unless intentionally fill-in-friendly for cold start.",
                ],
                excluded_titles: excludedTitles,
                forbidden_titles: forbiddenTitles.slice(0, MAX_EXCLUDED_TITLES),
                work_profile: workProfile,
                recent_activity: hasHistory ? recentActivity : null,
                user_memories: memories.length > 0
                    ? memories.map((m) => ({
                        title: m.title,
                        body: m.body,
                    }))
                    : null,
            }),
        },
    ];
}

async function callOpenAI(
    count: number,
    todos: TodoContextRow[],
    excludedTitles: string[],
    memories: MemoryRow[],
    forbiddenTitles: string[],
): Promise<TaskSuggestion[]> {
    const res = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
            Authorization: `Bearer ${OPENAI_API_KEY}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            model: OPENAI_SUGGESTIONS_MODEL,
            messages: buildPrompt(count, todos, excludedTitles, memories, forbiddenTitles),
            response_format: { type: "json_object" },
        }),
    });

    if (!res.ok) {
        throw new Error(`openai_error:${res.status}:${await res.text()}`);
    }

    const data = await res.json();
    const content = data?.choices?.[0]?.message?.content;
    if (typeof content !== "string") {
        throw new Error("openai_bad_response");
    }

    const parsed = JSON.parse(content);
    const rawSuggestions = Array.isArray(parsed?.suggestions) ? parsed.suggestions : [];
    const historicalTitles = buildHistoricalTitles(todos);
    const excluded = new Set([
        ...excludedTitles.map(normalizeTitle),
        ...forbiddenTitles.map(normalizeTitle),
    ]);
    const suggestions: TaskSuggestion[] = [];

    for (const raw of rawSuggestions) {
        const suggestion = sanitizeSuggestion(raw, excluded, historicalTitles);
        if (!suggestion) continue;
        const normalized = normalizeTitle(suggestion.title);
        excluded.add(normalized);
        suggestions.push(suggestion);
        if (suggestions.length >= count) break;
    }

    return suggestions;
}

async function generateSuggestions(
    count: number,
    todos: TodoContextRow[],
    excludedTitles: string[],
    memories: MemoryRow[],
): Promise<TaskSuggestion[]> {
    if (!OPENAI_API_KEY) {
        throw new Error("openai_not_configured");
    }

    const forbiddenTitles = [...buildHistoricalTitles(todos)];
    let suggestions = await callOpenAI(
        count,
        todos,
        excludedTitles,
        memories,
        forbiddenTitles,
    );

    if (suggestions.length < count && todos.length > 0) {
        const retryExcluded = [
            ...excludedTitles,
            ...suggestions.map((s) => s.title),
        ];
        const retry = await callOpenAI(
            count,
            todos,
            retryExcluded,
            memories,
            forbiddenTitles,
        );
        const seen = new Set(suggestions.map((s) => normalizeTitle(s.title)));
        for (const candidate of retry) {
            const key = normalizeTitle(candidate.title);
            if (seen.has(key)) continue;
            seen.add(key);
            suggestions.push(candidate);
            if (suggestions.length >= count) break;
        }
    }

    return suggestions;
}

serve(async (req) => {
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders() });
    }
    if (req.method !== "POST") {
        return json({ error: "method_not_allowed" }, 405);
    }
    if (!SUPABASE_SERVICE_ROLE_KEY) {
        return json({ error: "service_role_not_configured" }, 500);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
        return json({ error: "unauthorized" }, 401);
    }

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: authHeader } },
    });
    const { data: userResp, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userResp.user) {
        return json({ error: "unauthorized" }, 401);
    }

    let body: SuggestionRequest;
    try {
        body = await req.json();
    } catch {
        return json({ error: "invalid_json" }, 400);
    }

    const count = clampCount(body.count);
    const excludedTitles = (Array.isArray(body.exclude_titles) ? body.exclude_titles : [])
        .map((title) => cleanString(title, 160))
        .filter(Boolean)
        .slice(0, MAX_EXCLUDED_TITLES);

    const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const userId = userResp.user.id;

    const [todosResult, memoriesResult] = await Promise.all([
        serviceClient
            .from("todos")
            .select(
                "title,original_title,status,connection_slug,preparation_summary,topic,collection_name,created_at,updated_at,completed_at",
            )
            .eq("user_id", userId)
            .order("updated_at", { ascending: false })
            .limit(MAX_FETCH_TODOS),
        serviceClient
            .from("memories")
            .select("title,body")
            .eq("user_id", userId)
            .eq("memory_status", "active")
            .eq("target", "user")
            .order("updated_at", { ascending: false })
            .limit(MAX_MEMORIES),
    ]);

    const { data, error } = todosResult;
    if (error) {
        console.error("task-suggestions todo fetch error:", error);
        return json({ error: "todo_context_failed", detail: String(error.message ?? error) }, 500);
    }

    const todos = (data ?? []) as TodoContextRow[];
    const memories = (memoriesResult.data ?? []) as MemoryRow[];
    const hasHistory = todos.length > 0;
    const excluded = new Set(excludedTitles.map(normalizeTitle));

    try {
        const generated = await generateSuggestions(
            count,
            todos,
            excludedTitles,
            memories,
        );

        if (!hasHistory && generated.length < count) {
            const fallback = fallbackSuggestions(
                count - generated.length,
                new Set([
                    ...excluded,
                    ...generated.map((s) => normalizeTitle(s.title)),
                ]),
            );
            return json({ suggestions: [...generated, ...fallback].slice(0, count) });
        }

        return json({ suggestions: generated.slice(0, count) });
    } catch (err) {
        console.error("task-suggestions generation error:", err);
        if (!hasHistory) {
            return json({
                suggestions: fallbackSuggestions(count, excluded),
                degraded: true,
                error: String(err),
            });
        }
        return json({
            suggestions: [],
            degraded: true,
            error: String(err),
        });
    }
});

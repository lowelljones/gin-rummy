import type { SupabaseClient } from "@supabase/supabase-js";

const REPORT_REASONS = new Set(["harassment", "hate", "spam", "inappropriate", "other"]);

export function normalizeReportReason(raw: unknown): string | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  if (!trimmed) return null;
  const lower = trimmed.toLowerCase();
  if (REPORT_REASONS.has(lower)) return lower;
  return trimmed.slice(0, 200);
}

export async function blockedUserIdsFor(
  admin: SupabaseClient,
  blockerId: string,
): Promise<Set<string>> {
  const { data, error } = await admin
    .from("user_blocks")
    .select("blocked_user_id")
    .eq("blocker_id", blockerId);
  if (error) throw new Error(error.message);
  return new Set((data ?? []).map((row) => row.blocked_user_id as string));
}

export type BlockedUserRow = { blocked_user_id: string; created_at: string };

export async function listBlockedUsers(
  admin: SupabaseClient,
  blockerId: string,
): Promise<BlockedUserRow[]> {
  const { data, error } = await admin
    .from("user_blocks")
    .select("blocked_user_id, created_at")
    .eq("blocker_id", blockerId)
    .order("created_at", { ascending: false });
  if (error) throw new Error(error.message);
  return (data ?? []) as BlockedUserRow[];
}

export async function insertUserBlock(
  admin: SupabaseClient,
  blockerId: string,
  blockedUserId: string,
): Promise<void> {
  const { error } = await admin.from("user_blocks").upsert(
    { blocker_id: blockerId, blocked_user_id: blockedUserId },
    { onConflict: "blocker_id,blocked_user_id", ignoreDuplicates: true },
  );
  if (error) throw new Error(error.message);
}

export async function deleteUserBlock(
  admin: SupabaseClient,
  blockerId: string,
  blockedUserId: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from("user_blocks")
    .delete()
    .eq("blocker_id", blockerId)
    .eq("blocked_user_id", blockedUserId)
    .select("blocked_user_id")
    .maybeSingle();
  if (error) throw new Error(error.message);
  return data != null;
}

export type ChatReportInsert = {
  id: string;
  game_id: string;
  message_id: string;
  reporter_id: string;
  reported_user_id: string;
  reason: string | null;
};

export async function insertChatReport(
  admin: SupabaseClient,
  row: Omit<ChatReportInsert, "id">,
): Promise<ChatReportInsert> {
  const { data, error } = await admin
    .from("chat_reports")
    .insert(row)
    .select("id, game_id, message_id, reporter_id, reported_user_id, reason")
    .single();
  if (error || !data) throw new Error(error?.message ?? "insert failed");
  return data as ChatReportInsert;
}

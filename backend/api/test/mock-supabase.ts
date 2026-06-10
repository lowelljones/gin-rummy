/**
 * Minimal in-memory Supabase stand-in (GoTrue auth + PostgREST) covering the
 * exact query surface the Gin Rummy API server uses. Lets the invite-link E2E
 * (two humans joining via a texted link) run hermetically, with no live
 * Supabase project required.
 *
 * Supported:
 *   - POST   /auth/v1/admin/users            (create confirmed user)
 *   - DELETE /auth/v1/admin/users/:id
 *   - POST   /auth/v1/token?grant_type=password
 *   - GET    /auth/v1/user                   (Bearer token -> user)
 *   - GET/POST/PATCH/DELETE /rest/v1/:table  with `col=eq.V`, `col=in.(..)`
 *     filters, `order=col.asc|desc`, `limit`, upsert (`Prefer:
 *     resolution=merge-duplicates` + `on_conflict`), `return=representation`,
 *     and `.single()`'s `Accept: application/vnd.pgrst.object+json`.
 *
 * Run: npx tsx test/mock-supabase.ts   (PORT via MOCK_SUPABASE_PORT, default 9123)
 */
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import crypto from "node:crypto";

const PORT = Number(process.env.MOCK_SUPABASE_PORT ?? "9123");

type Row = Record<string, unknown>;
const tables: Record<string, Row[]> = {
  profiles: [],
  lobbies: [],
  lobby_players: [],
  games: [],
  hands: [],
  game_moves: [],
  game_chat_messages: [],
};

type User = { id: string; email: string; password: string };
const users = new Map<string, User>(); // id -> user
const tokens = new Map<string, string>(); // token -> user id

let createdAtCounter = 0;
function nextCreatedAt(): string {
  // Strictly increasing so `order("created_at")` is deterministic.
  return new Date(Date.now() + createdAtCounter++).toISOString();
}

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

function send(res: ServerResponse, status: number, body: unknown) {
  const text = body === undefined ? "" : JSON.stringify(body);
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(text);
}

function userJson(u: User) {
  const now = new Date().toISOString();
  return {
    id: u.id,
    aud: "authenticated",
    role: "authenticated",
    email: u.email,
    email_confirmed_at: now,
    confirmed_at: now,
    created_at: now,
    updated_at: now,
    app_metadata: { provider: "email", providers: ["email"] },
    user_metadata: {},
    identities: [],
  };
}

// ---- PostgREST-ish filtering ----

type Filter = { col: string; op: "eq" | "in"; value: string | string[] };

function parseFilters(params: URLSearchParams): {
  filters: Filter[];
  order: { col: string; asc: boolean } | null;
  limit: number | null;
  onConflict: string | null;
} {
  const filters: Filter[] = [];
  let order: { col: string; asc: boolean } | null = null;
  let limit: number | null = null;
  let onConflict: string | null = null;

  for (const [key, value] of params.entries()) {
    if (key === "select" || key === "columns") continue;
    if (key === "on_conflict") {
      onConflict = value;
      continue;
    }
    if (key === "order") {
      const [col, dir] = value.split(".");
      order = { col, asc: dir !== "desc" };
      continue;
    }
    if (key === "limit") {
      limit = Number(value);
      continue;
    }
    if (value.startsWith("eq.")) {
      filters.push({ col: key, op: "eq", value: value.slice(3) });
    } else if (value.startsWith("in.(") && value.endsWith(")")) {
      const list = value
        .slice(4, -1)
        .split(",")
        .map((s) => s.trim().replace(/^"|"$/g, ""));
      filters.push({ col: key, op: "in", value: list });
    }
  }
  return { filters, order, limit, onConflict };
}

function matches(row: Row, filters: Filter[]): boolean {
  for (const f of filters) {
    const actual = row[f.col];
    if (f.op === "eq") {
      if (String(actual) !== f.value) return false;
    } else {
      if (!(f.value as string[]).some((v) => String(actual) === v)) return false;
    }
  }
  return true;
}

function applyDefaults(table: string, row: Row): Row {
  const out: Row = { ...row };
  if (out.id === undefined) out.id = crypto.randomUUID();
  if (out.created_at === undefined) out.created_at = nextCreatedAt();
  if (table === "lobby_players" && out.ready === undefined) out.ready = false;
  return out;
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", `http://127.0.0.1:${PORT}`);
  const method = req.method ?? "GET";

  try {
    // ---- Auth (GoTrue) ----
    if (url.pathname === "/auth/v1/admin/users" && method === "POST") {
      const body = JSON.parse(await readBody(req)) as { email: string; password: string };
      const u: User = { id: crypto.randomUUID(), email: body.email, password: body.password };
      users.set(u.id, u);
      return send(res, 200, userJson(u));
    }
    const adminUserMatch = url.pathname.match(/^\/auth\/v1\/admin\/users\/([0-9a-f-]+)$/);
    if (adminUserMatch && method === "DELETE") {
      users.delete(adminUserMatch[1]);
      return send(res, 200, {});
    }
    if (url.pathname === "/auth/v1/token" && method === "POST") {
      const body = JSON.parse(await readBody(req)) as { email: string; password: string };
      const u = [...users.values()].find((x) => x.email === body.email && x.password === body.password);
      if (!u) return send(res, 400, { error: "invalid_grant", error_description: "Invalid login credentials" });
      const token = `mock-${u.id}-${crypto.randomUUID()}`;
      tokens.set(token, u.id);
      return send(res, 200, {
        access_token: token,
        token_type: "bearer",
        expires_in: 3600,
        refresh_token: `r-${token}`,
        user: userJson(u),
      });
    }
    if (url.pathname === "/auth/v1/user" && method === "GET") {
      const auth = req.headers.authorization ?? "";
      const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
      const uid = tokens.get(token);
      const u = uid ? users.get(uid) : undefined;
      if (!u) return send(res, 401, { code: 401, msg: "invalid JWT" });
      return send(res, 200, userJson(u));
    }

    // ---- PostgREST ----
    const restMatch = url.pathname.match(/^\/rest\/v1\/([a-z_]+)$/);
    if (restMatch) {
      const table = restMatch[1];
      if (!(table in tables)) return send(res, 404, { message: `relation "${table}" does not exist` });
      const rows = tables[table];
      const { filters, order, limit, onConflict } = parseFilters(url.searchParams);
      const prefer = String(req.headers.prefer ?? "");
      const accept = String(req.headers.accept ?? "");
      const wantsObject = accept.includes("vnd.pgrst.object");
      const wantsRepresentation = prefer.includes("return=representation");

      const respond = (selected: Row[], createdStatus = 200) => {
        if (wantsObject) {
          if (selected.length !== 1) {
            return send(res, 406, {
              code: "PGRST116",
              details: `Results contain ${selected.length} rows`,
              hint: null,
              message: "JSON object requested, multiple (or no) rows returned",
            });
          }
          return send(res, createdStatus, selected[0]);
        }
        return send(res, createdStatus, selected);
      };

      if (method === "GET") {
        let selected = rows.filter((r) => matches(r, filters));
        if (order) {
          selected = [...selected].sort((a, b) => {
            const av = String(a[order.col] ?? "");
            const bv = String(b[order.col] ?? "");
            return order.asc ? av.localeCompare(bv) : bv.localeCompare(av);
          });
        }
        if (limit !== null) selected = selected.slice(0, limit);
        return respond(selected);
      }

      if (method === "POST") {
        const raw = JSON.parse(await readBody(req)) as Row | Row[];
        const incoming = Array.isArray(raw) ? raw : [raw];
        const isUpsert = prefer.includes("resolution=merge-duplicates");
        const inserted: Row[] = [];
        for (const r of incoming) {
          if (isUpsert && onConflict) {
            const idx = rows.findIndex((x) => String(x[onConflict]) === String(r[onConflict]));
            if (idx >= 0) {
              rows[idx] = { ...rows[idx], ...r };
              inserted.push(rows[idx]);
              continue;
            }
          }
          const full = applyDefaults(table, r);
          rows.push(full);
          inserted.push(full);
        }
        if (!wantsRepresentation) return send(res, 201, undefined);
        return respond(inserted, 201);
      }

      if (method === "PATCH") {
        const patch = JSON.parse(await readBody(req)) as Row;
        const updated: Row[] = [];
        for (let i = 0; i < rows.length; i++) {
          if (matches(rows[i], filters)) {
            rows[i] = { ...rows[i], ...patch };
            updated.push(rows[i]);
          }
        }
        if (!wantsRepresentation) return send(res, 204, undefined);
        return respond(updated);
      }

      if (method === "DELETE") {
        const kept = rows.filter((r) => !matches(r, filters));
        const removed = rows.filter((r) => matches(r, filters));
        tables[table] = kept;
        if (!wantsRepresentation) return send(res, 204, undefined);
        return respond(removed);
      }
    }

    return send(res, 404, { message: `mock-supabase: unhandled ${method} ${url.pathname}` });
  } catch (e) {
    return send(res, 500, { message: `mock-supabase error: ${(e as Error).message}` });
  }
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`mock-supabase listening on http://127.0.0.1:${PORT}`);
});

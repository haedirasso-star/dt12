// ════════════════════════════════════════════════════════════════════
//  TOTV+ push v2 — Supabase Edge Function (مجانية: 500 ألف استدعاء/شهر)
//
//  الإشعارات
//   • order            ← تطبيق TOTV+ بعد إرسال طلب اشتراك ⇐ إشعار فوري للإدارة
//   • broadcast        ← الإدارة ⇐ إشعار لكل المستخدمين
//   • admin_test_order ← الإدارة ⇐ إشعار طلب تجريبي (فحص النظام)
//  التوقعات والدعوات والمحادثة (جداول 04_engagement.sql)
//   • المستخدم: predict · pred_get · ref_me · ref_apply · ref_mine · chat_list · chat_send
//   • الإدارة:  admin_threads · admin_messages · admin_send · admin_rewards · admin_settle
//               admin_reward_done · ref_on_order · admin_auto_expiring
//
//  الحماية: كل طلب يحمل Firebase ID Token يُتحقق منه هنا محلياً بتوقيع Google
//  (بلا مفتاح API — لا يتأثر بقيود المفاتيح). أوامر الإدارة لبريد ADMIN_EMAILS فقط.
//  مفاتيح Firebase وSupabase السرية تبقى هنا في Secrets — لا تدخل أي تطبيق.
//
//  Secrets: FCM_SERVICE_ACCOUNT · ADMIN_EMAILS   (SUPABASE_SERVICE_ROLE_KEY تلقائي)
//  اختياري: SB_SECRET_KEY (مفتاح sb_secret_ إن أوقفت المفاتيح القديمة) · SPORTS_FEED_URL · ICON_URL
// ════════════════════════════════════════════════════════════════════

const SA = (() => { try { return JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}"); } catch { return {}; } })();
const PROJECT = String(SA.project_id ?? "totvq-8e439");
const WEB_KEYS = [Deno.env.get("FIREBASE_WEB_API_KEY"), "AIzaSyCk0dSmHGQ248b-OQi44Rm2zWrfbpLBkpU", "AIzaSyBR9NjEZHm9RhngSfYNMmphaH_gDLTApTY"]
  .filter((k): k is string => !!k);
const ADMINS = (Deno.env.get("ADMIN_EMAILS") ?? "").toLowerCase().split(",").map((s) => s.trim()).filter(Boolean);
const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const SB_KEY = Deno.env.get("SB_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const ICON = Deno.env.get("ICON_URL") || `${BASE}/functions/v1/push/icon.png`;
const TOPICS = new Set(["all_users", "matches", "admins"]);
const VERSION = 2;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const clip = (v: unknown, n: number) => String(v ?? "").replace(/\s+/g, " ").trim().slice(0, n);
const text = (v: unknown, n: number) => String(v ?? "").replace(/\r/g, "").replace(/\n{3,}/g, "\n\n").trim().slice(0, n);
const int = (v: unknown, d = 0) => { const n = Number(v); return Number.isFinite(n) ? Math.trunc(n) : d; };
class HttpErr extends Error { constructor(public code: number, msg: string) { super(msg); } }

// ── أدوات base64url ────────────────────────────────────────────────
const b64url = (b: ArrayBuffer | Uint8Array) =>
  btoa(String.fromCharCode(...new Uint8Array(b as ArrayBuffer))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));
const unb64 = (s: string) => {
  const t = s.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(t.padEnd(t.length + (4 - t.length % 4) % 4, "=")), (c) => c.charCodeAt(0));
};
const unjson = (s: string) => JSON.parse(new TextDecoder().decode(unb64(s)));

// ── توكن Google (FCM + Firestore) يُخزّن 50 دقيقة ───────────────────
let tok = { v: "", exp: 0 };
async function gToken(): Promise<string> {
  if (tok.v && Date.now() < tok.exp) return tok.v;
  const pem = String(SA.private_key ?? "").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const iat = Math.floor(Date.now() / 1000);
  const unsigned = `${enc({ alg: "RS256", typ: "JWT" })}.${enc({
    iss: SA.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore",
    aud: "https://oauth2.googleapis.com/token", iat, exp: iat + 3600,
  })}`;
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${b64url(sig)}` }),
  });
  const j = await r.json();
  if (!j.access_token) throw new Error("Google auth failed");
  tok = { v: j.access_token, exp: Date.now() + 50 * 60 * 1000 };
  return tok.v;
}

async function send(topic: string, title: string, body: string, opts: {
  image?: string; channel?: string; sound?: string; data?: Record<string, string>;
} = {}) {
  const notification: Record<string, string> = { title, body };
  if (opts.image) notification.image = opts.image;
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${PROJECT}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${await gToken()}`, "Content-Type": "application/json" },
    body: JSON.stringify({ message: {
      topic, notification, data: opts.data ?? {},
      android: { priority: "HIGH", notification: { channel_id: opts.channel ?? "totv_main", sound: opts.sound ?? "default" } },
      apns: { payload: { aps: { sound: "default", "mutable-content": 1 } } },
    } }),
  });
  if (!r.ok) throw new Error(`FCM ${r.status}: ${(await r.text()).slice(0, 200)}`);
}
const safeSend = async (...a: Parameters<typeof send>) => { try { await send(...a); return true; } catch (e) { console.warn("[fcm]", e); return false; } };
const userTopic = (uid: string) => `u_${uid.replace(/[^A-Za-z0-9_.~%-]/g, "")}`;

// ── Firestore (قراءة مستند واحد) ───────────────────────────────────
function fsVal(v: Record<string, unknown> | undefined): unknown {
  if (!v) return null;
  if ("stringValue" in v) return v.stringValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return Number(v.doubleValue);
  if ("booleanValue" in v) return v.booleanValue;
  if ("timestampValue" in v) return v.timestampValue;
  if ("mapValue" in v) {
    const f = (v.mapValue as { fields?: Record<string, Record<string, unknown>> }).fields ?? {};
    return Object.fromEntries(Object.entries(f).map(([k, x]) => [k, fsVal(x)]));
  }
  return null;
}
async function fsDoc(path: string): Promise<Record<string, unknown> | null> {
  if (!SA.private_key) return null;
  try {
    const r = await fetch(`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${path}`,
      { headers: { Authorization: `Bearer ${await gToken()}` } });
    if (!r.ok) { if (r.status !== 404) console.warn("[fs]", r.status, (await r.text()).slice(0, 160)); return null; }
    const j = await r.json();
    return Object.fromEntries(Object.entries(j.fields ?? {}).map(([k, x]) => [k, fsVal(x as Record<string, unknown>)]));
  } catch (e) { console.warn("[fs]", e); return null; }
}

// ── قاعدة Supabase بمفتاح الخدمة ───────────────────────────────────
function sbHeaders(extra: Record<string, string> = {}) {
  const h: Record<string, string> = { apikey: SB_KEY, "Content-Type": "application/json", ...extra };
  if (SB_KEY.startsWith("eyJ")) h.Authorization = `Bearer ${SB_KEY}`;
  return h;
}
async function db(path: string, init: RequestInit & { prefer?: string } = {}): Promise<unknown> {
  if (!SB_KEY) throw new HttpErr(500, "مفتاح الخدمة غير متاح للدالة");
  const r = await fetch(`${BASE}/rest/v1/${path}`, {
    ...init, headers: sbHeaders(init.prefer ? { Prefer: init.prefer } : {}),
  });
  const raw = await r.text();
  if (!r.ok) {
    if (raw.includes("does not exist") || raw.includes("PGRST205") || raw.includes("PGRST202")) {
      throw new HttpErr(500, "جداول التوقعات والمحادثة غير منشأة — شغّل 04_engagement.sql");
    }
    throw new HttpErr(502, `DB ${r.status}: ${raw.slice(0, 200)}`);
  }
  return raw ? JSON.parse(raw) : null;
}
const rpc = (fn: string, args: Record<string, unknown>) => db(`rpc/${fn}`, { method: "POST", body: JSON.stringify(args) });
const q = encodeURIComponent;

// ── التحقق من مستخدم Firebase (محلياً بمفاتيح Google العامة) ─────────
type User = { uid: string; email: string; name: string };
let jwks: { keys: Record<string, JsonWebKey>; exp: number } = { keys: {}, exp: 0 };
async function googleKeys(force = false) {
  if (!force && Date.now() < jwks.exp && Object.keys(jwks.keys).length) return jwks.keys;
  const r = await fetch("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com");
  const j = await r.json();
  const keys: Record<string, JsonWebKey> = {};
  for (const k of j.keys ?? []) keys[k.kid] = k;
  const age = Number(/max-age=(\d+)/.exec(r.headers.get("cache-control") ?? "")?.[1] ?? 3600);
  jwks = { keys, exp: Date.now() + Math.min(age, 21600) * 1000 };
  return keys;
}
async function verifyLocal(idToken: string): Promise<User | null> {
  const parts = idToken.split(".");
  if (parts.length !== 3) return null;
  const h = unjson(parts[0]), p = unjson(parts[1]);
  const now = Math.floor(Date.now() / 1000);
  if (h.alg !== "RS256" || p.aud !== PROJECT || p.iss !== `https://securetoken.google.com/${PROJECT}`) return null;
  if (!p.sub || Number(p.exp) < now - 30 || Number(p.iat) > now + 300) return null;
  let keys = await googleKeys();
  if (!keys[h.kid]) keys = await googleKeys(true);
  const jwk = keys[h.kid];
  if (!jwk) return null;
  const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, unb64(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
  return ok ? { uid: String(p.sub), email: String(p.email ?? "").toLowerCase(), name: clip(p.name, 60) } : null;
}
async function verifyLookup(idToken: string): Promise<User | null> {
  for (const key of WEB_KEYS) {
    try {
      const r = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${key}`, {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ idToken }),
      });
      if (r.ok) {
        const u = (await r.json())?.users?.[0];
        return u ? { uid: u.localId, email: String(u.email ?? "").toLowerCase(), name: clip(u.displayName, 60) } : null;
      }
      const err = await r.text();
      if (err.includes("INVALID_ID_TOKEN") || err.includes("USER_NOT_FOUND")) return null;
    } catch (e) { console.warn("[lookup]", e); }
  }
  return null;
}
async function verify(idToken: string): Promise<User | null> {
  if (!idToken || idToken.length < 100) return null;
  try { return await verifyLocal(idToken); } catch (e) {
    console.warn("[verify local]", e);
    return verifyLookup(idToken);
  }
}

// ── حدود بسيطة ضد الإغراق (لكل نسخة من الدالة) ─────────────────────
const hits = new Map<string, number[]>();
function limit(key: string, max: number, windowMs: number) {
  const now = Date.now();
  const l = (hits.get(key) ?? []).filter((t) => now - t < windowMs);
  if (l.length >= max) throw new HttpErr(429, "محاولات كثيرة — انتظر قليلاً");
  l.push(now); hits.set(key, l);
  if (hits.size > 5000) hits.clear();
}

// ── جدول المباريات (للتحقق من وقت الانطلاق) ─────────────────────────
let feed: { at: number; map: Map<number, { ts: number; h: string; a: string; lg: string }> } = { at: 0, map: new Map() };
async function feedMatch(id: number) {
  if (Date.now() - feed.at > 10 * 60 * 1000) {
    try {
      let base = Deno.env.get("SPORTS_FEED_URL") ?? "";
      if (!base) base = String((await fsDoc("app_config/remote_config"))?.sports_feed ?? "");
      base = base.trim().replace(/\/+$/, "");
      if (base) {
        const j = await (await fetch(`${base}/matches.json?b=${Math.floor(Date.now() / 600000)}`)).json();
        const lgs = j.leagues ?? {};
        const map = new Map();
        for (const m of j.matches ?? []) {
          map.set(Number(m.id), { ts: Number(m.ts), h: m.h?.ar || m.h?.n || "", a: m.a?.ar || m.a?.n || "", lg: lgs[m.lg]?.ar ?? "" });
        }
        feed = { at: Date.now(), map };
      }
    } catch (e) { console.warn("[feed]", e); feed.at = Date.now() - 8 * 60 * 1000; }
  }
  return feed.map.get(id) ?? null;
}

// ── المحادثة ───────────────────────────────────────────────────────
async function post(uid: string, sender: "user" | "admin" | "auto", body: string, meta: { email?: string; name?: string; kind?: string } = {}) {
  return await rpc("eng_chat_post", {
    p_uid: uid, p_sender: sender, p_body: body,
    p_email: meta.email ?? "", p_name: meta.name ?? "", p_kind: meta.kind ?? "text",
  });
}
async function tellUser(uid: string, body: string, opts: { kind?: string; title?: string; email?: string; name?: string } = {}) {
  const m = await post(uid, "auto", body, { kind: opts.kind ?? "auto", email: opts.email, name: opts.name });
  await safeSend(userTopic(uid), opts.title ?? "رسالة من TOTV+", clip(body, 180), { data: { type: "chat" } });
  return m;
}

const sentOrders = new Map<string, number>();
const lastOrder = new Map<string, number>();

// ════════════════════════════════════════════════════════════════════
Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method === "GET" && url.pathname.endsWith("/health")) {
    return json({
      ok: true, v: VERSION,
      fcm: !!(SA.client_email && SA.private_key && SA.project_id),
      project: SA.project_id ?? null,
      admins: ADMINS.length,
      db: !!SB_KEY,
    });
  }
  if (req.method === "GET" && url.pathname.endsWith("/icon.png")) {
    return new Response(Uint8Array.from(atob(ICON_PNG), (c) => c.charCodeAt(0)),
      { headers: { ...cors, "Content-Type": "image/png", "Cache-Control": "public, max-age=604800" } });
  }
  if (req.method !== "POST") return json({ error: "method" }, 405);
  if (!SA.private_key) return json({ error: "FCM_SERVICE_ACCOUNT غير مضبوط" }, 500);

  let b: Record<string, unknown>;
  try { b = await req.json(); } catch { return json({ error: "bad json" }, 400); }
  const action = String(b.action ?? "");

  try {
    // ════ طلب اشتراك جديد ⇐ إشعار الإدارة ═════════════════════════════
    //  يُقرأ الطلب من Firestore نفسه (بيانات موثوقة)، فلا يتوقف الإشعار
    //  حتى لو تعذّر التحقق من توكن المستخدم.
    if (action === "order") {
      const oid = clip(b.order_id, 80).replace(/[^A-Za-z0-9_-]/g, "");
      if (oid && sentOrders.has(oid)) return json({ ok: true, skipped: "dup" });
      const o = oid ? await fsDoc(`orders/${oid}`) : null;
      let parts: string[];
      if (o) {
        if (o.status && o.status !== "pending") return json({ ok: true, skipped: "not_pending" });
        const created = Date.parse(String(o.created ?? "")) || Date.now();
        if (Date.now() - created > 6 * 3600 * 1000) return json({ ok: true, skipped: "old" });
        parts = [clip(o.name, 40), clip(o.plan_title ?? o.plan, 20), o.price ? `${clip(o.price, 12)} د.ع` : "", clip(o.method, 20)];
      } else {
        const user = await verify(String(b.idToken ?? ""));
        if (!user) return json({ error: "unauthorized" }, 401);
        const now = Date.now();
        if (now - (lastOrder.get(user.uid) ?? 0) < 45_000) return json({ ok: true, skipped: "rate" });
        lastOrder.set(user.uid, now);
        parts = [clip(b.name, 40), clip(b.plan, 20), b.price ? `${clip(b.price, 12)} د.ع` : "", clip(b.method, 20)];
      }
      if (oid) { sentOrders.set(oid, Date.now()); if (sentOrders.size > 2000) sentOrders.clear(); }
      await send("admin_orders", "📥 لديك طلب اشتراك — يرجى التفعيل", parts.filter(Boolean).join(" • ") || "طلب جديد", {
        channel: "admin_orders", sound: "cash",
        data: { type: "order", order_id: oid },
      });
      return json({ ok: true, source: o ? "firestore" : "client" });
    }

    const user = await verify(String(b.idToken ?? ""));
    if (!user) return json({ error: "unauthorized" }, 401);
    const isAdmin = ADMINS.includes(user.email);
    const meta = { email: user.email, name: clip(b.my_name, 60) || user.name };

    // ════ أوامر المستخدم ══════════════════════════════════════════════
    switch (action) {
      case "predict": {
        limit(`p:${user.uid}`, 12, 60_000);
        const id = int(b.match_id);
        const hg = int(b.h, -1), ag = int(b.a, -1);
        if (!id || hg < 0 || ag < 0 || hg > 30 || ag > 30) throw new HttpErr(400, "النتيجة غير صحيحة");
        const fm = await feedMatch(id);
        const ts = fm?.ts ?? int(b.ts);
        if (!ts) throw new HttpErr(400, "المباراة غير معروفة");
        const now = Date.now() / 1000;
        if (now < ts - 30 * 60) throw new HttpErr(409, "التوقع يُفتح قبل انطلاق المباراة بـ 30 دقيقة");
        if (now >= ts) throw new HttpErr(409, "انطلقت المباراة — أُغلق التوقع");
        await db("predictions?on_conflict=match_id,uid", {
          method: "POST", prefer: "resolution=merge-duplicates,return=minimal",
          body: JSON.stringify({
            match_id: id, uid: user.uid, email: user.email, name: meta.name,
            home_goals: hg, away_goals: ag,
            home_name: fm?.h || clip(b.home_name, 60), away_name: fm?.a || clip(b.away_name, 60),
            league: fm?.lg || clip(b.league, 60),
            kickoff: new Date(ts * 1000).toISOString(), status: "open", updated_at: new Date().toISOString(),
          }),
        });
        return json({ ok: true, stats: await rpc("eng_match_stats", { p_match: id }) });
      }
      case "pred_get": {
        const id = int(b.match_id);
        const rows = await db(`predictions?select=home_goals,away_goals,status&match_id=eq.${id}&uid=eq.${q(user.uid)}`) as unknown[];
        return json({ ok: true, mine: rows[0] ?? null, stats: await rpc("eng_match_stats", { p_match: id }) });
      }
      case "ref_me": {
        const code = await rpc("eng_ref_code", { p_uid: user.uid, p_email: user.email, p_name: meta.name });
        const mine = await db(`referrals?select=status&referrer_uid=eq.${q(user.uid)}`) as { status: string }[];
        const me = await db(`referrals?select=code&friend_uid=eq.${q(user.uid)}`) as { code: string }[];
        return json({
          ok: true, code,
          joined: mine.length,
          subscribed: mine.filter((r) => r.status === "subscribed" || r.status === "rewarded").length,
          rewarded: mine.filter((r) => r.status === "rewarded").length,
          used_code: me[0]?.code ?? "",
        });
      }
      case "ref_apply": {
        limit(`r:${user.uid}`, 6, 10 * 60_000);
        const code = clip(b.code, 12).toUpperCase().replace(/[^A-Z0-9]/g, "");
        if (code.length < 4) throw new HttpErr(400, "اكتب كود الدعوة كاملاً");
        const owner = (await db(`referral_codes?select=uid,name,email&code=eq.${q(code)}`) as Record<string, string>[])[0];
        if (!owner) throw new HttpErr(404, "الكود غير صحيح");
        if (owner.uid === user.uid) throw new HttpErr(409, "لا يمكنك استخدام كودك");
        const had = await db(`referrals?select=code&friend_uid=eq.${q(user.uid)}`) as unknown[];
        if (had.length) throw new HttpErr(409, "استخدمت كود دعوة من قبل");
        const subbed = await db(`subscriptions?select=uid&uid=eq.${q(user.uid)}`) as unknown[];
        if (subbed.length) throw new HttpErr(409, "الدعوة للمستخدمين الجدد فقط (قبل أول اشتراك)");
        await db("referrals", { method: "POST", prefer: "return=minimal", body: JSON.stringify({
          friend_uid: user.uid, code, referrer_uid: owner.uid, friend_email: user.email, friend_name: meta.name,
        }) });
        return json({ ok: true, referrer: owner.name || (owner.email ?? "").split("@")[0] });
      }
      case "chat_list": {
        const before = int(b.before);
        const rows = await db(`chat_messages?select=id,sender,body,kind,created_at&uid=eq.${q(user.uid)}` +
          `${before ? `&id=lt.${before}` : ""}&order=id.desc&limit=40`);
        if (!before) await rpc("eng_chat_read", { p_uid: user.uid, p_side: "user" });
        return json({ ok: true, messages: rows });
      }
      case "chat_send": {
        limit(`c:${user.uid}`, 8, 60_000);
        const body = text(b.text, 1500);
        if (!body) throw new HttpErr(400, "الرسالة فارغة");
        const m = await post(user.uid, "user", body, meta);
        await safeSend("admins", `💬 ${meta.name || user.email || "مستخدم"}`, clip(body, 160), {
          channel: "admin_chat", data: { type: "chat", uid: user.uid },
        });
        return json({ ok: true, message: m });
      }
    }

    // ════ أوامر الإدارة ═══════════════════════════════════════════════
    if (!action.startsWith("admin_") && action !== "broadcast" && action !== "ref_on_order") {
      return json({ error: "unknown action" }, 400);
    }
    if (!isAdmin) return json({ error: "forbidden" }, 403);

    switch (action) {
      case "broadcast": {
        const topic = TOPICS.has(String(b.topic)) ? String(b.topic) : "all_users";
        const title = clip(b.title, 80), body = clip(b.body, 300);
        if (!title || !body) return json({ error: "title/body required" }, 400);
        const img = String(b.image ?? "").trim();
        const kind = b.kind === "live" ? "live" : "broadcast";   // live ⇐ الضغط يفتح قناة TOTV Live
        await send(topic, title, body, { image: /^https:\/\/\S+$/.test(img) ? img : ICON, data: { type: kind } });
        return json({ ok: true, topic });
      }
      case "admin_test_order": {
        await send("admin_orders", "📥 طلب تجريبي — الإشعارات تعمل ✅", "هذا اختبار من فحص النظام", {
          channel: "admin_orders", sound: "cash", data: { type: "order", order_id: "" },
        });
        return json({ ok: true });
      }
      case "admin_threads": {
        const s = clip(b.q, 60).replace(/[,()*]/g, "");
        const f = s ? `&or=(name.ilike.*${q(s)}*,email.ilike.*${q(s)}*,uid.eq.${q(s)})` : "";
        const unread = b.unread === true ? "&unread_admin=gt.0" : "";
        const rows = await db(`chat_threads?select=*${f}${unread}&order=last_at.desc&limit=${Math.min(int(b.limit, 80), 200)}`);
        return json({ ok: true, threads: rows });
      }
      case "admin_messages": {
        const uid = clip(b.uid, 128);
        const before = int(b.before);
        const rows = await db(`chat_messages?select=id,sender,body,kind,created_at&uid=eq.${q(uid)}` +
          `${before ? `&id=lt.${before}` : ""}&order=id.desc&limit=50`);
        if (!before) await rpc("eng_chat_read", { p_uid: uid, p_side: "admin" });
        const th = await db(`chat_threads?select=*&uid=eq.${q(uid)}`) as unknown[];
        return json({ ok: true, messages: rows, thread: th[0] ?? null });
      }
      case "admin_send": {
        const uids = (Array.isArray(b.uids) ? b.uids : [b.uid]).map((x) => clip(x, 128)).filter(Boolean).slice(0, 300);
        const body = text(b.text, 1500);
        if (!uids.length || !body) throw new HttpErr(400, "اختر المستخدم واكتب الرسالة");
        const sender = b.auto === true ? "auto" : "admin";
        let last: unknown = null, sent = 0;
        for (const uid of uids) {
          last = await post(uid, sender, body, { kind: clip(b.kind, 20) || "text", email: uids.length === 1 ? clip(b.email, 120) : "", name: uids.length === 1 ? clip(b.name, 60) : "" });
          if (await safeSend(userTopic(uid), clip(b.title, 60) || "رسالة من إدارة TOTV+", clip(body, 180), { data: { type: "chat" } })) sent++;
        }
        return json({ ok: true, message: last, count: uids.length, pushed: sent });
      }
      case "admin_rewards":
        return json({ ok: true, ...(await rpc("eng_rewards", { p_limit: Math.min(int(b.limit, 200), 500) }) as Record<string, unknown>) });
      case "admin_settle": {
        const id = int(b.match_id), hg = int(b.h, -1), ag = int(b.a, -1);
        if (!id || hg < 0 || ag < 0) throw new HttpErr(400, "النتيجة غير صحيحة");
        const r = await rpc("eng_settle", {
          p_match: id, p_home: hg, p_away: ag, p_home_name: clip(b.home_name, 60), p_away_name: clip(b.away_name, 60),
          p_league: clip(b.league, 60), p_kickoff: b.ts ? new Date(int(b.ts) * 1000).toISOString() : null,
        }) as Record<string, number>;
        let told = 0;
        if (b.notify !== false) {
          const won = await db(`predictions?select=uid,email,name,home_name,away_name&match_id=eq.${id}&status=eq.won&rewarded=eq.false&limit=300`) as Record<string, string>[];
          for (const w of won) {
            await tellUser(w.uid, `🎯 مبروك! توقعك صحيح لمباراة ${w.home_name} × ${w.away_name} (${hg}-${ag}).\nفزت بيوم مجاني، وسيُضاف إلى حسابك قريباً.`,
              { kind: "prize", title: "🎉 فزت في التوقعات!", email: w.email, name: w.name });
            told++;
          }
        }
        return json({ ok: true, ...r, notified: told });
      }
      case "admin_reward_done": {
        const uid = clip(b.uid, 128);
        const days = int(b.days);
        if (b.kind === "ref") {
          await db(`referrals?friend_uid=eq.${q(clip(b.friend_uid, 128))}`, { method: "PATCH", prefer: "return=minimal",
            body: JSON.stringify({ status: "rewarded", rewarded_at: new Date().toISOString() }) });
          if (b.notify !== false) await tellUser(uid, `🎁 شكراً لدعوتك! اشترك صديقك، وأُضيف إلى اشتراكك ${days || 16} يوماً مجاناً.`, { kind: "prize", title: "🎁 جائزة الدعوة" });
        } else {
          await db(`predictions?match_id=eq.${int(b.match_id)}&uid=eq.${q(uid)}`, { method: "PATCH", prefer: "return=minimal",
            body: JSON.stringify({ rewarded: true, rewarded_at: new Date().toISOString() }) });
          if (b.notify !== false) await tellUser(uid, `✅ أُضيفت جائزتك: ${days || 1} يوم مجاني إلى اشتراكك. استمر في التوقع!`, { kind: "prize", title: "✅ أُضيفت جائزتك" });
        }
        return json({ ok: true });
      }
      case "ref_on_order": {
        // عند قبول طلب اشتراك: إن كان صاحبه مدعوّاً ⇐ تصبح الدعوة «اشترك» وتظهر جائزة الداعي
        const fuid = clip(b.uid, 128);
        const rows = await db(`referrals?select=*&friend_uid=eq.${q(fuid)}`) as Record<string, string>[];
        const r = rows[0];
        if (!r) return json({ ok: true, referral: null });
        if (r.status === "joined") {
          await db(`referrals?friend_uid=eq.${q(fuid)}`, { method: "PATCH", prefer: "return=minimal",
            body: JSON.stringify({ status: "subscribed", subscribed_at: new Date().toISOString(), order_id: clip(b.order_id, 80) }) });
          r.status = "subscribed";
        }
        const owner = (await db(`referral_codes?select=uid,email,name&uid=eq.${q(r.referrer_uid)}`) as Record<string, string>[])[0] ?? {};
        return json({ ok: true, referral: { ...r, referrer_email: owner.email ?? "", referrer_name: owner.name ?? "" } });
      }
      case "admin_auto_expiring": {
        // يستدعيه بوت تطبيق الإدارة: رسالة تذكير واحدة لكل اشتراك ينتهي خلال 3 أيام
        const list = await rpc("eng_expiring", { p_days: Math.min(Math.max(int(b.days, 3), 1), 7) }) as Record<string, string>[];
        let n = 0;
        for (const s of list.slice(0, 200)) {
          const exp = new Date(s.expiry_date);
          const ref = exp.toISOString().slice(0, 10);
          const d = Math.max(0, Math.ceil((exp.getTime() - Date.now()) / 864e5));
          await db("auto_notices", { method: "POST", prefer: "resolution=ignore-duplicates,return=minimal",
            body: JSON.stringify({ uid: s.uid, kind: "expiring", ref }) });
          await tellUser(s.uid, `⏰ تنبيه: ينتهي اشتراكك ${d <= 1 ? "خلال يوم" : `خلال ${d} أيام`} (${ref}).\nجدّد الآن حتى لا ينقطع البث — اضغط «اشترك» من صفحة المزيد.`,
            { kind: "expiring", title: "⏰ اشتراكك ينتهي قريباً", email: s.email, name: s.name });
          n++;
        }
        return json({ ok: true, sent: n });
      }
    }
    return json({ error: "unknown action" }, 400);
  } catch (e) {
    if (e instanceof HttpErr) return json({ error: e.message }, e.code);
    return json({ error: String((e as Error).message ?? e) }, 502);
  }
});

// أيقونة TOTV+ (192×192 PNG)
const ICON_PNG = "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";

// ════════════════════════════════════════════════════════════════════
//  TOTV+ push — Supabase Edge Function (مجانية: 500 ألف استدعاء/شهر)
//
//  • action:"order"     ← تطبيق TOTV+ بعد إرسال طلب اشتراك
//                         ⇒ إشعار فوري لتطبيق الإدارة (topic: admin_orders)
//  • action:"broadcast" ← تطبيق الإدارة (المشرف فقط)
//                         ⇒ إشعار فوري لكل المستخدمين بصورة أيقونة TOTV+
//  • GET /push/icon.png ← أيقونة التطبيق (صورة الإشعار الافتراضية)
//
//  الحماية: كل طلب يحمل Firebase ID Token ويُتحقق منه هنا.
//  الإرسال للجميع مسموح فقط للبريد المذكور في ADMIN_EMAILS.
//  مفتاح Firebase يبقى هنا في Secrets — لا يدخل أي تطبيق.
//
//  Secrets المطلوبة (Edge Functions → Secrets):
//    FCM_SERVICE_ACCOUNT   ملف JSON لحساب خدمة بدور «Firebase Cloud Messaging API Admin»
//    ADMIN_EMAILS          مثال: haedirasso@gmail.com,admin@totv.com
//  اختياري:
//    FIREBASE_WEB_API_KEY  (الافتراضي مفتاح مشروع totvq-8e439 العام)
//    ICON_URL              صورة إشعار مختلفة
//  مهم: أوقف «Enforce JWT verification» لهذه الدالة (نتحقق بأنفسنا).
// ════════════════════════════════════════════════════════════════════

const SA = (() => { try { return JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}"); } catch { return {}; } })();
// مفاتيح Firebase العامة لنفس المشروع (الويب ثم أندرويد) — تُجرَّب بالترتيب إن كان أحدها مقيّداً
const WEB_KEYS = [Deno.env.get("FIREBASE_WEB_API_KEY"), "AIzaSyCk0dSmHGQ248b-OQi44Rm2zWrfbpLBkpU", "AIzaSyBR9NjEZHm9RhngSfYNMmphaH_gDLTApTY"]
  .filter((k): k is string => !!k);
const ADMINS = (Deno.env.get("ADMIN_EMAILS") ?? "").toLowerCase().split(",").map((s) => s.trim()).filter(Boolean);
const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const ICON = Deno.env.get("ICON_URL") || `${BASE}/functions/v1/push/icon.png`;
const TOPICS = new Set(["all_users", "matches", "admins"]);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const clip = (v: unknown, n: number) => String(v ?? "").replace(/\s+/g, " ").trim().slice(0, n);

// ── توكن FCM (يُخزّن ساعة) ─────────────────────────────────────────
const b64url = (b: ArrayBuffer | Uint8Array) =>
  btoa(String.fromCharCode(...new Uint8Array(b as ArrayBuffer))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));
let tok = { v: "", exp: 0 };

async function fcmToken(): Promise<string> {
  if (tok.v && Date.now() < tok.exp) return tok.v;
  const pem = String(SA.private_key ?? "").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const iat = Math.floor(Date.now() / 1000);
  const unsigned = `${enc({ alg: "RS256", typ: "JWT" })}.${enc({
    iss: SA.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token", iat, exp: iat + 3600,
  })}`;
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${b64url(sig)}` }),
  });
  const j = await r.json();
  if (!j.access_token) throw new Error("FCM auth failed");
  tok = { v: j.access_token, exp: Date.now() + 50 * 60 * 1000 };
  return tok.v;
}

async function send(topic: string, title: string, body: string, opts: {
  image?: string; channel?: string; sound?: string; data?: Record<string, string>;
} = {}) {
  const notification: Record<string, string> = { title, body };
  if (opts.image) notification.image = opts.image;
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${SA.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${await fcmToken()}`, "Content-Type": "application/json" },
    body: JSON.stringify({ message: {
      topic, notification, data: opts.data ?? {},
      android: { priority: "HIGH", notification: { channel_id: opts.channel ?? "totv_main", sound: opts.sound ?? "default" } },
      apns: { payload: { aps: { sound: "default", "mutable-content": 1 } } },
    } }),
  });
  if (!r.ok) throw new Error(`FCM ${r.status}: ${(await r.text()).slice(0, 200)}`);
}

// ── التحقق من مستخدم Firebase ───────────────────────────────────────
async function verify(idToken: string): Promise<{ uid: string; email: string } | null> {
  if (!idToken || idToken.length < 100) return null;
  for (const key of WEB_KEYS) {
    try {
      const r = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${key}`, {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ idToken }),
      });
      if (r.ok) {
        const u = (await r.json())?.users?.[0];
        return u ? { uid: u.localId, email: String(u.email ?? "").toLowerCase() } : null;
      }
      const err = await r.text();
      if (err.includes("INVALID_ID_TOKEN") || err.includes("USER_NOT_FOUND")) return null;  // التوكن نفسه غير صالح
      console.warn("[verify] key rejected, trying next:", err.slice(0, 120));
    } catch (e) { console.warn("[verify]", e); }
  }
  return null;
}

const lastOrder = new Map<string, number>();   // حد: طلب واحد كل 45 ثانية لكل مستخدم

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  // فحص سريع من تطبيق الإدارة: هل الدالة منشورة وهل الأسرار مضبوطة؟
  if (req.method === "GET" && url.pathname.endsWith("/health")) {
    return json({
      ok: true,
      fcm: !!(SA.client_email && SA.private_key && SA.project_id),
      project: SA.project_id ?? null,
      admins: ADMINS.length,
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
  const user = await verify(String(b.idToken ?? ""));
  if (!user) return json({ error: "unauthorized" }, 401);

  try {
    if (b.action === "order") {
      const now = Date.now();
      if (now - (lastOrder.get(user.uid) ?? 0) < 45_000) return json({ ok: true, skipped: "rate" });
      lastOrder.set(user.uid, now);
      const parts = [clip(b.name, 40), clip(b.plan, 20), b.price ? `${clip(b.price, 12)} د.ع` : "", clip(b.method, 20)]
        .filter(Boolean);
      await send("admin_orders", "📥 لديك طلب اشتراك — يرجى التفعيل", parts.join(" • ") || user.email, {
        channel: "admin_orders", sound: "cash",
        data: { type: "order", order_id: clip(b.order_id, 40) },
      });
      return json({ ok: true });
    }

    if (b.action === "broadcast") {
      if (!ADMINS.includes(user.email)) return json({ error: "forbidden" }, 403);
      const topic = TOPICS.has(String(b.topic)) ? String(b.topic) : "all_users";
      const title = clip(b.title, 80), body = clip(b.body, 300);
      if (!title || !body) return json({ error: "title/body required" }, 400);
      const img = String(b.image ?? "").trim();
      await send(topic, title, body, {
        image: /^https:\/\/\S+$/.test(img) ? img : ICON,
        data: { type: "broadcast" },
      });
      return json({ ok: true, topic });
    }
    return json({ error: "unknown action" }, 400);
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 502);
  }
});

// أيقونة TOTV+ (192×192 PNG)
const ICON_PNG = "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";

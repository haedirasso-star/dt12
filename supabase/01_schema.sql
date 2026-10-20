-- ════════════════════════════════════════════════════════════════════
--  TOTV+ — مخطّط Supabase الكامل  (نظام أكواد التفعيل والاشتراكات)
--  الصق هذا الملف كاملاً في:  Supabase → SQL Editor → New query → Run
--  آمن للتشغيل أكثر من مرة (idempotent).
-- ════════════════════════════════════════════════════════════════════

-- ── 1) جدول أكواد التفعيل ──────────────────────────────────────────
create table if not exists public.activation_codes (
  code            text primary key,
  batch_id        text,
  host            text not null,
  username        text not null,
  password        text not null,
  plan            text not null default 'monthly',
  days            int  not null default 30,
  status          text not null default 'unused',   -- unused | used | disabled
  used            boolean not null default false,
  disabled        boolean not null default false,
  agent           text default '',
  note            text default '',

  -- بيانات المشترك تُكتب هنا لحظة التفعيل
  used_by_uid     text,
  used_by_email   text,
  used_by_name    text,
  used_device_id  text,
  used_platform   text,
  used_app_ver    text,
  used_at         timestamptz,
  expiry_date     timestamptz,
  last_seen_at    timestamptz,

  created_by      text,
  created_at      timestamptz not null default now()
);

-- ── 2) جدول الاشتراكات (سجل واحد لكل مستخدم) ───────────────────────
create table if not exists public.subscriptions (
  uid             text primary key,          -- Firebase UID
  email           text,
  display_name    text,
  plan            text not null default 'premium',
  tier            text,
  duration_days   int,
  code            text references public.activation_codes(code) on delete set null,
  host            text,
  username        text,
  password        text,
  expiry_date     timestamptz,
  activated_at    timestamptz default now(),
  device_id       text,
  platform        text,
  app_version     text,
  agent           text,
  updated_at      timestamptz default now()
);

-- ── 3) سجل عمليات التفعيل ──────────────────────────────────────────
create table if not exists public.activation_log (
  id          bigserial primary key,
  uid         text,
  email       text,
  code        text,
  host        text,
  plan        text,
  days        int,
  device_id   text,
  platform    text,
  result      text,                          -- ok | error code
  created_at  timestamptz not null default now()
);

-- ── 4) كبح محاولات التخمين ─────────────────────────────────────────
create table if not exists public.redeem_attempts (
  actor       text primary key,              -- uid أو device_id
  fails       int not null default 0,
  last_fail   timestamptz not null default now()
);

-- ── 5) قائمة المشرفين ──────────────────────────────────────────────
create table if not exists public.admins (
  email  text primary key,
  role   text not null default 'admin',
  added_at timestamptz default now()
);

-- ⚠️ غيّر هذا الإيميل إلى إيميلك في Supabase Auth
insert into public.admins (email, role) values
  ('haedirasso@gmail.com', 'super'),
  ('admin@totv.com',       'super')
on conflict (email) do nothing;

-- ── 6) الفهارس ─────────────────────────────────────────────────────
create index if not exists idx_codes_status     on public.activation_codes(status);
create index if not exists idx_codes_used       on public.activation_codes(used);
create index if not exists idx_codes_email      on public.activation_codes(used_by_email);
create index if not exists idx_codes_uid        on public.activation_codes(used_by_uid);
create index if not exists idx_codes_created    on public.activation_codes(created_at desc);
create index if not exists idx_codes_batch      on public.activation_codes(batch_id);
create index if not exists idx_subs_email       on public.subscriptions(email);
create index if not exists idx_subs_expiry      on public.subscriptions(expiry_date);
create index if not exists idx_log_created      on public.activation_log(created_at desc);

-- ════════════════════════════════════════════════════════════════════
--  7) الحماية — RLS مفعّل على كل الجداول
--     التطبيق لا يلمس الجداول مباشرةً إطلاقاً، بل عبر الدوال فقط.
-- ════════════════════════════════════════════════════════════════════
alter table public.activation_codes enable row level security;
alter table public.subscriptions    enable row level security;
alter table public.activation_log   enable row level security;
alter table public.redeem_attempts  enable row level security;
alter table public.admins           enable row level security;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.admins
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

drop policy if exists p_codes_admin on public.activation_codes;
create policy p_codes_admin on public.activation_codes
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists p_subs_admin on public.subscriptions;
create policy p_subs_admin on public.subscriptions
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists p_log_admin on public.activation_log;
create policy p_log_admin on public.activation_log
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists p_admins_read on public.admins;
create policy p_admins_read on public.admins
  for select using (public.is_admin());

-- لا سياسة لـ anon على أي جدول ⇒ التطبيق لا يستطيع قراءة أو سرد
-- أي كود أو اشتراك مباشرةً. المنفذ الوحيد هو الدوال أدناه.

-- ════════════════════════════════════════════════════════════════════
--  8) الدالة الرئيسية: تفعيل كود
--     ذرّية بالكامل — كودٌ واحد لا يُفعَّل من جهازين أبداً.
-- ════════════════════════════════════════════════════════════════════
create or replace function public.redeem_code(
  p_code     text,
  p_uid      text,
  p_email    text default '',
  p_name     text default '',
  p_device   text default '',
  p_platform text default '',
  p_appver   text default ''
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c        public.activation_codes%rowtype;
  v_code   text := upper(regexp_replace(coalesce(p_code,''), '[^A-Za-z0-9]', '', 'g'));
  v_expiry timestamptz;
  v_fails  int;
begin
  if p_uid is null or length(p_uid) < 6 then
    return jsonb_build_object('ok', false, 'error', 'NO_UID');
  end if;
  if length(v_code) < 8 then
    return jsonb_build_object('ok', false, 'error', 'BAD_FORMAT');
  end if;

  -- كبح التخمين: 10 محاولات فاشلة ⇒ إيقاف 15 دقيقة
  select fails into v_fails from public.redeem_attempts
    where actor = p_uid and last_fail > now() - interval '15 minutes';
  if coalesce(v_fails, 0) >= 10 then
    return jsonb_build_object('ok', false, 'error', 'TOO_MANY');
  end if;

  -- القفل الذرّي: أول من يصل يفوز
  select * into c from public.activation_codes
    where code = v_code for update;

  if not found then
    insert into public.redeem_attempts(actor, fails, last_fail)
      values (p_uid, 1, now())
      on conflict (actor) do update
        set fails = public.redeem_attempts.fails + 1, last_fail = now();
    insert into public.activation_log(uid, email, code, device_id, result)
      values (p_uid, p_email, v_code, p_device, 'NOT_FOUND');
    return jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
  end if;

  if c.disabled or c.status = 'disabled' then
    return jsonb_build_object('ok', false, 'error', 'DISABLED');
  end if;

  if c.used and c.used_by_uid is distinct from p_uid then
    insert into public.redeem_attempts(actor, fails, last_fail)
      values (p_uid, 1, now())
      on conflict (actor) do update
        set fails = public.redeem_attempts.fails + 1, last_fail = now();
    return jsonb_build_object('ok', false, 'error', 'USED');
  end if;

  -- نفس المستخدم يعيد التفعيل ⇒ نفس التاريخ (لا تمديد بالخداع)
  if c.used and c.used_by_uid = p_uid and c.expiry_date is not null then
    v_expiry := c.expiry_date;
  else
    v_expiry := now() + (c.days || ' days')::interval;
  end if;

  if v_expiry <= now() then
    return jsonb_build_object('ok', false, 'error', 'EXPIRED');
  end if;

  update public.activation_codes set
    used = true, status = 'used',
    used_by_uid = p_uid, used_by_email = lower(p_email), used_by_name = p_name,
    used_device_id = p_device, used_platform = p_platform, used_app_ver = p_appver,
    used_at = coalesce(used_at, now()),
    expiry_date = v_expiry, last_seen_at = now()
  where code = v_code;

  insert into public.subscriptions (
    uid, email, display_name, plan, tier, duration_days, code,
    host, username, password, expiry_date, activated_at,
    device_id, platform, app_version, agent, updated_at)
  values (
    p_uid, lower(p_email), p_name, 'premium', c.plan, c.days, v_code,
    c.host, c.username, c.password, v_expiry, now(),
    p_device, p_platform, p_appver, c.agent, now())
  on conflict (uid) do update set
    email = excluded.email, display_name = excluded.display_name,
    plan = 'premium', tier = excluded.tier,
    duration_days = excluded.duration_days, code = excluded.code,
    host = excluded.host, username = excluded.username, password = excluded.password,
    expiry_date = excluded.expiry_date, activated_at = excluded.activated_at,
    device_id = excluded.device_id, platform = excluded.platform,
    app_version = excluded.app_version, agent = excluded.agent, updated_at = now();

  delete from public.redeem_attempts where actor = p_uid;

  insert into public.activation_log(uid, email, code, host, plan, days, device_id, platform, result)
    values (p_uid, lower(p_email), v_code, c.host, c.plan, c.days, p_device, p_platform, 'ok');

  return jsonb_build_object(
    'ok', true, 'plan', c.plan, 'days', c.days,
    'host', c.host, 'username', c.username, 'password', c.password,
    'expiry', v_expiry, 'code', v_code);
end; $$;

-- ════════════════════════════════════════════════════════════════════
--  9) استعادة الاشتراك بعد تسجيل الخروج / إعادة التثبيت
-- ════════════════════════════════════════════════════════════════════
create or replace function public.get_subscription(p_uid text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.subscriptions%rowtype;
begin
  if p_uid is null or length(p_uid) < 6 then
    return jsonb_build_object('ok', false, 'error', 'NO_UID');
  end if;

  select * into s from public.subscriptions where uid = p_uid;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NONE');
  end if;
  if s.expiry_date is not null and s.expiry_date <= now() then
    return jsonb_build_object('ok', false, 'error', 'EXPIRED',
                              'expiry', s.expiry_date);
  end if;

  update public.subscriptions set updated_at = now() where uid = p_uid;

  return jsonb_build_object(
    'ok', true, 'plan', s.plan, 'tier', s.tier, 'days', s.duration_days,
    'host', s.host, 'username', s.username, 'password', s.password,
    'expiry', s.expiry_date, 'code', s.code);
end; $$;

-- ── 10) الصلاحيات: التطبيق ينفّذ دالتين فقط، ولا يرى الجداول ────────
revoke all on public.activation_codes from anon, authenticated;
revoke all on public.subscriptions    from anon, authenticated;
revoke all on public.activation_log   from anon, authenticated;
revoke all on public.redeem_attempts  from anon, authenticated;

grant execute on function public.redeem_code(text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.get_subscription(text) to anon, authenticated;

-- ════════════════════════════════════════════════════════════════════
--  انتهى. شغّل الآن 02_admin_functions.sql
-- ════════════════════════════════════════════════════════════════════

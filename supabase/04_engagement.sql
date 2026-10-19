-- ════════════════════════════════════════════════════════════════════
--  TOTV+ — التوقعات · الدعوات · المحادثة   (شغّله مرة واحدة في SQL Editor)
--
--  • لا يقرأ التطبيق ولا يكتب في هذه الجداول مباشرة: كل شيء يمر عبر دالة
--    push (Edge Function) التي تتحقق من حساب Firebase ثم تكتب بمفتاح الخدمة.
--  • RLS مفعّل بلا سياسات ⇐ المفتاح العام (publishable) لا يصل إليها إطلاقاً.
--  • آمن لإعادة التشغيل (if not exists / or replace).
-- ════════════════════════════════════════════════════════════════════

-- ── 1) توقعات المباريات ─────────────────────────────────────────────
create table if not exists public.predictions (
  match_id    bigint      not null,
  uid         text        not null,
  email       text        default '',
  name        text        default '',
  home_goals  int         not null check (home_goals between 0 and 30),
  away_goals  int         not null check (away_goals between 0 and 30),
  home_name   text        default '',
  away_name   text        default '',
  league      text        default '',
  kickoff     timestamptz not null,
  status      text        not null default 'open',      -- open | won | lost
  rewarded    boolean     not null default false,
  rewarded_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (match_id, uid)
);
create index if not exists predictions_uid_idx    on public.predictions (uid, created_at desc);
create index if not exists predictions_status_idx on public.predictions (status, rewarded);

create table if not exists public.match_results (
  match_id    bigint primary key,
  home_goals  int  not null,
  away_goals  int  not null,
  home_name   text default '',
  away_name   text default '',
  league      text default '',
  kickoff     timestamptz,
  total       int  default 0,
  winners     int  default 0,
  settled_at  timestamptz default now()
);

-- ── 2) الدعوات ──────────────────────────────────────────────────────
create table if not exists public.referral_codes (
  code        text primary key,
  uid         text unique not null,
  email       text default '',
  name        text default '',
  created_at  timestamptz default now()
);

create table if not exists public.referrals (
  friend_uid    text primary key,             -- كل صديق يُحتسب مرة واحدة فقط
  code          text not null,
  referrer_uid  text not null,
  friend_email  text default '',
  friend_name   text default '',
  order_id      text default '',
  status        text not null default 'joined', -- joined | subscribed | rewarded | rejected
  created_at    timestamptz default now(),
  subscribed_at timestamptz,
  rewarded_at   timestamptz
);
create index if not exists referrals_ref_idx    on public.referrals (referrer_uid);
create index if not exists referrals_status_idx on public.referrals (status);

-- ── 3) المحادثة ─────────────────────────────────────────────────────
create table if not exists public.chat_threads (
  uid           text primary key,
  email         text default '',
  name          text default '',
  last_text     text default '',
  last_from     text default '',
  last_at       timestamptz default now(),
  unread_admin  int  default 0,
  unread_user   int  default 0
);
create index if not exists chat_threads_last_idx on public.chat_threads (last_at desc);

create table if not exists public.chat_messages (
  id          bigserial primary key,
  uid         text not null,
  sender      text not null check (sender in ('user', 'admin', 'auto')),
  body        text not null check (char_length(body) between 1 and 2000),
  kind        text not null default 'text',
  created_at  timestamptz not null default now()
);
create index if not exists chat_messages_uid_idx on public.chat_messages (uid, id desc);

-- رسائل تلقائية أُرسلت (حتى لا تتكرر): مثل «ينتهي اشتراكك خلال 3 أيام»
create table if not exists public.auto_notices (
  uid         text not null,
  kind        text not null,
  ref         text not null,
  created_at  timestamptz default now(),
  primary key (uid, kind, ref)
);

alter table public.predictions    enable row level security;
alter table public.match_results  enable row level security;
alter table public.referral_codes enable row level security;
alter table public.referrals      enable row level security;
alter table public.chat_threads   enable row level security;
alter table public.chat_messages  enable row level security;
alter table public.auto_notices   enable row level security;

-- ════════════════════════════════════════════════════════════════════
--  دوال (لمفتاح الخدمة فقط — تستدعيها دالة push)
-- ════════════════════════════════════════════════════════════════════

-- رسالة جديدة + تحديث المحادثة في خطوة واحدة
create or replace function public.eng_chat_post(
  p_uid text, p_sender text, p_body text,
  p_email text default '', p_name text default '', p_kind text default 'text')
returns json language plpgsql security definer set search_path = public as $$
declare m public.chat_messages;
begin
  insert into public.chat_messages (uid, sender, body, kind)
  values (p_uid, p_sender, left(p_body, 2000), coalesce(nullif(p_kind, ''), 'text'))
  returning * into m;

  insert into public.chat_threads as t (uid, email, name, last_text, last_from, last_at, unread_admin, unread_user)
  values (p_uid, coalesce(p_email, ''), coalesce(p_name, ''), left(p_body, 140), p_sender, m.created_at,
          case when p_sender = 'user' then 1 else 0 end,
          case when p_sender = 'user' then 0 else 1 end)
  on conflict (uid) do update set
    email        = case when excluded.email <> '' then excluded.email else t.email end,
    name         = case when excluded.name  <> '' then excluded.name  else t.name  end,
    last_text    = excluded.last_text,
    last_from    = excluded.last_from,
    last_at      = excluded.last_at,
    unread_admin = case when p_sender = 'user' then t.unread_admin + 1 else t.unread_admin end,
    unread_user  = case when p_sender = 'user' then t.unread_user else t.unread_user + 1 end;

  return row_to_json(m);
end $$;

create or replace function public.eng_chat_read(p_uid text, p_side text)
returns void language sql security definer set search_path = public as $$
  update public.chat_threads
     set unread_admin = case when p_side = 'admin' then 0 else unread_admin end,
         unread_user  = case when p_side = 'user'  then 0 else unread_user  end
   where uid = p_uid;
$$;

-- إعلان نتيجة مباراة ⇐ تحديد الفائزين (النتيجة الدقيقة فقط)
create or replace function public.eng_settle(
  p_match bigint, p_home int, p_away int,
  p_home_name text default '', p_away_name text default '', p_league text default '', p_kickoff timestamptz default null)
returns json language plpgsql security definer set search_path = public as $$
declare v_total int; v_win int;
begin
  update public.predictions
     set status = case when home_goals = p_home and away_goals = p_away then 'won' else 'lost' end,
         updated_at = now()
   where match_id = p_match and not rewarded;

  select count(*), count(*) filter (where status = 'won')
    into v_total, v_win
    from public.predictions where match_id = p_match;

  insert into public.match_results (match_id, home_goals, away_goals, home_name, away_name, league, kickoff, total, winners, settled_at)
  values (p_match, p_home, p_away, p_home_name, p_away_name, p_league, p_kickoff, v_total, v_win, now())
  on conflict (match_id) do update set
    home_goals = excluded.home_goals, away_goals = excluded.away_goals,
    home_name = coalesce(nullif(excluded.home_name, ''), match_results.home_name),
    away_name = coalesce(nullif(excluded.away_name, ''), match_results.away_name),
    league = coalesce(nullif(excluded.league, ''), match_results.league),
    kickoff = coalesce(excluded.kickoff, match_results.kickoff),
    total = excluded.total, winners = excluded.winners, settled_at = now();

  return json_build_object('total', v_total, 'winners', v_win);
end $$;

-- كود الدعوة لكل مستخدم (يُنشأ مرة واحدة ويبقى ثابتاً)
create or replace function public.eng_ref_code(p_uid text, p_email text default '', p_name text default '')
returns text language plpgsql security definer set search_path = public as $$
declare c text; i int := 0;
begin
  select code into c from public.referral_codes where uid = p_uid;
  if c is not null then return c; end if;
  loop
    c := upper(substr(md5(p_uid || i::text || clock_timestamp()::text), 1, 6));
    c := translate(c, '01', 'ZK');   -- بلا 0/1 حتى لا تختلط مع O/I
    begin
      insert into public.referral_codes (code, uid, email, name) values (c, p_uid, p_email, p_name);
      return c;
    exception when unique_violation then
      select code into c from public.referral_codes where uid = p_uid;
      if c is not null then return c; end if;
      i := i + 1;
      if i > 20 then raise exception 'code_gen_failed'; end if;
    end;
  end loop;
end $$;

-- قائمة الجوائز للإدارة: الفائزون بالتوقعات + الدعوات المؤهلة
create or replace function public.eng_rewards(p_limit int default 200)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'winners', coalesce((
      select json_agg(w order by w.rewarded, w.kickoff desc) from (
        select p.match_id, p.uid, p.email, p.name, p.home_goals, p.away_goals,
               p.home_name, p.away_name, p.league, p.kickoff, p.rewarded, p.rewarded_at,
               (s.expiry_date is not null and s.expiry_date > now()) as subscribed
          from public.predictions p
          left join public.subscriptions s on s.uid = p.uid
         where p.status = 'won'
         order by p.rewarded, p.kickoff desc
         limit p_limit) w), '[]'::json),
    'referrals', coalesce((
      select json_agg(r order by r.status = 'rewarded', r.created_at desc) from (
        select f.friend_uid, f.friend_email, f.friend_name, f.code, f.referrer_uid, f.order_id,
               f.status, f.created_at, f.subscribed_at, f.rewarded_at,
               rc.email as referrer_email, rc.name as referrer_name,
               (s.expiry_date is not null and s.expiry_date > now()) as referrer_subscribed
          from public.referrals f
          join public.referral_codes rc on rc.uid = f.referrer_uid
          left join public.subscriptions s on s.uid = f.referrer_uid
         where f.status in ('joined', 'subscribed', 'rewarded')
         order by f.created_at desc
         limit p_limit) r), '[]'::json),
    'results', coalesce((
      select json_agg(m order by m.settled_at desc) from (
        select * from public.match_results order by settled_at desc limit 60) m), '[]'::json),
    'stats', json_build_object(
      'predictions', (select count(*) from public.predictions),
      'players',     (select count(distinct uid) from public.predictions),
      'won',         (select count(*) from public.predictions where status = 'won'),
      'pending_win', (select count(*) from public.predictions where status = 'won' and not rewarded),
      'ref_codes',   (select count(*) from public.referral_codes),
      'ref_joined',  (select count(*) from public.referrals),
      'ref_subs',    (select count(*) from public.referrals where status in ('subscribed', 'rewarded')),
      'ref_pending', (select count(*) from public.referrals where status = 'subscribed'))
  );
$$;

-- إحصائيات توقعات مباراة (للتطبيق: كم شخصاً توقّع + أكثر نتيجة)
create or replace function public.eng_match_stats(p_match bigint)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'total', (select count(*) from public.predictions where match_id = p_match),
    'home',  (select count(*) from public.predictions where match_id = p_match and home_goals > away_goals),
    'draw',  (select count(*) from public.predictions where match_id = p_match and home_goals = away_goals),
    'away',  (select count(*) from public.predictions where match_id = p_match and home_goals < away_goals),
    'top',   (select json_agg(t) from (
                select home_goals as h, away_goals as a, count(*) as n
                  from public.predictions where match_id = p_match
                 group by 1, 2 order by 3 desc limit 3) t)
  );
$$;

-- اشتراكات تنتهي خلال 3 أيام ولم تصلها رسالة تذكير بعد
create or replace function public.eng_expiring(p_days int default 3)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(x), '[]'::json) from (
    select s.uid, s.email, s.display_name as name, s.expiry_date
      from public.subscriptions s
     where s.expiry_date > now()
       and s.expiry_date < now() + make_interval(days => p_days)
       and not exists (select 1 from public.auto_notices n
                        where n.uid = s.uid and n.kind = 'expiring'
                          and n.ref = to_char(s.expiry_date at time zone 'UTC', 'YYYY-MM-DD'))
     order by s.expiry_date
     limit 300) x;
$$;

revoke all on function public.eng_chat_post(text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.eng_chat_read(text, text)                        from public, anon, authenticated;
revoke all on function public.eng_settle(bigint, int, int, text, text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.eng_ref_code(text, text, text)                    from public, anon, authenticated;
revoke all on function public.eng_rewards(int)                                  from public, anon, authenticated;
revoke all on function public.eng_match_stats(bigint)                           from public, anon, authenticated;
revoke all on function public.eng_expiring(int)                                 from public, anon, authenticated;
grant execute on function public.eng_chat_post(text, text, text, text, text, text) to service_role;
grant execute on function public.eng_chat_read(text, text)                        to service_role;
grant execute on function public.eng_settle(bigint, int, int, text, text, text, timestamptz) to service_role;
grant execute on function public.eng_ref_code(text, text, text)                    to service_role;
grant execute on function public.eng_rewards(int)                                  to service_role;
grant execute on function public.eng_match_stats(bigint)                           to service_role;
grant execute on function public.eng_expiring(int)                                 to service_role;

select 'TOTV+ engagement ready ✅' as result;

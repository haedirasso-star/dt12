-- ════════════════════════════════════════════════════════════════════
--  TOTV+ — دوال صفحة الأدمن
--  شغّلها بعد 01_schema.sql
-- ════════════════════════════════════════════════════════════════════

-- ── مولّد كود عشوائي (بلا O/0/I/1 لمنع الالتباس البصري) ────────────
create or replace function public.gen_code()
returns text language plpgsql as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  out text := 'TOTV';
  i int;
begin
  for i in 1..8 loop
    out := out || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
  end loop;
  return out;
end; $$;

-- ════════════════════════════════════════════════════════════════════
--  توليد أكواد لسيرفر واحد — يعيد قائمة الأكواد المولّدة
-- ════════════════════════════════════════════════════════════════════
create or replace function public.admin_generate_codes(
  p_host  text,
  p_user  text,
  p_pass  text,
  p_plan  text default 'monthly',
  p_days  int  default 30,
  p_count int  default 2,
  p_agent text default '',
  p_note  text default ''
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_batch text := 'B' || upper(to_hex(floor(extract(epoch from now()) * 1000)::bigint));
  v_admin text := coalesce(auth.jwt() ->> 'email', '');
  v_host  text := regexp_replace(trim(p_host), '/+$', '');
  v_code  text;
  v_out   text[] := '{}';
  i int;
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'error', 'NOT_ADMIN');
  end if;
  if coalesce(trim(p_host),'') = '' or coalesce(trim(p_user),'') = ''
     or coalesce(trim(p_pass),'') = '' then
    return jsonb_build_object('ok', false, 'error', 'MISSING_FIELDS');
  end if;
  if v_host !~ '^https?://' then v_host := 'http://' || v_host; end if;

  for i in 1..least(greatest(p_count, 1), 100) loop
    loop
      v_code := public.gen_code();
      exit when not exists (select 1 from public.activation_codes where code = v_code);
    end loop;

    insert into public.activation_codes
      (code, batch_id, host, username, password, plan, days,
       status, used, disabled, agent, note, created_by)
    values
      (v_code, v_batch, v_host, trim(p_user), trim(p_pass), p_plan, p_days,
       'unused', false, false, coalesce(p_agent,''), coalesce(p_note,''), v_admin);

    v_out := array_append(v_out, v_code);
  end loop;

  return jsonb_build_object('ok', true, 'batch', v_batch, 'codes', to_jsonb(v_out));
end; $$;

-- ════════════════════════════════════════════════════════════════════
--  بحث عن مشترك بالإيميل — كل معلوماته + أكواده
-- ════════════════════════════════════════════════════════════════════
create or replace function public.admin_lookup(p_email text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_sub   jsonb;
  v_codes jsonb;
  v_q     text := lower(trim(p_email));
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'error', 'NOT_ADMIN');
  end if;

  select to_jsonb(s) into v_sub
    from public.subscriptions s
   where lower(s.email) = v_q or s.uid = p_email
   limit 1;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.used_at desc), '[]'::jsonb)
    into v_codes
    from public.activation_codes c
   where lower(c.used_by_email) = v_q
      or c.used_by_uid = p_email;

  return jsonb_build_object(
    'ok', true,
    'subscription', coalesce(v_sub, 'null'::jsonb),
    'codes', v_codes,
    'days_left', case
      when v_sub is null then null
      else greatest(0, extract(day from ((v_sub ->> 'expiry_date')::timestamptz - now()))::int)
    end);
end; $$;

-- ════════════════════════════════════════════════════════════════════
--  إحصاءات لوحة التحكم — استعلام واحد بدل عشرات القراءات
-- ════════════════════════════════════════════════════════════════════
create or replace function public.admin_stats()
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'error', 'NOT_ADMIN');
  end if;
  return jsonb_build_object(
    'ok', true,
    'codes_total',    (select count(*) from public.activation_codes),
    'codes_unused',   (select count(*) from public.activation_codes
                        where not used and not disabled),
    'codes_used',     (select count(*) from public.activation_codes where used),
    'codes_disabled', (select count(*) from public.activation_codes where disabled),
    'subs_active',    (select count(*) from public.subscriptions
                        where expiry_date > now()),
    'subs_expired',   (select count(*) from public.subscriptions
                        where expiry_date <= now()),
    'expiring_7d',    (select count(*) from public.subscriptions
                        where expiry_date between now() and now() + interval '7 days'),
    'activated_24h',  (select count(*) from public.activation_log
                        where result = 'ok' and created_at > now() - interval '24 hours')
  );
end; $$;

-- ════════════════════════════════════════════════════════════════════
--  إيقاف / تشغيل / إعادة تعيين كود
-- ════════════════════════════════════════════════════════════════════
create or replace function public.admin_set_code_state(
  p_code text, p_action text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_code text := upper(regexp_replace(coalesce(p_code,''), '[^A-Za-z0-9]', '', 'g'));
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'error', 'NOT_ADMIN');
  end if;

  if p_action = 'disable' then
    update public.activation_codes
       set disabled = true, status = 'disabled' where code = v_code;

  elsif p_action = 'enable' then
    update public.activation_codes
       set disabled = false,
           status = case when used then 'used' else 'unused' end
     where code = v_code;

  elsif p_action = 'release' then
    update public.activation_codes set
      used = false, status = 'unused',
      used_by_uid = null, used_by_email = null, used_by_name = null,
      used_device_id = null, used_at = null, expiry_date = null
    where code = v_code;
    delete from public.subscriptions where code = v_code;

  elsif p_action = 'delete' then
    delete from public.activation_codes where code = v_code;

  else
    return jsonb_build_object('ok', false, 'error', 'BAD_ACTION');
  end if;

  return jsonb_build_object('ok', true);
end; $$;

-- ── الصلاحيات: هذه الدوال للمشرفين المسجّلين فقط ───────────────────
revoke execute on function public.admin_generate_codes(text,text,text,text,int,int,text,text) from anon;
revoke execute on function public.admin_lookup(text)                  from anon;
revoke execute on function public.admin_stats()                       from anon;
revoke execute on function public.admin_set_code_state(text,text)     from anon;

grant execute on function public.admin_generate_codes(text,text,text,text,int,int,text,text) to authenticated;
grant execute on function public.admin_lookup(text)                  to authenticated;
grant execute on function public.admin_stats()                       to authenticated;
grant execute on function public.admin_set_code_state(text,text)     to authenticated;

-- ════════════════════════════════════════════════════════════════════
--  انتهى الإعداد. أنشئ الآن حساب الأدمن:
--  Supabase → Authentication → Users → Add user
--  استخدم نفس الإيميل الموجود في جدول admins.
-- ════════════════════════════════════════════════════════════════════

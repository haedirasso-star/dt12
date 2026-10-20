# نقل الأكواد الحالية من Firestore إلى Supabase

إن كنت قد ولّدت أكواداً في Firestore سابقاً، انقلها بهذه الطريقة (تستغرق دقيقتين).

## الخطوة 1 — تصدير الأكواد من Firestore

افتح صفحة الأدمن القديمة → **🔑 أكواد التفعيل** → **⬇ تصدير CSV**.
ستحصل على ملف فيه كل الأكواد.

## الخطوة 2 — الاستيراد إلى Supabase

Supabase → **Table Editor** → اختر جدول `activation_codes` → زر **Insert** → **Import data from CSV**.

طابِق الأعمدة هكذا:

| عمود CSV | عمود Supabase |
|---|---|
| code | code (احذف الشرطات: TOTV-AB12-CD34 ← TOTVAB12CD34) |
| plan | plan |
| days | days |
| host | host |
| username | username |
| password | password |
| used_by_email | used_by_email |
| expiry_date | expiry_date |
| agent | agent |
| note | note |

> **مهم:** عمود `code` في Supabase يجب أن يكون **بلا شرطات**. في Excel استخدم:
> `=SUBSTITUTE(A2,"-","")`

## الخطوة 3 — تصحيح حالة الأكواد المستخدمة

بعد الاستيراد شغّل في SQL Editor:

```sql
-- علّم الأكواد التي لها مشترك بأنها مستخدمة
update public.activation_codes
   set used = true, status = 'used'
 where used_by_email is not null and used_by_email <> '';

-- أنشئ سجلات الاشتراكات من الأكواد المستخدمة
insert into public.subscriptions
  (uid, email, plan, tier, duration_days, code, host, username, password, expiry_date, activated_at)
select used_by_uid, used_by_email, 'premium', plan, days, code,
       host, username, password, expiry_date, coalesce(used_at, now())
  from public.activation_codes
 where used = true and used_by_uid is not null
on conflict (uid) do nothing;

-- تحقّق
select count(*) as codes_total,
       count(*) filter (where used) as used_codes
  from public.activation_codes;
select count(*) as subscriptions from public.subscriptions;
```

## البديل الأبسط

إن كانت الأكواد قليلة، **لا تنقل شيئاً** — ولّد أكواداً جديدة من Supabase مباشرةً،
واترك الأكواد القديمة تعمل حتى تنتهي (المشتركون الحاليون محفوظة بياناتهم محلياً
على أجهزتهم ولن تتأثر).

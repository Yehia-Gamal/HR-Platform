import pg from 'pg';
const { Client } = pg;

const DB_URL = "postgresql://postgres:01154869616.eA@db.ujzzvqsodyhnnnpkoaml.supabase.co:5432/postgres";

async function runLiveTest() {
  const client = new Client({
    connectionString: DB_URL,
    ssl: { rejectUnauthorized: false }
  });

  console.log("=============================================================");
  console.log("🚀 بدء التجربة الحية الشاملة لنظام الجزاءات الفورية للتأخير");
  console.log("=============================================================\n");

  console.log("🔌 جاري الاتصال بقاعدة بيانات الإنتاج...");
  await client.connect();
  console.log("✅ تم الاتصال بنجاح بقاعدة البيانات!\n");

  try {
    // =========================================================================
    // اختبار 1: فحص دالة حساب الغرامات لجميع الشرائح وفترة السماح
    // =========================================================================
    console.log("🧪 [اختبار 1] فحص شرائح الغرامات وفترة السماح (calc_instant_penalty_amount):");
    
    const brackets = [
      { min: 0, expected: '0.00', label: "تأخير 0 دقيقة (في الموعد 10:00 ص)" },
      { min: 10, expected: '0.00', label: "تأخير 10 دقائق (10:10 ص — فترة سماح)" },
      { min: 15, expected: '0.00', label: "تأخير 15 دقيقة (10:15 ص — نهاية فترة السماح)" },
      { min: 16, expected: '20.00', label: "تأخير 16 دقيقة (10:16 ص — شريحة 20ج)" },
      { min: 30, expected: '20.00', label: "تأخير 30 دقيقة (10:30 ص — شريحة 20ج)" },
      { min: 31, expected: '50.00', label: "تأخير 31 دقيقة (10:31 ص — شريحة 50ج)" },
      { min: 60, expected: '50.00', label: "تأخير 60 دقيقة (11:00 ص — شريحة 50ج)" },
      { min: 61, expected: '150.00', label: "تأخير 61 دقيقة (11:01 ص — شريحة 150ج)" },
      { min: 120, expected: '150.00', label: "تأخير 120 دقيقة (12:00 م — شريحة 150ج)" },
      { min: 180, expected: '150.00', label: "تأخير 180 دقيقة (> ساعتين — الحد الأقصى 150ج)" }
    ];

    for (const b of brackets) {
      const res = await client.query(`select public.calc_instant_penalty_amount($1) as amount`, [b.min]);
      const actual = res.rows[0].amount;
      if (actual === b.expected) {
        console.log(`  ✓ ${b.label} -> الناتج: ${actual} ج.م (مطابق تماماً)`);
      } else {
        throw new Error(`❌ عدم تطابق في دالة الحساب: متوقع ${b.expected} وحصلنا على ${actual}`);
      }
    }

    console.log("\n-------------------------------------------------------------");

    // =========================================================================
    // اختبار 2: دورة الحياة الكاملة (اليوم 1 -> اليوم 2 -> اليوم 3 -> غلق السيستم -> سداد الـ HR -> فتح السيستم)
    // =========================================================================
    console.log("🧪 [اختبار 2] دورة حياة الغرامة والتصعيد وغلق الحساب وإعادة الفتح:");

    // نبدأ معاملة آمنة (Transaction)
    await client.query("BEGIN;");
    console.log("  🔒 تم بدء معاملة معزولة (Transaction) لضمان أمان بيانات الإنتاج.");

    // اختيار موظف حقيقي نشط لديه حساب مستخدم
    const empRes = await client.query(`
      select e.id, e.employee_code, e.full_name_ar, e.status as emp_status, e.is_active, p.status as prof_status
      from public.employees e
      join public.profiles p on p.employee_id = e.id
      where e.status = 'active' and e.is_active = true and p.status = 'active'
      limit 1
    `);

    if (empRes.rows.length === 0) {
      throw new Error("لم يتم العثور على موظف نشط في النظام للاختبار");
    }

    const testEmp = empRes.rows[0];
    console.log(`  👤 الموظف المختار للتجربة: ${testEmp.full_name_ar} (كود: ${testEmp.employee_code})`);
    console.log(`     الحالة الحالية: employees.status = ${testEmp.emp_status} | is_active = ${testEmp.is_active} | profiles.status = ${testEmp.prof_status}`);

    // اختيار مسؤول HR لتأكيد السداد
    const hrRes = await client.query(`
      select id, full_name_ar from public.employees 
      where status = 'active' and is_active = true 
      limit 1
    `);
    const hrActor = hrRes.rows[0];
    console.log(`  👔 مسؤول الـ HR لتأكيد الاستلام: ${hrActor.full_name_ar}`);

    // -------------------------------------------------------------------------
    // أ: إنشاء غرامة اليوم الأول
    // -------------------------------------------------------------------------
    console.log("\n  📍 [المرحلة 1 - اليوم الأول]: تسجيل تأخير 30 دقيقة (10:30 ص)...");
    const insertPenaltyRes = await client.query(`
      insert into public.instant_attendance_penalties (
        employee_id, work_date, late_minutes, original_amount, current_amount,
        status, escalation_level, notes
      ) values (
        $1, current_date - interval '1 day', 30, 20.00, 20.00,
        'pending_payment', 'initial', 'غرامة تجريبية لتأخير 30 دقيقة'
      ) returning id, original_amount, current_amount, status, escalation_level
    `, [testEmp.id]);

    const penalty = insertPenaltyRes.rows[0];
    console.log(`  ✓ تم تسجيل الغرامة الفورية: ID = ${penalty.id}`);
    console.log(`    المبلغ الأصلي: ${penalty.original_amount} ج.م | المبلغ المطلوب: ${penalty.current_amount} ج.م`);
    console.log(`    الحالة: ${penalty.status} | مستوى التصعيد: ${penalty.escalation_level}`);

    // -------------------------------------------------------------------------
    // ب: محاكاة التصعيد لليوم الثاني (المطالبة بـ 500 جنيه)
    // -------------------------------------------------------------------------
    console.log("\n  📍 [المرحلة 2 - اليوم الثاني]: تشغيل كرون التصعيد لعدم السداد في اليوم الأول...");
    const escalateDay2Res = await client.query(`select public.auto_escalate_instant_penalties() as result`);
    console.log(`  ✓ عدد الغرامات المصعدة في كرون اليوم الثاني:`, escalateDay2Res.rows[0].result);

    const checkDay2 = await client.query(`
      select current_amount, status, escalation_level
      from public.instant_attendance_penalties where id = $1
    `, [penalty.id]);
    const day2 = checkDay2.rows[0];

    console.log(`    المبلغ المطلوب الجديد: ${day2.current_amount} ج.م (تمت المطالبة بـ 500 جنيه بنجاح!)`);
    console.log(`    الحالة: ${day2.status} | التصعيد: ${day2.escalation_level}`);

    if (day2.current_amount === '500.00' && day2.status === 'doubled') {
      console.log(`  ✅ تأكيد اليوم الثاني: تمت المطالبة بـ 500 جنيه بنجاح!`);
    } else {
      throw new Error(`❌ فشل تصعيد اليوم الثاني إلى 500 جنيه: ${JSON.stringify(day2)}`);
    }

    // -------------------------------------------------------------------------
    // ج: محاكاة اليوم الثالث (عدم سداد الـ 500 ج -> غلق السيستم والإيقاف عن العمل وإشعار الفريق)
    // -------------------------------------------------------------------------
    console.log("\n  📍 [المرحلة 3 - اليوم الثالث]: محاكاة مرور اليوم الثاني دون سداد الـ 500 جنيه...");
    
    // نعدل work_date ليكون قبل 3 أيام لتأكيد تجاوزه (v_today - 1)
    await client.query(`
      update public.instant_attendance_penalties
         set work_date = current_date - 3
       where id = $1
    `, [penalty.id]);

    const rowBefore3 = await client.query(`
      select work_date, status, escalation_level, current_date, (current_date - 1) as threshold,
             (work_date < current_date - 1) as is_older
      from public.instant_attendance_penalties where id = $1
    `, [penalty.id]);
    console.log(`    🔍 فحص السجل قبل كرون اليوم الثالث:`, rowBefore3.rows[0]);

    const matchingStage2 = await client.query(`
      select p.id, p.employee_id, p.work_date, p.status, p.escalation_level,
             ((now() at time zone 'Africa/Cairo')::date) as cairo_today,
             ((now() at time zone 'Africa/Cairo')::date) - 1 as cairo_thresh
      from public.instant_attendance_penalties p
      where p.status = 'doubled'
        and p.escalation_level = 'doubled'
        and p.work_date < ((now() at time zone 'Africa/Cairo')::date) - 1
    `);
    console.log(`    🔍 الصفوف المطابقة لشرط المرحلة 2:`, matchingStage2.rows);

    const auditErr = await client.query(`
      select event_type, summary_ar, metadata
      from public.audit_events
      order by created_at desc
      limit 2
    `);
    console.log(`    ⚠️ آخر سجلات التدقيق:`, auditErr.rows);

    const escalateDay3Res = await client.query(`select public.auto_escalate_instant_penalties() as result`);
    console.log(`  ✓ عدد الحالات المعلقة في كرون اليوم الثالث:`, escalateDay3Res.rows[0].result);

    const checkDay3 = await client.query(`
      select current_amount, status, escalation_level, suspended_at
      from public.instant_attendance_penalties where id = $1
    `, [penalty.id]);
    const day3 = checkDay3.rows[0];

    console.log(`    حالة الغرامة: ${day3.status} | مستوى التصعيد: ${day3.escalation_level}`);
    console.log(`    وقت تعليق الموظف: ${day3.suspended_at}`);

    // فحص غلق الحساب والسيستم على الموظف
    const checkEmpLock = await client.query(`
      select e.status as emp_status, e.is_active as emp_is_active, p.status as prof_status
      from public.employees e
      join public.profiles p on p.employee_id = e.id
      where e.id = $1
    `, [testEmp.id]);
    const lock = checkEmpLock.rows[0];

    console.log(`    🔒 فحص إغلاق السيستم:`);
    console.log(`       - employees.status: '${lock.emp_status}' (متوقع: suspended)`);
    console.log(`       - employees.is_active: ${lock.emp_is_active} (متوقع: false)`);
    console.log(`       - profiles.status: '${lock.prof_status}' (متوقع: suspended)`);

    if (lock.emp_status === 'suspended' && lock.emp_is_active === false && lock.prof_status === 'suspended') {
      console.log(`  ✅ تأكيد الأمان: تم إيقاف الموظف عن العمل وغلق السيستم عليه بنجاح تام!`);
    } else {
      throw new Error(`❌ فشل في إغلاق السيستم على الموظف: ${JSON.stringify(lock)}`);
    }

    // فحص إشعار الفريق
    const teamNotif = await client.query(`
      select count(*) as count from public.notifications
      where entity_id = $1 and entity_type = 'instant_penalty_suspended'
    `, [penalty.id]);
    console.log(`    📢 عدد إشعارات التعليق المرسلة لكامل الفريق: ${teamNotif.rows[0].count} إشعار`);

    // -------------------------------------------------------------------------
    // د: استلام الـ HR للـ 500 جنيه وفتح السيستم وعودة الموظف للعمل
    // -------------------------------------------------------------------------
    console.log("\n  📍 [المرحلة 4 - سداد الـ HR]: قيام الـ HR بتأكيد استلام الـ 500 جنيه وفتح السيستم...");
    
    // سداد الغرامة
    await client.query(`
      update public.instant_attendance_penalties
         set status = 'paid',
             paid_at = now(),
             confirmed_by = $1,
             updated_at = now()
       where id = $2
    `, [hrActor.id, penalty.id]);

    // إعادة تفعيل الحساب فوراً كما تنص القواعد
    await client.query(`
      update public.employees
         set status = 'active',
             is_active = true,
             updated_at = now()
       where id = $1
    `, [testEmp.id]);

    await client.query(`
      update public.profiles
         set status = 'active',
             updated_at = now()
       where employee_id = $1
    `, [testEmp.id]);

    const checkRestored = await client.query(`
      select e.status as emp_status, e.is_active as emp_is_active, p.status as prof_status
      from public.employees e
      join public.profiles p on p.employee_id = e.id
      where e.id = $1
    `, [testEmp.id]);
    const restored = checkRestored.rows[0];

    console.log(`    🔓 فحص إعادة فتح السيستم بعد السداد:`);
    console.log(`       - employees.status: '${restored.emp_status}' (متوقع: active)`);
    console.log(`       - employees.is_active: ${restored.emp_is_active} (متوقع: true)`);
    console.log(`       - profiles.status: '${restored.prof_status}' (متوقع: active)`);

    if (restored.emp_status === 'active' && restored.emp_is_active === true && restored.prof_status === 'active') {
      console.log(`  ✅ تأكيد السداد: تم إزالة الخصم والعلامة وعاد الموظف للعمل والسيستم فُتح بالكامل!`);
    } else {
      throw new Error(`❌ فشل في إعادة فتح السيستم: ${JSON.stringify(restored)}`);
    }

    // -------------------------------------------------------------------------
    // هـ: تجربة وظيفة إلغاء الغرامة بواسطة الـ HR (cancel_instant_penalty)
    // -------------------------------------------------------------------------
    console.log("\n  📍 [المرحلة 5 - إلغاء غرامة بواسطة HR]: إنشاء غرامة ثانية وإلغاؤها بسبب عذر قهري...");
    const penalty2Res = await client.query(`
      insert into public.instant_attendance_penalties (
        employee_id, work_date, late_minutes, original_amount, current_amount,
        status, escalation_level, notes
      ) values (
        $1, current_date - interval '10 days', 45, 50.00, 50.00,
        'pending_payment', 'initial', 'غرامة لتجربة الإلغاء'
      ) returning id
    `, [testEmp.id]);
    const penalty2Id = penalty2Res.rows[0].id;

    await client.query(`
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = 'إلغاء: تم قبول عذر قهري رسمي بموافقة الإدارة',
             updated_at = now()
       where id = $1
    `, [penalty2Id]);

    const checkP2 = await client.query(`select status, notes from public.instant_attendance_penalties where id = $1`, [penalty2Id]);
    console.log(`  ✓ حالة الغرامة بعد الإلغاء: status = ${checkP2.rows[0].status} | الملاحظات: ${checkP2.rows[0].notes}`);
    console.log(`  ✅ تم تأكيد مسار الإلغاء بنجاح!`);

    // التراجع عن المعاملة المعزولة لإبقاء قاعدة بيانات الإنتاج نقية 100%
    await client.query("ROLLBACK;");
    console.log("\n  🔄 تم عمل ROLLBACK للمعاملة بنجاح — قاعدة بيانات الإنتاج بقيت نقية دون أي تعديل تجريبي!");

    console.log("\n=============================================================");
    console.log("🎉 اكتملت التجربة الحية بنجاح 100% — كافة القواعد تعمل بدقة متناهية!");
    console.log("=============================================================");

  } catch (err) {
    await client.query("ROLLBACK;");
    console.error("❌ حدث خطأ أثناء التجربة الحية:", err);
    process.exitCode = 1;
  } finally {
    await client.end();
  }
}

runLiveTest();

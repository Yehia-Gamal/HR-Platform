# DEPENDENCY_GRAPH.md — V17 Task Dependencies

> آخر تحديث: 2026-07-25

## Execution Lanes

Five independent lanes can run in parallel. Within each lane, tasks are sequential.

---

### Lane A — KPI Flow (P0, CRITICAL)

```
A1. shared-contracts: KPI stage enum reorder + criteria schema
    ↓
A2. migration 0130: advance_kpi_stage routing self→hr_review→manager_review→manager_final
    + stage order array in trigger
    + get_kpi_evaluation_form editability
    + save_kpi_compliance_metric stage check
    + kpi_criteria seed (7 criteria, weights, HR/manager owner)
    ↓
A3. pgTAP test 0053: V17 KPI flow (self→HR→manager→finalized)
    + executive exclusion still works
    + HR cannot score manager fields, manager cannot score HR fields
    ↓
A4. Flutter mobile_kpi_page.dart: reorder stage filters, add hr_review action
    + kpi_evaluation_detail_page.dart: field editability per stage
    + employee_home_page.dart: stage labels
    + mobile_providers.dart: provider updates
    ↓
A5. Web KpiCyclesPage + PerformancePage: V17 flow reflection
```

**Estimated migrations:** 1 (0130)  
**Estimated test files:** 1 (0053)  
**Risk:** HIGH — changes core business logic for the entire KPI workflow

---

### Lane B — Complaints Administrative Actions (P1)

```
B1. shared-contracts: dispute admin action schema
    ↓
B2. migration 0131: add columns to dispute_cases
    + propose_admin_action / decide_admin_action / execute_admin_action RPCs
    + RLS policies (secretary propose, director decide, HR execute)
    ↓
B3. pgTAP test 0054: admin action lifecycle
    ↓
B4. Flutter executive_disputes_page.dart: show proposed action
    + executive_decisions_page.dart: approve/reject/return
    + mobile_disputes_page.dart: employee sees action outcome
    ↓
B5. Web DisputesPage: secretary propose, director decide, HR execute
```

**Estimated migrations:** 1 (0131)  
**Estimated test files:** 1 (0054)  
**Depends on:** Nothing in Lane A — fully parallel

---

### Lane C — Operations Routing + Holidays + Posts (P0/P1 mix)

```
C1. migration 0132: Operations personal request routing → executive director
    ↓
C2. pgTAP: operations request routing test
    ↓
C3. Flutter: verify request approver display

── parallel with ──

C4. migration 0133: official_holidays table + RLS
    ↓
C5. pgTAP test 0055: holiday CRUD + scope
    ↓
C6. Web: HR official-holiday management route

── parallel with ──

C7. migration 0134: post publishing RLS (main_admin + hr + executive)
    ↓
C8. Flutter + Web: enforce publishing restrictions
```

**Estimated migrations:** 3 (0132–0134)  
**Estimated test files:** 1–2  
**Depends on:** Nothing in Lanes A or B

---

### Lane D — Page Cleanup & Profile (P0, INDEPENDENT)

```
D1. workspace_scaffold.dart: hide risk + governance from More menu
    ↓  (no dependency, just ordering)
D2. mobile_self_service_page.dart: remove documents/custody/payroll panels
    ↓
D3. mobile_profile_page.dart: remove hidden panels, add direct manager name
    ↓
D4. Verify deleted pages (privacy, learning, service portal) have zero nav references
    ↓
D5. Web App.tsx: verify hidden route comments match V17 §4.2
```

**Estimated migrations:** 0  
**No backend dependency — can start immediately**

---

### Lane E — Notifications & Attendance Config (P1)

```
E1. migration 0135: attendance_config table (times, grace, reminder schedule)
    ↓
E2. migration 0136: word count CHECK constraints on text fields
    ↓
E3. Edge Function or pg_cron: attendance reminders (9:45/10:00/17:45/18:00)
    + exclude: executive, leave, mission, holiday
    ↓
E4. Notification outbox integration: KPI stage change, request status, disputes, posts
    ↓
E5. Flutter: verify notification center shows all categories
```

**Estimated migrations:** 2 (0135–0136)  
**Depends on:** Lane C4 (holidays) for holiday exclusion logic

---

### Lane F — Cleanup Items (INDEPENDENT, LOW PRIORITY)

```
F1. AndroidManifest.xml: verify/remove MODIFY_AUDIO_SETTINGS
F2. vercel.json: camera=(self) → camera=()
F3. Consider removing live-location-video-url 410 stub
```

**No dependencies. Can run any time.**

---

## Visual Dependency Map

```
                    ┌──────────────────────────────────────────────┐
                    │         Wave 2: Contracts (parallel)         │
                    │  A1(KPI) B1(Disputes) C-schemas E-schemas   │
                    └──────┬───────┬────────┬──────────┬──────────┘
                           │       │        │          │
                    ┌──────▼──┐ ┌──▼────┐ ┌─▼────────┐│
                    │ A2: mig │ │B2: mig│ │C1-C7:migs││
                    │  0130   │ │ 0131  │ │0132-0134 ││
                    │ KPI     │ │Dispute│ │Ops+Hol+  ││
                    │ flow    │ │admin  │ │Post      ││
                    └────┬────┘ └───┬───┘ └────┬─────┘│
                         │         │           │      │
                    ┌────▼────┐ ┌──▼────┐ ┌───▼───┐ ┌▼─────────┐
                    │A3: test │ │B3:test│ │C2/5:  │ │E1-2: mig  │
                    │  0053   │ │ 0054  │ │tests  │ │0135-0136  │
                    └────┬────┘ └───┬───┘ └───┬───┘ └─────┬─────┘
                         │         │          │           │
    ┌──────────┐   ┌─────▼─────┐ ┌─▼──────┐ ┌▼────────┐ ┌▼──────────┐
    │D1-5:     │   │A4: Flutter│ │B4: mob  │ │C3/6/8:  │ │E3-5: notif│
    │Page      │   │KPI mobile │ │disputes │ │mob+web  │ │ pipeline  │
    │cleanup   │   └─────┬─────┘ └─┬──────┘ └─────────┘ └───────────┘
    │(parallel)│         │         │
    └──────────┘   ┌─────▼─────┐ ┌─▼──────┐
                   │A5: Web KPI│ │B5: web  │
                   │  pages    │ │disputes │
                   └───────────┘ └────────┘

    ┌──────────┐
    │F1-3:     │   ← Independent cleanup, any time
    │Android/  │
    │Vercel fix│
    └──────────┘
```

---

## Parallel Execution Strategy

### Batch 1 (START NOW — zero dependencies)

| Agent | Lane | Work |
|---|---|---|
| Agent-D | D | Page cleanup: hide risk/governance, remove hidden panels from self-service/profile |
| Agent-F | F | AndroidManifest + vercel.json fixes |
| Agent-A1 | A | Shared contracts: KPI stage enum + criteria schema |
| Agent-B1 | B | Shared contracts: dispute admin action schema |

### Batch 2 (after contracts done)

| Agent | Lane | Work |
|---|---|---|
| Agent-A2 | A | Migration 0130: KPI flow reorder |
| Agent-B2 | B | Migration 0131: dispute admin action columns + RPCs |
| Agent-C | C | Migrations 0132–0134: ops routing + holidays + post publishing |

### Batch 3 (after migrations done)

| Agent | Lane | Work |
|---|---|---|
| Agent-A3 | A | pgTAP test 0053: KPI V17 flow |
| Agent-B3 | B | pgTAP test 0054: dispute admin actions |
| Agent-C-test | C | pgTAP tests for ops routing + holidays |
| Agent-E | E | Migrations 0135–0136: attendance config + word count |

### Batch 4 (after tests pass)

| Agent | Lane | Work |
|---|---|---|
| Agent-A4 | A | Flutter KPI pages update |
| Agent-B4 | B | Flutter disputes pages update |
| Agent-A5 | A | Web KPI pages update |
| Agent-B5 | B | Web disputes pages update |
| Agent-E2 | E | Notification pipeline |

### Batch 5 (final)

| Agent | Lane | Work |
|---|---|---|
| Wave 10 | ALL | Full validation: pgTAP + vitest + flutter test + build + analyze |

---

## Migration Number Allocation

| Number | Purpose | Lane |
|---|---|---|
| 0130 | KPI flow reorder + criteria + form editability | A |
| 0131 | Dispute administrative action columns + RPCs + RLS | B |
| 0132 | Operations request routing → executive director | C |
| 0133 | Official holidays table + RLS | C |
| 0134 | Post publishing RLS restriction | C |
| 0135 | Attendance config table + reminder schedule | E |
| 0136 | Word count CHECK constraints | E |

⚠️ Before creating ANY migration:
```bash
ls supabase/migrations/ | sort | tail -5
ls supabase/migrations/ | cut -c1-4 | sort | uniq -d
```

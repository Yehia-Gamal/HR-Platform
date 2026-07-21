# خارطة تنفيذ V8 — Ahla Shabab Management OS

## المبدأ

لا Big Bang. كل مرحلة تسلم Vertical Slices قابلة للاستخدام ومختبرة. ترتيب التنفيذ أدناه ملزم إلا بقرار معماري موثق.

## Phase 0 — Security Remediation & Single Source of Truth

- تدوير الأسرار.
- إصلاح SQL P0 في الصلاحيات والحضور والWorkflow والموقع.
- Migration manifest كامل.
- pgTAP/RLS tests.
- تصنيف SQL القديمة Draft Only.
- توحيد V8 كمصدر الحقيقة.

**Gate:** صفر P0/P1 في الهوية والصلاحيات والحضور.

## Phase 1 — Unified Platform Foundation

- Monorepo.
- Flutter واحد وWorkspace Resolver.
- React واحدة وWorkspaces.
- Design Tokens Light/Dark.
- Auth/MFA/Passkey/device sessions.
- RBAC+ABAC وField permissions.
- Audit/Security events.
- Transactional Outbox foundation.
- CI/CD وDev/Staging/Prod.

## Phase 2 — Core HR Release

- Employee 360 وCreation Wizard.
- Organization/Managers.
- Attendance/Shift/Geofence.
- Leave/Permissions/Missions.
- KPI self→manager→secretary→executive.
- Official News & Decisions Feed.
- Notifications and scheduled reports.
- Executive Workspace mobile.

## Phase 3 — Operations & Governance Core

- Tasks/Projects.
- Meetings and decisions.
- Disputes/committees.
- Risks/incidents.
- Service Catalog/HR Helpdesk.
- Evidence Vault basic.
- Document generation/signatures basic.

## Phase 4 — Enterprise Governance

- Universal Action Center.
- Position/Headcount/Capacity.
- SOP Runner.
- Quality/CAPA.
- Internal Audit.
- Compliance Calendar.
- Executive Briefing/Meeting Mode.

## Phase 5 — Automation & Process Intelligence

- Event Catalog/Outbox workers.
- Automation Studio.
- Process Event Logs.
- Process Mining/Conformance.
- Notification Intelligence.
- Decision Impact/Benefits.

## Phase 6 — Digital Twin & Data Governance

- Digital Twin graph.
- Scenario Lab.
- Data Catalog/Contracts/Quality/Lineage.
- Knowledge Graph.
- Organizational Memory.

## Phase 7 — Full Employee Lifecycle

- ATS/Recruitment.
- Onboarding/Probation.
- LMS/Skills/Certifications.
- Career/Succession/Talent Marketplace.
- Assets/Offboarding.
- Payroll فقط بعد Legal/Finance approval.

## Phase 8 — Responsible Intelligence & Resilience

- AI Governance/Model Registry.
- RAG assistants with citations.
- Forecasting and anomaly review.
- Release Readiness/Control Room.
- Chaos/DR/Business Continuity.

## قاعدة القطع Cut Scope

عند ضغط الوقت، لا تُخفّض الأمان أو الاختبارات. يتم تأجيل وحدة كاملة عبر Feature Flag بدل إصدار نصف مكتمل.

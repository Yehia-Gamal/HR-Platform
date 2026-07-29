import { z } from 'zod';

const uuid = z.string().uuid();
const nullableUuid = uuid.nullable();

export const attendanceOperationsCatalogSchema = z.object({
  month: z.string(),
  shifts: z.array(z.object({
    id: uuid, code: z.string(), name: z.string(), startTime: z.string(), endTime: z.string(),
    crossesMidnight: z.boolean(), breakMinutes: z.number(), graceInMinutes: z.number(), active: z.boolean(),
  })),
  rosters: z.array(z.object({
    id: uuid, code: z.string(), name: z.string(), periodStart: z.string(), periodEnd: z.string(), status: z.string(),
    departmentId: nullableUuid, teamId: nullableUuid, branchId: nullableUuid, publishedAt: z.string().nullable(), days: z.number(),
  })),
  corrections: z.array(z.object({
    id: uuid, employeeId: uuid, employeeName: z.string(), employeeCode: z.string().nullable(), workDate: z.string(),
    type: z.string(), reason: z.string(), status: z.string(), requestedCheckIn: z.string().nullable(), requestedCheckOut: z.string().nullable(), requestedStatus: z.string().nullable(), createdAt: z.string(),
  })),
  overtime: z.array(z.object({
    id: uuid, employeeId: uuid, employeeName: z.string(), employeeCode: z.string().nullable(), workDate: z.string(),
    requestedMinutes: z.number(), approvedMinutes: z.number().nullable(), status: z.string(), reason: z.string().nullable(),
  })),
  periods: z.array(z.object({
    id: uuid, periodMonth: z.string(), branchId: nullableUuid, status: z.string(), closedAt: z.string().nullable(), unlockedAt: z.string().nullable(), unlockReason: z.string().nullable(),
  })),
  summary: z.object({ scheduled: z.number(), present: z.number(), absent: z.number(), pendingCorrections: z.number(), pendingOvertime: z.number() }),
  lastUpdatedAt: z.string(),
});
export type AttendanceOperationsCatalog = z.infer<typeof attendanceOperationsCatalogSchema>;

export const kpiAdminCatalogSchema = z.object({
  month: z.string(),
  cycles: z.array(z.object({
    id: uuid, periodMonth: z.string(), status: z.string(), templateId: nullableUuid, templateName: z.string().nullable(),
    selfDueAt: z.string().nullable(), managerDueAt: z.string().nullable(), secretaryDueAt: z.string().nullable(), executiveDueAt: z.string().nullable(),
    scheduledOpenAt: z.string().nullable().optional(), deadlineAt: z.string().nullable().optional(), extendedUntil: z.string().nullable().optional(), effectiveDeadline: z.string().nullable().optional(),
    openedAt: z.string().nullable(), lockedAt: z.string().nullable(), overrideReason: z.string().nullable().optional(), evaluations: z.number(), finalized: z.number(),
    overdue: z.number().optional(), averageScore: z.number().nullable().optional(),
    employeeEvaluations: z.array(z.object({
      id: uuid, employeeId: uuid, employeeName: z.string(), employeeCode: z.string().nullable(),
      stage: z.string(), workflowStatus: z.string().nullable().optional(),
      finalScore: z.number().nullable().optional(), finalRating: z.string().nullable().optional(),
      locked: z.boolean().optional(),
    })).optional(),
  })),
  templates: z.array(z.object({
    id: uuid, name: z.string(), version: z.number(), active: z.boolean(), officialCode: z.string().nullable().optional(), criteria: z.array(z.object({
      id: uuid, code: z.string().nullable().optional(), name: z.string(), weight: z.number(), maxScore: z.number(), sourceType: z.string(), attendanceMetric: z.string().nullable(), evaluatorStage: z.string().nullable().optional(), calculationMethod: z.string().nullable().optional(), requiresEvidence: z.boolean(),
    })),
  })),
  appeals: z.array(z.object({
    id: uuid, evaluationId: uuid, employeeId: uuid, employeeName: z.string(), employeeCode: z.string().nullable(), reason: z.string(),
    requestedOutcome: z.string().nullable(), status: z.string(), submittedAt: z.string(), resolutionDueAt: z.string().nullable(), reviewNote: z.string().nullable(),
  })),
  stageCounts: z.record(z.string(), z.number()),
  canManageCycles: z.boolean().optional(),
  officialTemplateId: nullableUuid.optional(),
  policy: z.object({ id: uuid, version: z.number(), name: z.string(), weights: z.record(z.string(), z.number()), attendanceRules: z.record(z.string(), z.number()), ratingBands: z.array(z.object({ min: z.number(), max: z.number(), label: z.string() })) }).nullable().optional(),
  lastUpdatedAt: z.string(),
});
export type KpiAdminCatalog = z.infer<typeof kpiAdminCatalogSchema>;

export const disputeParticipantSchema = z.object({
  id: uuid,
  name: z.string(),
  employeeCode: z.string().nullable(),
  department: z.string().nullable(),
});
export const disputeParticipantDirectorySchema = z.array(disputeParticipantSchema);
export type DisputeParticipant = z.infer<typeof disputeParticipantSchema>;

const disputeMemberSchema = z.object({ id: uuid, employeeId: uuid, name: z.string(), role: z.string(), active: z.boolean() });
const disputePartySchema = z.object({
  id: uuid, employeeId: uuid, name: z.string(), type: z.string(), notificationStatus: z.string(),
  notifiedAt: z.string().nullable(), statementSubmittedAt: z.string().nullable(),
});
const disputeStatementSchema = z.object({
  id: uuid, submittedBy: uuid, submittedByName: z.string(), type: z.string(), text: z.string(),
  visibility: z.string(), submittedAt: z.string(),
});
const disputeEvidenceSchema = z.object({
  id: uuid, title: z.string(), description: z.string().nullable(), type: z.string(), mimeType: z.string().nullable(),
  storagePath: z.string().nullable(), visibility: z.string(), submittedAt: z.string(), submittedByName: z.string().nullable(),
});
const disputeSessionSchema = z.object({
  id: uuid, type: z.string(), scheduledAt: z.string().nullable(), endsAt: z.string().nullable(), heldAt: z.string().nullable(),
  status: z.string(), location: z.string().nullable(), modality: z.string().nullable(), minutes: z.string().nullable(),
  minutesData: z.record(z.string(), z.unknown()), outcome: z.string().nullable(), recommendation: z.string().nullable(), followUpAt: z.string().nullable(),
  attendance: z.array(z.object({ committeeMemberId: uuid, employeeId: uuid, name: z.string(), status: z.string() })),
});
const disputeActionSchema = z.object({
  id: uuid, type: z.string(), note: z.string().nullable(), assignedTo: nullableUuid, assignedName: z.string().nullable(),
  dueAt: z.string().nullable(), status: z.string().nullable(), proof: z.string().nullable(), completedAt: z.string().nullable(), createdAt: z.string(),
});
const disputeSettlementSchema = z.object({
  id: uuid, type: z.string(), fromName: z.string().nullable(), toName: z.string().nullable(), text: z.string().nullable(),
  publicationPlace: z.string().nullable(), dueAt: z.string().nullable(), status: z.string(), completedAt: z.string().nullable(),
});
const disputeAppealSchema = z.object({
  id: uuid, decisionId: uuid, appellantId: uuid, appellantName: z.string(), reason: z.string(), status: z.string(),
  submittedAt: z.string(), resolution: z.string().nullable(),
});
export const disputeOperationsCatalogSchema = z.object({
  cases: z.array(z.object({
    id: uuid, caseNumber: z.string().nullable(), title: z.string(), description: z.string().nullable(), caseType: z.string(), status: z.string(), priority: z.string(), severity: z.string().optional(),
    actorId: nullableUuid, actorName: z.string().nullable(), respondentId: nullableUuid, respondentName: z.string().nullable(),
    actorDepartment: z.string().nullable(), assignedTo: nullableUuid, assignedName: z.string().nullable(), openedAt: z.string(), updatedAt: z.string().nullable(),
    acceptedAt: z.string().nullable(), reviewDueAt: z.string().nullable(), decisionDueAt: z.string().nullable(), overdue: z.boolean(),
    incidentAt: z.string().nullable(), incidentLocation: z.string().nullable(), requestedAction: z.string().nullable(),
    directManagerContacted: z.boolean().nullable(), amicableAttempted: z.boolean().nullable(), amicableResult: z.string().nullable(),
    confidential: z.boolean(), privacyLevel: z.string(), quorum: z.number(), closureReason: z.string().nullable(),
    parties: z.array(disputePartySchema), members: z.array(disputeMemberSchema), statements: z.array(disputeStatementSchema),
    evidence: z.array(disputeEvidenceSchema), sessions: z.array(disputeSessionSchema),
    decision: z.object({
      id: uuid, number: z.string(), text: z.string(), rationale: z.string(), outcome: z.string(), status: z.string(), issuedAt: z.string().nullable(),
      ownerId: nullableUuid, ownerName: z.string().nullable(), dueAt: z.string().nullable(), implementedAt: z.string().nullable(),
    }).nullable(),
    // V17 §14 admin-action fields (mig 0141)
    proposedAdminAction: z.string().nullable().optional(),
    proposedActionDetail: z.string().nullable().optional(),
    proposedAt: z.string().nullable().optional(),
    proposedByName: z.string().nullable().optional(),
    executiveDecision: z.string().nullable().optional(),
    executiveDecisionReason: z.string().nullable().optional(),
    executiveDecisionAt: z.string().nullable().optional(),
    executiveDecisionByName: z.string().nullable().optional(),
    approvedAdminAction: z.string().nullable().optional(),
    approvedActionDetail: z.string().nullable().optional(),
    executedAt: z.string().nullable().optional(),
    executedByName: z.string().nullable().optional(),
    executionNotes: z.string().nullable().optional(),
    actions: z.array(disputeActionSchema), settlements: z.array(disputeSettlementSchema), appeals: z.array(disputeAppealSchema),
  })),
  summary: z.object({
    new: z.number(), overdue: z.number(), urgent: z.number(), critical: z.number(), waitingStatements: z.number(),
    escalated: z.number(), pendingExecution: z.number(),
    actionProposed: z.number().optional(), awaitingExecution: z.number().optional(), executed: z.number().optional(),
    closed: z.number(), averageResolutionHours: z.number(),
  }),
  pendingAppeals: z.number(),
  lastUpdatedAt: z.string(),
});
export type DisputeOperationsCatalog = z.infer<typeof disputeOperationsCatalogSchema>;

export const lifecycleOperationsCatalogSchema = z.object({
  documents: z.array(z.object({
    id: uuid, employeeId: uuid, employeeName: z.string(), employeeCode: z.string().nullable(), type: z.string(), title: z.string().nullable(), number: z.string().nullable(),
    issueDate: z.string().nullable(), expiryDate: z.string().nullable(), status: z.string(), verified: z.boolean(), storagePath: z.string(), createdAt: z.string(),
  })),
  assets: z.array(z.object({
    id: uuid, assetCode: z.string().nullable(), type: z.string(), name: z.string(), serial: z.string().nullable(), status: z.string(), condition: z.string().nullable(), location: z.string().nullable(),
    assignment: z.object({ id: uuid, employeeId: uuid, employeeName: z.string(), status: z.string(), handedOverAt: z.string().nullable(), returnedAt: z.string().nullable() }).nullable(),
  })),
  offboarding: z.array(z.object({
    id: uuid, caseNumber: z.string(), employeeId: uuid, employeeName: z.string(), employeeCode: z.string().nullable(), reasonType: z.string(), lastWorkingDate: z.string(), status: z.string(), handoverEmployeeId: nullableUuid,
    clearance: z.array(z.object({ id: uuid, category: z.string(), title: z.string(), status: z.string(), assigneeId: nullableUuid, dueAt: z.string().nullable(), completionNote: z.string().nullable() })),
  })),
  expiringDocuments: z.number(), assignedAssets: z.number(), openOffboarding: z.number(), lastUpdatedAt: z.string(),
});
export type LifecycleOperationsCatalog = z.infer<typeof lifecycleOperationsCatalogSchema>;

import { z } from 'zod';

const uuid = z.string().uuid();

// ─── Documents Studio Catalog (RPC: get_documents_assets_offboarding_catalog) ───

export const documentItemSchema = z.object({
  id: uuid,
  employeeId: uuid,
  employeeName: z.string(),
  employeeCode: z.string().nullable(),
  type: z.string(),
  title: z.string(),
  number: z.string().nullable(),
  issueDate: z.string().nullable(),
  expiryDate: z.string().nullable(),
  status: z.string(),
  verified: z.boolean(),
  storagePath: z.string().nullable(),
  createdAt: z.string().nullable(),
});
export type DocumentItem = z.infer<typeof documentItemSchema>;

export const assetAssignmentSchema = z.object({
  id: uuid.nullable(),
  employeeId: uuid.nullable(),
  employeeName: z.string().nullable(),
  status: z.string().nullable(),
  handedOverAt: z.string().nullable(),
  returnedAt: z.string().nullable(),
});
export type AssetAssignment = z.infer<typeof assetAssignmentSchema>;

export const assetItemSchema = z.object({
  id: uuid,
  assetCode: z.string().nullable(),
  type: z.string(),
  name: z.string(),
  serial: z.string().nullable(),
  status: z.string().nullable(),
  condition: z.string().nullable(),
  location: z.string().nullable(),
  assignment: assetAssignmentSchema.nullable(),
});
export type AssetItem = z.infer<typeof assetItemSchema>;

export const clearanceItemSchema = z.object({
  id: uuid,
  category: z.string(),
  title: z.string(),
  status: z.string(),
  assigneeId: uuid.nullable(),
  dueAt: z.string().nullable(),
  completionNote: z.string().nullable(),
});
export type ClearanceItem = z.infer<typeof clearanceItemSchema>;

export const offboardingCaseSchema = z.object({
  id: uuid,
  caseNumber: z.string(),
  employeeId: uuid,
  employeeName: z.string(),
  employeeCode: z.string().nullable(),
  reasonType: z.string(),
  lastWorkingDate: z.string().nullable(),
  status: z.string(),
  handoverEmployeeId: uuid.nullable(),
  clearance: z.array(clearanceItemSchema),
});
export type OffboardingCase = z.infer<typeof offboardingCaseSchema>;

export const documentsCatalogSchema = z.object({
  documents: z.array(documentItemSchema),
  assets: z.array(assetItemSchema),
  offboarding: z.array(offboardingCaseSchema),
  expiringDocuments: z.number(),
  assignedAssets: z.number(),
  openOffboarding: z.number(),
  lastUpdatedAt: z.string(),
});
export type DocumentsCatalog = z.infer<typeof documentsCatalogSchema>;

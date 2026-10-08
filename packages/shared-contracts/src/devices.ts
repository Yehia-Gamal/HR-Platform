import { z } from 'zod';

const uuid = z.string().uuid();
const isoDate = z.string().datetime({ offset: true }).nullable();

/** جهاز معلّق بانتظار الموافقة */
export const pendingDeviceSchema = z
  .object({
    id: uuid,
    employeeId: uuid,
    employeeName: z.string(),
    employeeCode: z.string().nullable(),
    employeePhotoUrl: z.string().nullable(),
    deviceName: z.string().nullable(),
    platform: z.string(),
    status: z.enum(['pending', 'blocked']),
    registeredAt: z.string(),
    lastUsedAt: z.string().nullable(),
    rejectionReason: z.string().nullable(),
    revocationSource: z.string().nullable(),
    metadata: z.record(z.string(), z.unknown()),
  })
  .strict();
export type PendingDevice = z.infer<typeof pendingDeviceSchema>;

/** جهاز في لوحة الإدارة */
export const adminDeviceSchema = z
  .object({
    id: uuid,
    employeeId: uuid,
    employeeName: z.string(),
    employeeCode: z.string().nullable(),
    employeePhotoUrl: z.string().nullable().optional(),
    deviceName: z.string().nullable(),
    platform: z.string(),
    status: z.enum(['pending', 'active', 'blocked', 'revoked', 'replaced', 'auto_revoked']),
    registeredAt: z.string(),
    approvedAt: z.string().nullable().optional(),
    approvedBy: z.string().nullable().optional(),
    revokedAt: z.string().nullable().optional(),
    lastUsedAt: z.string().nullable().optional(),
    rejectionReason: z.string().nullable().optional(),
    revocationSource: z.string().nullable().optional(),
    metadata: z.record(z.string(), z.unknown()).nullable().optional(),
  })
  .passthrough();
export type AdminDevice = z.infer<typeof adminDeviceSchema>;

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
    deviceName: z.string().nullable(),
    platform: z.string(),
    status: z.enum(['pending', 'active', 'blocked', 'revoked', 'replaced', 'auto_revoked']),
    registeredAt: z.string(),
    approvedAt: z.string().nullable(),
    revokedAt: z.string().nullable(),
    lastUsedAt: z.string().nullable(),
    rejectionReason: z.string().nullable(),
    revocationSource: z.string().nullable(),
  })
  .strict();
export type AdminDevice = z.infer<typeof adminDeviceSchema>;

import { describe, expect, it } from 'vitest';
import {
  executiveAttendanceOverviewSchema,
  liveLocationModeSchema,
  liveLocationResponseSchema,
} from './liveLocation.js';

describe('live location contracts', () => {
  it('accepts the combined location_video mode', () => {
    expect(liveLocationModeSchema.parse('location_video')).toBe('location_video');
    expect(() => liveLocationModeSchema.parse('teleport')).toThrow();
  });

  it('round-trips a get_live_location_response payload with point + video', () => {
    const payload = liveLocationResponseSchema.parse({
      request: {
        id: '11111111-1111-4111-8111-111111111111',
        status: 'completed',
        mode: 'location_video',
        reason: 'متابعة إدارية',
        purpose: 'verification',
        requestedAt: '2026-07-15T08:00:00.000Z',
        respondedAt: '2026-07-15T08:00:30.000Z',
        startsAt: '2026-07-15T08:00:30.000Z',
        expiresAt: '2026-07-15T08:02:30.000Z',
        durationMinutes: 2,
        needsVideo: true,
        needsPoint: true,
      },
      employee: {
        id: '22222222-2222-4222-8222-222222222222',
        name: 'موظف الهدف',
        employeeCode: 'EMP-001',
        jobTitle: 'أخصائي',
        department: 'العمليات',
      },
      requesterName: 'المدير التنفيذي',
      points: [
        {
          id: '33333333-3333-4333-8333-333333333333',
          latitude: 30.05,
          longitude: 31.23,
          accuracy: 12,
          altitude: null,
          speed: null,
          heading: null,
          isMock: false,
          source: 'mobile',
          addressAr: 'قرب شارع النيل، المنيا',
          recordedAt: '2026-07-15T08:00:45.000Z',
          createdAt: '2026-07-15T08:00:45.000Z',
        },
      ],
      video: {
        id: '44444444-4444-4444-8444-444444444444',
        durationSeconds: 5,
        sizeBytes: 900000,
        mimeType: 'video/mp4',
        capturedLat: 30.05,
        capturedLng: 31.23,
        capturedAccuracy: 12,
        capturedAt: '2026-07-15T08:00:50.000Z',
        status: 'ready',
        retentionDeleteAfter: '2026-07-16T08:00:50.000Z',
        legalHoldUntil: null,
      },
    });
    expect(payload.points).toHaveLength(1);
    expect(payload.video?.status).toBe('ready');
    expect(payload.request.needsVideo).toBe(true);
  });

  it('accepts an executive attendance overview with a minimal summary', () => {
    const overview = executiveAttendanceOverviewSchema.parse({
      date: '2026-07-15',
      summary: { total: 3, present: 2, onLeave: 1 },
      employees: [],
      generatedAt: '2026-07-15T08:00:00.000Z',
    });
    expect(overview.summary.total).toBe(3);
  });
});

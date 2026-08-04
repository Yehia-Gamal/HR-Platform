import { z } from 'zod';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

/* ─── Schemas (تطابق get_learning_admin_catalog RPC في 0033) ─── */
export const learningCourseSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  title: z.string(),
  category: z.string(),
  deliveryMode: z.enum(['online', 'onsite', 'hybrid', 'self_paced']),
  durationMinutes: z.number(),
  mandatory: z.boolean(),
  active: z.boolean(),
  enrollments: z.number().default(0),
  completed: z.number().default(0),
});

export const learningEnrollmentSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeName: z.string().nullable(),
  employeeCode: z.string().nullable(),
  courseId: z.string().uuid(),
  courseTitle: z.string(),
  status: z.enum(['enrolled', 'in_progress', 'completed', 'failed', 'cancelled']),
  progress: z.number().nullable(),
  score: z.number().nullable(),
  enrolledAt: z.string(),
  completedAt: z.string().nullable(),
  expiresAt: z.string().nullable(),
});

export const learningEmployeeSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  code: z.string().nullable(),
});

export const learningCatalogSchema = z.object({
  courses: z.array(learningCourseSchema),
  enrollments: z.array(learningEnrollmentSchema),
  employees: z.array(learningEmployeeSchema),
  lastUpdatedAt: z.string().optional(),
});

export type LearningCourse = z.infer<typeof learningCourseSchema>;
export type LearningEnrollment = z.infer<typeof learningEnrollmentSchema>;
export type LearningEmployee = z.infer<typeof learningEmployeeSchema>;
export type LearningCatalog = z.infer<typeof learningCatalogSchema>;

/* ─── Queries ─── */
export function useLearningCatalog() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['learning-catalog'],
    enabled: auth.status === 'authenticated',
    queryFn: async () => learningCatalogSchema.parse(await rpc('get_learning_admin_catalog', {})),
    staleTime: 30_000,
  });
}

/* ─── Mutations (RPCs موجودة في 0033) ─── */
export interface CourseFormInput {
  id?: string | null;
  code: string;
  title_ar: string;
  title_en?: string;
  description?: string;
  category?: string;
  delivery_mode: string;
  duration_minutes: number;
  mandatory: boolean;
  passing_score?: number | null;
  validity_months?: number | null;
  active: boolean;
}

export function useUpsertCourse() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: CourseFormInput) =>
      rpc('upsert_learning_course_admin', {
        p_id: input.id ?? null,
        p_code: input.code,
        p_title_ar: input.title_ar,
        p_title_en: input.title_en ?? null,
        p_description: input.description ?? null,
        p_category: input.category ?? 'general',
        p_delivery_mode: input.delivery_mode,
        p_duration_minutes: input.duration_minutes,
        p_mandatory: input.mandatory,
        p_passing_score: input.passing_score ?? null,
        p_validity_months: input.validity_months ?? null,
        p_active: input.active,
      }),
    onSuccess: () => client.invalidateQueries({ queryKey: ['learning-catalog'] }),
    meta: { successMessage: 'تم حفظ الدورة التدريبية بنجاح' },
  });
}

export function useEnrollEmployee() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: { employeeId: string; courseId: string; sessionId?: string | null }) =>
      rpc('enroll_employee_course_admin', {
        p_employee_id: input.employeeId,
        p_course_id: input.courseId,
        p_session_id: input.sessionId ?? null,
      }),
    onSuccess: () => client.invalidateQueries({ queryKey: ['learning-catalog'] }),
    meta: { successMessage: 'تم تسجيل الموظف في الدورة بنجاح' },
  });
}

export function useTransitionEnrollment() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: async (input: { enrollmentId: string; status: string; progress?: number; score?: number }) =>
      rpc('transition_learning_enrollment', {
        p_enrollment_id: input.enrollmentId,
        p_status: input.status,
        p_progress: input.progress ?? null,
        p_score: input.score ?? null,
      }),
    onSuccess: () => client.invalidateQueries({ queryKey: ['learning-catalog'] }),
    meta: { successMessage: 'تم تحديث حالة التسجيل' },
  });
}

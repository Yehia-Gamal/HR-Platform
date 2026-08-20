import { describe, expect, it } from 'vitest';
import {
  workflowStepSchema,
  workflowDefinitionSchema,
  createWorkflowDefinitionInputSchema,
} from './workflow.js';

const uuid1 = '11111111-1111-4111-8111-111111111111';
const uuid2 = '22222222-2222-4222-8222-222222222222';

describe('Workflow Contracts', () => {
  it('validates workflow step structure', () => {
    const step = workflowStepSchema.parse({
      id: uuid1,
      workflowId: uuid2,
      stepOrder: 1,
      stepName: 'اعتماد المدير المباشر',
      approverRole: 'direct_manager',
      slaHours: 24,
      autoApproveOnSla: false,
    });
    expect(step.stepOrder).toBe(1);
    expect(step.approverRole).toBe('direct_manager');
  });

  it('validates workflow definition schema with steps', () => {
    const def = workflowDefinitionSchema.parse({
      id: uuid1,
      requestType: 'leave',
      name: 'مسار اعتماد الإجازات العادية',
      isActive: true,
      steps: [
        {
          id: uuid2,
          workflowId: uuid1,
          stepOrder: 1,
          stepName: 'مدير الإدارة',
          approverRole: 'department_manager',
          slaHours: 48,
          autoApproveOnSla: true,
        },
      ],
    });
    expect(def.requestType).toBe('leave');
    expect(def.steps).toHaveLength(1);
  });

  it('create workflow input enforces at least one step', () => {
    expect(() =>
      createWorkflowDefinitionInputSchema.parse({
        requestType: 'mission',
        name: 'مسار المأموريات',
        steps: [],
      })
    ).toThrow();
  });
});

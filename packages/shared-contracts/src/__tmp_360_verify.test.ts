import { describe, expect, it } from 'vitest';
import { employee360Schema } from './employee';

const raw = '{"id": "11111111-2222-3333-4444-555555555555", "team": null, "email": null, "grade": null, "roles": [], "assets": [], "branch": null, "status": "active", "teamId": null, "gradeId": null, "branchId": null, "hireDate": "2024-01-15", "isActive": true, "jobTitle": null, "photoUrl": null, "position": null, "workSite": null, "documents": [], "latestKpi": null, "managerId": null, "phoneE164": "+201099505229", "department": null, "fullNameAr": "موظف تجريبي", "fullNameEn": "Test Employee", "jobTitleId": null, "positionId": null, "workSiteId": null, "contractEnd": null, "departments": [], "managerName": null, "recentTasks": [], "attendance30": {"absent": 0, "present": 0, "lateDays": 0, "workMinutes": 0}, "departmentId": null, "employeeCode": "TEST-001", "probationEnd": null, "accountStatus": null, "directReports": 0, "lastUpdatedAt": null, "requestCounts": {"pending": 0, "approved": 0, "rejected": 0}, "recentRequests": [], "employmentTypeId": null}';

describe('tmp 360 verify', () => {
  it('parses get_employee_360 output', () => {
    const parsed = employee360Schema.parse(JSON.parse(raw));
    expect(parsed.employeeCode).toBe('TEST-001');
    expect(parsed.managerId).toBeNull();
  });
});

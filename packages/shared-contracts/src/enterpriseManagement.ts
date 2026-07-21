import { z } from 'zod';
const uuid=z.string().uuid();
export const enterpriseManagementCatalogSchema=z.object({
 objectives:z.array(z.object({id:uuid,code:z.string(),title:z.string(),level:z.string(),status:z.string(),progress:z.number(),periodEnd:z.string().nullable()})),
 projects:z.array(z.object({id:uuid,code:z.string(),name:z.string(),status:z.string(),priority:z.string(),progress:z.number(),targetEndDate:z.string().nullable(),openTasks:z.number()})),
 risks:z.array(z.object({id:uuid,number:z.number(),title:z.string(),category:z.string(),probability:z.number(),impact:z.number(),score:z.number(),status:z.string(),reviewDate:z.string().nullable()})),
 incidents:z.array(z.object({id:uuid,number:z.number(),title:z.string(),severity:z.string(),status:z.string(),occurredAt:z.string().nullable()})),
 serviceRequests:z.array(z.object({id:uuid,number:z.number(),serviceName:z.string(),requesterName:z.string(),title:z.string(),priority:z.string(),status:z.string(),dueAt:z.string().nullable()})),
 meetings:z.array(z.object({id:uuid,title:z.string(),meetingType:z.string(),startsAt:z.string().nullable(),status:z.string(),minutesStatus:z.string(),decisions:z.number()})),
 qualityCases:z.array(z.object({id:uuid,number:z.number(),title:z.string(),severity:z.string(),status:z.string(),dueAt:z.string().nullable()})),
 audits:z.array(z.object({id:uuid,code:z.string(),title:z.string(),status:z.string(),plannedStart:z.string().nullable(),findings:z.number()})),
 automations:z.array(z.object({id:uuid,code:z.string(),name:z.string(),eventType:z.string(),version:z.number(),active:z.boolean(),requiresApproval:z.boolean()})),
 dataAssets:z.array(z.object({id:uuid,code:z.string(),name:z.string(),sourceSystem:z.string(),classification:z.string(),active:z.boolean()})),
 aiUseCases:z.array(z.object({id:uuid,code:z.string(),name:z.string(),purpose:z.string(),provider:z.string().nullable(),modelName:z.string().nullable(),riskLevel:z.string(),humanReviewRequired:z.boolean(),active:z.boolean()})),
 lastUpdatedAt:z.string()
});
export type EnterpriseManagementCatalog=z.infer<typeof enterpriseManagementCatalogSchema>;

export const peopleFinanceCatalogSchema=z.object({
 workforcePlans:z.array(z.object({id:uuid,year:z.number(),departmentId:uuid,departmentName:z.string(),positionId:uuid.nullable(),approvedHeadcount:z.number(),plannedHires:z.number(),plannedCost:z.number().nullable(),status:z.string()})),
 capacity:z.array(z.object({id:uuid,snapshotDate:z.string(),departmentId:uuid,departmentName:z.string(),availableMinutes:z.number(),demandMinutes:z.number(),leaveMinutes:z.number(),overtimeMinutes:z.number(),utilizationPercent:z.number().nullable()})),
 salaryStructures:z.array(z.object({id:uuid,code:z.string(),name:z.string(),currency:z.string(),active:z.boolean(),effectiveFrom:z.string(),effectiveTo:z.string().nullable()})),
 payrollRuns:z.array(z.object({id:uuid,periodMonth:z.string(),currency:z.string(),status:z.string(),totals:z.record(z.string(),z.unknown()),calculatedAt:z.string().nullable(),approvedAt:z.string().nullable(),closedAt:z.string().nullable()})),
 loans:z.array(z.object({id:uuid,employeeId:uuid,employeeName:z.string(),loanType:z.string(),principalAmount:z.number(),outstandingAmount:z.number(),status:z.string()})),
 campaigns:z.array(z.object({id:uuid,title:z.string(),campaignType:z.string(),startsAt:z.string().nullable(),endsAt:z.string().nullable(),status:z.string()})),
 lastUpdatedAt:z.string()
});
export type PeopleFinanceCatalog=z.infer<typeof peopleFinanceCatalogSchema>;

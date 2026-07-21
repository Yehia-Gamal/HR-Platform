import { describe,expect,it } from 'vitest';
import { enterpriseManagementCatalogSchema,peopleFinanceCatalogSchema } from './enterpriseManagement.js';
const now=new Date().toISOString();
describe('enterprise management contracts',()=>{
 it('parses enterprise catalog',()=>expect(enterpriseManagementCatalogSchema.parse({objectives:[],projects:[],risks:[],incidents:[],serviceRequests:[],meetings:[],qualityCases:[],audits:[],automations:[],dataAssets:[],aiUseCases:[],lastUpdatedAt:now}).projects).toHaveLength(0));
 it('parses people finance catalog',()=>expect(peopleFinanceCatalogSchema.parse({workforcePlans:[],capacity:[],salaryStructures:[],payrollRuns:[],loans:[],campaigns:[],lastUpdatedAt:now}).payrollRuns).toHaveLength(0));
});

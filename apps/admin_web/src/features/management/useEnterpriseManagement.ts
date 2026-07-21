import { enterpriseManagementCatalogSchema, peopleFinanceCatalogSchema, type EnterpriseManagementCatalog, type PeopleFinanceCatalog } from '@ahla/shared-contracts';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
const now=new Date().toISOString();
const mockEnterprise:EnterpriseManagementCatalog={
  objectives:[],projects:[],risks:[],incidents:[],
  serviceRequests:[
    {id:'a1000000-0000-4000-8000-000000000001',number:24031,serviceName:'الدعم التقني',requesterName:'أحمد محمود',title:'تعذر الدخول إلى نظام الحضور',priority:'urgent',status:'submitted',dueAt:new Date(Date.now()-45*60_000).toISOString()},
    {id:'a1000000-0000-4000-8000-000000000002',number:24030,serviceName:'الخدمات الإدارية',requesterName:'سارة عادل',title:'طلب بطاقة دخول بديلة',priority:'high',status:'in_progress',dueAt:new Date(Date.now()+5*3_600_000).toISOString()},
    {id:'a1000000-0000-4000-8000-000000000003',number:24028,serviceName:'تقنية المعلومات',requesterName:'محمود فؤاد',title:'تجهيز صلاحيات جهاز العمل',priority:'normal',status:'assigned',dueAt:new Date(Date.now()+22*3_600_000).toISOString()},
    {id:'a1000000-0000-4000-8000-000000000004',number:24021,serviceName:'الموارد البشرية',requesterName:'منى حسن',title:'تصحيح بيانات وثيقة وظيفية',priority:'normal',status:'resolved',dueAt:new Date(Date.now()-26*3_600_000).toISOString()},
  ],
  meetings:[],qualityCases:[],audits:[],automations:[],dataAssets:[],aiUseCases:[],lastUpdatedAt:now
};
const mockFinance:PeopleFinanceCatalog={workforcePlans:[],capacity:[],salaryStructures:[],payrollRuns:[],loans:[],campaigns:[],lastUpdatedAt:now};
export function useEnterpriseManagementCatalog(){const a=useAuth();return useQuery({queryKey:['enterprise-management',a.isMock],enabled:a.status==='authenticated',queryFn:async()=>a.isMock?mockEnterprise:enterpriseManagementCatalogSchema.parse(await rpc('get_enterprise_management_catalog'))});}
export function usePeopleFinanceCatalog(){const a=useAuth();return useQuery({queryKey:['people-finance',a.isMock],enabled:a.status==='authenticated',queryFn:async()=>a.isMock?mockFinance:peopleFinanceCatalogSchema.parse(await rpc('get_people_finance_catalog'))});}

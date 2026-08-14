/**
 * أنواع عقود استوديو المستندات — مطابقة لـ get_document_studio_catalog() في migration 0033.
 * تُترك الحقول كـ string/string|null بدلاً من Date لتقارب سلسلة JSON القادمة من Postgres (jsonb).
 */
export type DocumentType = 'contract' | 'offer_letter' | 'warning' | 'certificate' | 'experience_letter' | 'other';

export type DocumentTemplate = {
  id: string;
  code: string;
  name: string;
  documentType: string;
  version: number;
  active: boolean;
  requiresEmployeeSignature: boolean;
  requiresManagerSignature: boolean;
  requiresHrSignature: boolean;
  requiresExecutiveSignature: boolean;
};

export type GeneratedDocument = {
  id: string;
  referenceNumber: string | null;
  title: string;
  documentType: string;
  employeeId: string | null;
  employeeName: string | null;
  status: string;
  createdAt: string;
  issuedAt: string | null;
  pendingSignatures: number;
};

export type DocumentStudioCatalog = {
  templates: DocumentTemplate[];
  documents: GeneratedDocument[];
  lastUpdatedAt: string;
};

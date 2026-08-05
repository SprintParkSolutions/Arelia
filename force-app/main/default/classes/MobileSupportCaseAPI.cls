/**
 * MobileSupportCaseAPI handles mobile support case creation and case listing.
 */
@RestResource(urlMapping='/mobileSupportCase')
global without sharing class MobileSupportCaseAPI {

    /**
     * Response wrapper for case creation.
     */
    global class CaseResponse {
        public Boolean success;
        public String caseId;
        public String message;
    }

    /**
     * Case data wrapper for mobile case listing.
     */
    global class CaseDTO {
        public String caseId;
        public String caseNumber;
        public String subject;
        public String description;
        public String status;
        public String priority;
        public String category;
        public String createdDate;
        public String projectId;
        public String projectName;
    }

    /**
     * Response wrapper for case list.
     */
    global class CaseListResponse {
        public Boolean success;
        public String message;
        public List<CaseDTO> cases;
    }

    /**
     * Creates a support case from mobile app.
     */
    @HttpPost
    global static CaseResponse createCase() {
        CaseResponse response = new CaseResponse();

        try {
            Map<String, Object> data = getRequestBodyData();

            String contactId = (String) data.get('contactId');
            String projectId = (String) data.get('projectId');
            String subject = (String) data.get('subject');
            String description = (String) data.get('description');
            String priority = (String) data.get('priority');
            String category = (String) data.get('category');
            String otherCategory = (String) data.get('otherCategory');

            String validationMessage = validateCaseRequest(contactId, subject);
            if (String.isNotBlank(validationMessage)) {
                response.success = false;
                response.message = validationMessage;
                return response;
            }

            Id areliaRecordTypeId = getAreliaCaseRecordTypeId();
            if (areliaRecordTypeId == null) {
                response.success = false;
                response.message = 'Arelia record type not found on Case object';
                return response;
            }

            Case supportCase = buildSupportCase(
                contactId,
                projectId,
                subject,
                description,
                priority,
                category,
                otherCategory,
                areliaRecordTypeId
            );

            insert supportCase;

            response.success = true;
            response.caseId = supportCase.Id;
            response.message = 'Case created successfully';
            return response;
        } catch (Exception ex) {
            response.success = false;
            response.message = ex.getMessage();
            return response;
        }
    }

    /**
     * Gets support cases for a mobile client by Contact Id.
     */
    @HttpGet
    global static CaseListResponse getCases() {
        CaseListResponse response = new CaseListResponse();
        response.success = false;
        response.message = '';
        response.cases = new List<CaseDTO>();

        try {
            RestRequest request = RestContext.request;
            String contactId = request.params.get('contactId');

            if (String.isBlank(contactId)) {
                response.message = 'Contact Id is required.';
                return response;
            }

            response.cases = getCasesByContactId(contactId);
            response.success = true;
            response.message = 'Success';
            return response;
        } catch (Exception ex) {
            response.success = false;
            response.message = ex.getMessage();
            return response;
        }
    }

    private static Map<String, Object> getRequestBodyData() {
        RestRequest request = RestContext.request;
        String body = request.requestBody == null
            ? null
            : request.requestBody.toString();

        if (String.isBlank(body)) {
            return new Map<String, Object>();
        }

        return (Map<String, Object>) JSON.deserializeUntyped(body);
    }

    private static String validateCaseRequest(String contactId, String subject) {
        if (String.isBlank(contactId)) {
            return 'Contact Id is required.';
        }

        if (String.isBlank(subject)) {
            return 'Subject is required.';
        }

        return null;
    }

    private static Id getAreliaCaseRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypeMap =
            Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName();

        if (recordTypeMap.containsKey('Arelia')) {
            return recordTypeMap.get('Arelia').getRecordTypeId();
        }

        return null;
    }

    private static Case buildSupportCase(
        String contactId,
        String projectId,
        String subject,
        String description,
        String priority,
        String category,
        String otherCategory,
        Id areliaRecordTypeId
    ) {
        Case supportCase = new Case();

        supportCase.RecordTypeId = areliaRecordTypeId;
        supportCase.Subject = subject;
        supportCase.Description = description;
        supportCase.Priority = String.isBlank(priority) ? 'Medium' : priority;
        supportCase.Origin = 'Mobile App';
        supportCase.ContactId = contactId;
        supportCase.Status = 'New';

        setCaseCategory(supportCase, category, otherCategory);

        if (String.isNotBlank(projectId)) {
            supportCase.Project__c = projectId;
        }

        return supportCase;
    }

    private static void setCaseCategory(
        Case supportCase,
        String category,
        String otherCategory
    ) {
        if (category == 'Other' && String.isNotBlank(otherCategory)) {
            supportCase.Type = 'Other';
            supportCase.Other_Category__c = otherCategory;
            return;
        }

        if (String.isNotBlank(category)) {
            supportCase.Type = category;
        }
    }

    private static List<CaseDTO> getCasesByContactId(String contactId) {
        List<CaseDTO> caseDTOList = new List<CaseDTO>();

        List<Case> caseList = [SELECT Id, CaseNumber, Subject, Description, Status,
                   Priority, Type, CreatedDate,Project__c, Project__r.Name
            FROM Case WHERE ContactId = :contactId ORDER BY CreatedDate DESC];


        for (Case caseRecord : caseList) {
            caseDTOList.add(buildCaseDTO(caseRecord));
        }

        return caseDTOList;
    }

    private static CaseDTO buildCaseDTO(Case caseRecord) {
        CaseDTO caseData = new CaseDTO();

        caseData.caseId = caseRecord.Id;
        caseData.caseNumber = caseRecord.CaseNumber;
        caseData.subject = caseRecord.Subject;
        caseData.description = caseRecord.Description;
        caseData.status = caseRecord.Status;
        caseData.priority = caseRecord.Priority;
        caseData.category = caseRecord.Type;
        caseData.createdDate = String.valueOf(caseRecord.CreatedDate);
        caseData.projectId = caseRecord.Project__c;
        caseData.projectName = caseRecord.Project__r != null ? caseRecord.Project__r.Name : null;

        return caseData;
    }
}
@RestResource(urlMapping='/mobileSupportCase')
global with sharing class MobileSupportCaseAPI {

    // ✅ RESPONSE WRAPPER
    global class CaseResponse {
        public Boolean success;
        public String caseId;
        public String message;
    }

    @HttpPost
    global static CaseResponse createCase() {

        CaseResponse response = new CaseResponse();

        try {
            RestRequest req = RestContext.request;
            String body = req.requestBody.toString();

            Map<String, Object> data =
                (Map<String, Object>) JSON.deserializeUntyped(body);

            // ⭐ READ VALUES FROM MOBILE
            String contactId  = (String) data.get('contactId');
            String projectId  = (String) data.get('projectId'); // ⭐ NEW
            String subject    = (String) data.get('subject');
            String description= (String) data.get('description');
            String priority   = (String) data.get('priority');
            String category   = (String) data.get('category');

            // ⭐ CREATE CASE
            Case c = new Case();
            c.Subject     = subject;
            c.Description = description;
            c.Priority    = priority;
            c.Origin      = 'Mobile App';
            c.ContactId   = contactId;
            c.Type        = category;
            c.Status      = 'New';

            // ⭐ MOST IMPORTANT LINE — LINK TO PROJECT
            if(String.isNotBlank(projectId)){
                c.Project__c = projectId;
            }

            insert c;

            response.success = true;
            response.caseId = c.Id;
            response.message = 'Case created successfully';

        } catch (Exception e) {
            response.success = false;
            response.message = e.getMessage();
        }

        return response;
    }
}
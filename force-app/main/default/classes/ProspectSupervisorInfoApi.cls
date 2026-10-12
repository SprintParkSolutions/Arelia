@RestResource(urlMapping='/registration/lead/supervisor')
global without sharing class ProspectSupervisorInfoApi {
    global class SupervisorResponse {
        public Boolean success = false;
        public String message;
        public Id leadId;
        public Boolean assigned = false;
        public Id supervisorUserId;
        public String supervisorUser;
        public String supervisorUserEmail;
        public String supervisorUserPhone;
    }

    @HttpGet
    global static SupervisorResponse getSupervisor() {
        SupervisorResponse response = new SupervisorResponse();
        RestContext.response.addHeader('Content-Type', 'application/json');
        String value = RestContext.request == null ? null : RestContext.request.params.get('leadId');
        Id leadId;
        try {
            if (String.isBlank(value)) throw new IllegalArgumentException();
            leadId = Id.valueOf(value.trim());
            if (leadId.getSObjectType() != Lead.SObjectType) throw new IllegalArgumentException();
        } catch (Exception invalidId) {
            RestContext.response.statusCode = 400;
            response.message = 'A valid Salesforce Lead ID is required.';
            return response;
        }
        try {
            List<Lead> records = [
                SELECT Id, Supervisor_User__c, Supervisor_User__r.Name,
                       Supervisor_User_Email__c, Supervisor_User_Phone__c
                FROM Lead WHERE Id = :leadId LIMIT 1
            ];
            if (records.isEmpty()) {
                RestContext.response.statusCode = 404;
                response.message = 'Lead record was not found.';
                return response;
            }
            Lead record = records[0];
            response.success = true;
            response.leadId = record.Id;
            response.assigned = record.Supervisor_User__c != null;
            response.supervisorUserId = record.Supervisor_User__c;
            if (response.assigned) {
                response.supervisorUser = record.Supervisor_User__r.Name;
                response.supervisorUserEmail = record.Supervisor_User_Email__c;
                response.supervisorUserPhone = record.Supervisor_User_Phone__c;
            }
            response.message = response.assigned ? 'Supervisor information loaded.' : 'A supervisor has not been assigned yet.';
            RestContext.response.statusCode = 200;
        } catch (Exception error) {
            RestContext.response.statusCode = 500;
            response.message = 'Unable to load supervisor information.';
        }
        return response;
    }
}
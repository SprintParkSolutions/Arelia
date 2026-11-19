@RestResource(
    urlMapping='/registration/lead/supervisor-details/*'
)
global with sharing class ProspectSupervisorDetailsApi {

    @HttpGet
    global static void getSupervisorDetails() {

        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        res.addHeader('Content-Type', 'application/json');

        String leadId = req.params.get('leadId');

        if (String.isBlank(leadId)) {
            sendResponse(400, new Map<String, Object>{
                'success' => false,
                'message' => 'Lead ID is required.'
            });
            return;
        }

        Id parsedLeadId;

        try {
            parsedLeadId = (Id) leadId;

            if (parsedLeadId.getSObjectType() != Lead.SObjectType) {
                throw new SupervisorApiException(
                    'Invalid Lead ID.'
                );
            }
        } catch (Exception ex) {
            sendResponse(400, new Map<String, Object>{
                'success' => false,
                'message' => 'Invalid Lead ID.'
            });
            return;
        }

        // IMPORTANT:
        // The authenticated customer must be authorized
        // to access this particular Lead/project.
        // Apply the same customer ownership validation
        // used by your existing prospect project API here.

        List<Lead> leads = [
            SELECT
                Id,
                Supervisor_User__c,
                Supervisor_User__r.Name,
                Supervisor_User__r.Email,
                Supervisor_User__r.Phone,
                Supervisor_User_Email__c,
                Supervisor_User_Phone__c
            FROM Lead
            WHERE Id = :parsedLeadId
            LIMIT 1
        ];

        if (leads.isEmpty()) {
            sendResponse(404, new Map<String, Object>{
                'success' => false,
                'message' => 'Project not found.'
            });
            return;
        }

        Lead prospect = leads[0];

        if (prospect.Supervisor_User__c == null) {
            sendResponse(404, new Map<String, Object>{
                'success' => false,
                'message' => 'No supervisor assigned to this project.'
            });
            return;
        }

        String email = prospect.Supervisor_User_Email__c;
        String phone = prospect.Supervisor_User_Phone__c;

        if (String.isBlank(email) &&
            prospect.Supervisor_User__r != null) {
            email = prospect.Supervisor_User__r.Email;
        }

        if (String.isBlank(phone) &&
            prospect.Supervisor_User__r != null) {
            phone = prospect.Supervisor_User__r.Phone;
        }

        sendResponse(200, new Map<String, Object>{
            'success' => true,
            'supervisor' => new Map<String, Object>{
                'leadId' => String.valueOf(prospect.Id),
                'supervisorId' =>
                    String.valueOf(prospect.Supervisor_User__c),
                'supervisorName' =>
                    prospect.Supervisor_User__r.Name,
                'supervisorEmail' =>
                    String.isBlank(email) ? '' : email,
                'supervisorPhone' =>
                    String.isBlank(phone) ? '' : phone
            }
        });
    }

    private static void sendResponse(
        Integer statusCode,
        Map<String, Object> result
    ) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.responseBody =
            Blob.valueOf(JSON.serialize(result));
    }

    global class SupervisorApiException extends Exception {}
}
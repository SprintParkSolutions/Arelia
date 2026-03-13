@RestResource(urlMapping='/registration/lead')
global without sharing class RegistrationLeadRestController {

    @HttpPost
    global static LeadResponse registerLead() {

        try {
            RestRequest req = RestContext.request;
            String body = req.requestBody.toString();

            Map<String, Object> payload =
                (Map<String, Object>) JSON.deserializeUntyped(body);

            Id leadId = RegistrationFormController.registerLead(payload);

            return new LeadResponse(true, leadId, null);

        } catch (Exception e) {
            return new LeadResponse(false, null, e.getMessage());
        }
    }

    global class LeadResponse {
        public Boolean success;
        public Id leadId;
        public String message;

        public LeadResponse(Boolean success, Id leadId, String message) {
            this.success = success;
            this.leadId = leadId;
            this.message = message;
        }
    }
}
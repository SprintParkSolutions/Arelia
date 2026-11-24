@RestResource(urlMapping='/mobileCreateLead/*')
global with sharing class MobileLeadService {

    global class LeadRequest {
        public String firstName;
        public String lastName;
        public String email;
        public String phone;
        public String company;

        public String projectType;     // Home / Office / etc
        public String city;
        public String budget;
        public String message;         // Optional requirement notes
    }

    global class LeadResponse {
        public Boolean success;
        public String message;
        public String leadId;

        public LeadResponse(Boolean success, String message, String leadId) {
            this.success = success;
            this.message = message;
            this.leadId = leadId;
        }
    }

    @HttpPost
    global static LeadResponse createLead() {
        try {
            String body = RestContext.request.requestBody.toString();
            LeadRequest reqData = (LeadRequest) JSON.deserialize(body, LeadRequest.class);

            // Basic validation
            if (String.isBlank(reqData.email) || String.isBlank(reqData.phone)) {
                return new LeadResponse(false, 'Email and Phone are required.', null);
            }

            Lead l = new Lead();
            l.FirstName = reqData.firstName;
            l.LastName  = String.isBlank(reqData.lastName) ? 'Unknown' : reqData.lastName;
            l.Email     = reqData.email;
            l.Phone     = reqData.phone;
            l.Company   = String.isBlank(reqData.company) ? 'Individual' : reqData.company;

            // Map your custom fields if you have them (update API names)
            // Example:
            // l.Project_Type__c = reqData.projectType;
            // l.City__c = reqData.city;
            // l.Budget_Range__c = reqData.budget;
            // l.Description = reqData.message;

            l.Description = reqData.message;

            insert l;

            return new LeadResponse(true, 'Lead created successfully.', l.Id);

        } catch (Exception e) {
            return new LeadResponse(false, 'Error: ' + e.getMessage(), null);
        }
    }
}
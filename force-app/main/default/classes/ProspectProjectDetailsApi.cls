@RestResource(urlMapping='/registration/lead/project-details')
global without sharing class ProspectProjectDetailsApi {

    global class ProjectDetailsResponse {
        public Boolean success;
        public String message;
        public Id leadId;

        public Boolean projectSubmitted;

        public String firstName;
        public String lastName;
        public String email;
        public String phone;

        public String siteSpace;
        public String typeOfProject;
        public String projectScope;
        public String planLevel;
        public String customerBudget;
        public String siteLocation;
        public String projectDescription;

        public ProjectDetailsResponse() {
            success = false;
            projectSubmitted = false;
        }
    }

    /*
     * Loads submitted project details.
     * GET:
     * /registration/lead/project-details?leadId=00Q...
     */
    @HttpGet
    global static ProjectDetailsResponse getProjectDetails() {
        ProjectDetailsResponse response =
            new ProjectDetailsResponse();

        try {
            RestContext.response.addHeader('Content-Type','application/json');
            
            String leadIdValue = RestContext.request == null ? null : RestContext.request.params.get('leadId');
            
            if (String.isBlank(leadIdValue)) {
                RestContext.response.statusCode = 400;
                response.message = 'Salesforce Lead ID is required.';
                return response;
            }
            Id leadId = parseLeadId(leadIdValue);
            if (leadId == null) {
                RestContext.response.statusCode = 400;
                response.message = 'Invalid Salesforce Lead ID.';
                return response;
            }
            List<Lead> leadRecords = [SELECT Id,FirstName, LastName, Email, Phone, Site_Space__c,
                        Type_Of_Project__c, Project_Scope__c, Plan_Level__c, Customer_Budget__c, Site_Location__c,
                        Project_Description__c, Project_Request_Submitted__c FROM Lead WHERE Id = :leadId LIMIT 1 ];
            
            if (leadRecords.isEmpty()) {
                RestContext.response.statusCode = 404;
                response.message = 'The prospect Lead record was not found.';
                return response;
            }

            Lead leadRecord = leadRecords[0];
            response.success = true;
            response.leadId = leadRecord.Id;
            response.projectSubmitted = leadRecord.Project_Request_Submitted__c == true;
            response.firstName = leadRecord.FirstName;
            response.lastName = leadRecord.LastName;
            response.email = leadRecord.Email;
            response.phone = leadRecord.Phone;
            response.siteSpace = leadRecord.Site_Space__c == null ? null : String.valueOf( leadRecord.Site_Space__c );
            response.typeOfProject = leadRecord.Type_Of_Project__c;
            response.projectScope = leadRecord.Project_Scope__c;
            response.planLevel = leadRecord.Plan_Level__c;
            response.customerBudget = leadRecord.Customer_Budget__c == null ? null : String.valueOf( leadRecord.Customer_Budget__c);
            response.siteLocation = leadRecord.Site_Location__c;
            response.projectDescription = leadRecord.Project_Description__c;
            
            if (response.projectSubmitted) {
                response.message = 'Submitted project details loaded successfully.';
            } else {
                response.message = 'Project details have not been submitted yet.';
            }
            RestContext.response.statusCode = 200;
            return response;

        } catch (QueryException exceptionValue) {
            RestContext.response.statusCode = 404;
            response.success = false;
            response.message = 'The prospect Lead record was not found.';
            return response;
        } catch (Exception exceptionValue) {
            RestContext.response.statusCode = 500;
            response.success = false;
            response.message = 'Unable to load project details. ' + exceptionValue.getMessage();
            return response;
        }
    }

    /*
     * Submits project details only once.
     */
    @HttpPost
    global static ProjectDetailsResponse updateProjectDetails() {

        ProjectDetailsResponse response = new ProjectDetailsResponse();
        try {
            RestContext.response.addHeader('Content-Type','application/json');
            
            String requestBody = RestContext.request == null || RestContext.request.requestBody == null
                    ? null : RestContext.request.requestBody.toString();
            
            if (String.isBlank(requestBody)) {
                RestContext.response.statusCode = 400;
                response.message = 'Request body is required.';
                return response;
            }

            Map<String, Object> requestData = (Map<String, Object>) JSON.deserializeUntyped( requestBody );
            String leadIdValue = getStringValue( requestData, 'leadId');
            if (String.isBlank(leadIdValue)) {
                RestContext.response.statusCode = 400;
                response.message = 'Lead ID is required.';
                return response;
            }

            Id leadId = parseLeadId(leadIdValue);

            if (leadId == null) {
                RestContext.response.statusCode = 400;
                response.message ='Invalid Salesforce Lead ID.';
                return response;
            }

            String siteSpace =getStringValue(requestData,'siteSpace');
            String typeOfProject =getStringValue(requestData,'typeOfProject');
            String projectScope =getStringValue(requestData,'projectScope');
            String planLevel =getStringValue(requestData,'planLevel');
            String customerBudget =getStringValue(requestData,'customerBudget');
            String siteLocation =getStringValue(requestData,'siteLocation');
            String projectDescription =getStringValue(requestData,'projectDescription');
            //String quotationType = getStringValue(requestData,'quotationType');

            if (String.isBlank(siteSpace) || String.isBlank(typeOfProject) || String.isBlank(projectScope) ||
                String.isBlank(planLevel) || String.isBlank(customerBudget) || String.isBlank(siteLocation) 
                || String.isBlank(projectDescription))
            {
                RestContext.response.statusCode = 400;
                response.message = 'All project details are required.';
                return response;
            }

            // if (quotationType != 'Manual' && quotationType != 'Automation') {
            //     RestContext.response.statusCode = 400;
            //     response.message = 'Invalid quotation type.';
            //     return response;
            // }

            Set<String> validProjectTypes = new Set<String>{'Home', 'Office', 'Only Project Plan'};
            Set<String> validProjectScopes = new Set<String>{'Full Home Interiors','Home Decor','Kitchen','Bed Room','Hall Interior',
                                            'Conference Hall','Fully Office Interiors','Office Decor','Office Space','Dining Hall',
                                            'Cabins','1BHK','2BHK','3BHK','4BHK','5BHK','1RK'};

            Set<String> validPlanLevels = new Set<String>{'Standard','Premium','Luxury'};
            
            if(!validProjectTypes.contains(typeOfProject)) {
                RestContext.response.statusCode = 400;
                response.message = 'Invalid Type Of Project value.';
                return response;
            }

            if(!validProjectScopes.contains(projectScope)) {
                RestContext.response.statusCode = 400;
                response.message = 'Invalid Project Scope value.';
                return response;
            }
            
            if (!validPlanLevels.contains(planLevel)) {
                RestContext.response.statusCode = 400;
                response.message = 'Invalid Plan Level value.';
                return response;
            }
            
            Decimal parsedBudget;

            try {
                parsedBudget = Decimal.valueOf(customerBudget);
            } catch (Exception budgetException) {
                RestContext.response.statusCode = 400;
                response.message = 'Enter a valid customer budget.';
                return response;
            }
            
            if(parsedBudget <= 0) {
                RestContext.response.statusCode = 400;
                response.message = 'Customer budget must be greater than zero.';
                return response;
            }

            List<Lead> leadRecords = [SELECT Id, Project_Request_Submitted__c FROM Lead WHERE Id = :leadId LIMIT 1];

            if (leadRecords.isEmpty()) {
                RestContext.response.statusCode = 404;
                response.message = 'The prospect Lead record was not found.';
                return response;
            }
            
            Lead leadRecord = leadRecords[0];
            
            /*
             * Server-side protection:
             * submitted records cannot be edited.
             */
            if (leadRecord.Project_Request_Submitted__c == true) {
                RestContext.response.statusCode = 409;
                response.success = false;
                response.projectSubmitted = true;
                response.leadId = leadRecord.Id;
                response.message = 'Your project details have already been submitted. '
                    + 'You cannot edit or submit another response. ' + 'For any changes, please contact our team.';
                
                return response;
            }
            
            leadRecord.Site_Space__c = siteSpace;
            leadRecord.Type_Of_Project__c = typeOfProject;
            leadRecord.Project_Scope__c = projectScope;
            leadRecord.Plan_Level__c = planLevel;
            leadRecord.Customer_Budget__c = parsedBudget;
            leadRecord.Site_Location__c = siteLocation;
            leadRecord.Project_Description__c = projectDescription;
            leadRecord.Project_Request_Quotation_Type__c = 'Manual';
            leadRecord.Project_Request_Submitted__c = true;
            
            update as system leadRecord;
            
            RestContext.response.statusCode = 200;
            response.success = true;
            response.projectSubmitted = true;
            response.leadId = leadRecord.Id;
            response.message = 'Project details submitted successfully.';
            return response;

        } catch (DmlException exceptionValue) {
            RestContext.response.statusCode = 400;
            response.success = false;
            response.message = exceptionValue.getDmlMessage(0);
            return response;
            
        } catch (QueryException exceptionValue) {
            RestContext.response.statusCode = 404;
            response.success = false;
            response.message = 'The prospect Lead record was not found.';
            return response;
            
        } catch (Exception exceptionValue) {
            RestContext.response.statusCode = 500;
            response.success = false;
            response.message = exceptionValue.getMessage();
            return response;
        }
    }

    private static Id parseLeadId(String leadIdValue) {
        if (String.isBlank(leadIdValue)) {
            return null;
        }
        try {
            Id parsedId =(Id) leadIdValue.trim();
            if(parsedId.getSObjectType() != Lead.SObjectType) {
                return null;
            }
            return parsedId;
        } catch (Exception exceptionValue) {
            return null;
        }
    }

    private static String getStringValue(Map<String, Object> requestData,String fieldName) {
        if (requestData == null || !requestData.containsKey(fieldName) || requestData.get(fieldName) == null ) {
            return null;
        }

        String value = String.valueOf(requestData.get(fieldName)).trim();
        if (String.isBlank(value) || value.toLowerCase() == 'null' ) {
            return null;
        }
        return value;
    }
}
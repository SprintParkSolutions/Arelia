@RestResource(urlMapping='/registration/lead/project-details')
global without sharing class ProspectProjectDetailsApi {

    global class ProjectDetailsResponse {
        public Boolean success;
        public String message;
        public Id leadId;
        public List<ProjectDetailsResponse> projects;

        public Boolean projectSubmitted;
        public String approvalStatus;

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
            List<Lead> leadRecords = [SELECT Id, Portal_Account_Key__c, FirstName, LastName, Email, Phone, Site_Space__c,
                        Type_Of_Project__c, Project_Scope__c, Plan_Level__c, Customer_Budget__c, Site_Location__c,
                        Project_Description__c, Approval_Status__c, Project_Request_Submitted__c FROM Lead WHERE Id = :leadId LIMIT 1 ];
            
            if (leadRecords.isEmpty()) {
                RestContext.response.statusCode = 404;
                response.message = 'The prospect Lead record was not found.';
                return response;
            }

            Lead leadRecord = leadRecords[0];
            response.success = true;
            response.leadId = leadRecord.Id;
            response.projectSubmitted = leadRecord.Project_Request_Submitted__c == true;
            response.approvalStatus = leadRecord.Approval_Status__c;
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
            
            String accountKey = String.isBlank(leadRecord.Portal_Account_Key__c)
                ? String.valueOf(leadRecord.Id) : leadRecord.Portal_Account_Key__c;
            response.projects = new List<ProjectDetailsResponse>();
            for (Lead project : [SELECT Id, Site_Space__c, Type_Of_Project__c, Project_Scope__c,
                Plan_Level__c, Customer_Budget__c, Site_Location__c, Project_Description__c,
                Project_Request_Submitted__c, Approval_Status__c FROM Lead
                WHERE Id = :accountKey OR Portal_Account_Key__c = :accountKey
                ORDER BY CreatedDate ASC, Id ASC]) {
                ProjectDetailsResponse item = new ProjectDetailsResponse();
                item.success = true;
                item.leadId = project.Id;
                item.projectSubmitted = project.Project_Request_Submitted__c == true;
                item.approvalStatus = project.Approval_Status__c;
                item.siteSpace = project.Site_Space__c == null ? null : String.valueOf(project.Site_Space__c);
                item.typeOfProject = project.Type_Of_Project__c;
                item.projectScope = project.Project_Scope__c;
                item.planLevel = project.Plan_Level__c;
                item.customerBudget = project.Customer_Budget__c == null ? null : String.valueOf(project.Customer_Budget__c);
                item.siteLocation = project.Site_Location__c;
                item.projectDescription = project.Project_Description__c;
                response.projects.add(item);
            }

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
     * Submits each project once; createNewProject inserts a separate linked Lead.
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
            Boolean createNewProject = requestData.get('createNewProject') == true;
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

            Boolean isScopeDisabled = typeOfProject == 'Interior Combo Package' || typeOfProject == 'Only Project Plan';
            if (isScopeDisabled) projectScope = null;

            if (String.isBlank(siteSpace) || String.isBlank(typeOfProject) || (!isScopeDisabled && String.isBlank(projectScope)) ||
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

            Set<String> validProjectTypes = new Set<String>{'Home', 'Office', 'Interior Combo Package', 'Only Project Plan'};
            Set<String> validProjectScopes = new Set<String>{'Full Home Interiors','Home Decor','Kitchen','Bed Room','Hall Interior',
                                            'Conference Hall','Fully Office Interiors','Office Decor','Office Space','Dining Hall',
                                            'Cabins','1BHK','2BHK','3BHK','4BHK','5BHK','1RK'};

            Set<String> validPlanLevels = new Set<String>{'Standard','Premium','Luxury'};
            
            if(!validProjectTypes.contains(typeOfProject)) {
                RestContext.response.statusCode = 400;
                response.message = 'Invalid Type Of Project value.';
                return response;
            }

            if(!isScopeDisabled && !validProjectScopes.contains(projectScope)) {
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

            List<Lead> leadRecords = [SELECT Id, FirstName, LastName, Company, Email, Phone,
                Enter_Password__c, Confirm_password__c, IsConverted, ConvertedContactId,
                Portal_Account_Key__c, Project_Request_Submitted__c FROM Lead WHERE Id = :leadId LIMIT 1 FOR UPDATE];

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
            if (!createNewProject && leadRecord.Project_Request_Submitted__c == true) {
                RestContext.response.statusCode = 409;
                response.success = false;
                response.projectSubmitted = true;
                response.leadId = leadRecord.Id;
                response.message = 'Your project details have already been submitted. '
                    + 'You cannot edit or submit another response. ' + 'For any changes, please contact our team.';
                
                return response;
            }
            
            if (createNewProject) {
                Lead source = leadRecord;
                String email = source.Email;
                String password = source.Enter_Password__c;
                String firstName = source.FirstName;
                String lastName = source.LastName;
                String phone = source.Phone;
                if (source.IsConverted && source.ConvertedContactId != null) {
                    Contact client = [SELECT FirstName, LastName, Email, Phone, Password__c
                        FROM Contact WHERE Id = :source.ConvertedContactId LIMIT 1];
                    email = client.Email;
                    password = client.Password__c;
                    firstName = client.FirstName;
                    lastName = client.LastName;
                    phone = client.Phone;
                }
                if (String.isBlank(email) || String.isBlank(password)) {
                    RestContext.response.statusCode = 400;
                    response.message = 'The source customer does not have portal credentials.';
                    return response;
                }
                leadRecord = new Lead(FirstName = firstName, LastName = lastName,
                    Company = source.Company, Email = email, Phone = phone,
                    Enter_Password__c = password, Confirm_password__c = password,
                    Portal_Account_Key__c = String.isBlank(source.Portal_Account_Key__c)
                        ? String.valueOf(source.Id) : source.Portal_Account_Key__c);
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
            
            if (createNewProject) {
                Database.DMLOptions options = new Database.DMLOptions();
                options.DuplicateRuleHeader.allowSave = true;
                options.DuplicateRuleHeader.runAsCurrentUser = true;
                Database.SaveResult saved = Database.insert(leadRecord, options, AccessLevel.SYSTEM_MODE);
                if (!saved.isSuccess()) {
                    RestContext.response.statusCode = 400;
                    response.message = saved.getErrors()[0].getMessage();
                    return response;
                }
            } else {
                update as system leadRecord;
            }
            
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
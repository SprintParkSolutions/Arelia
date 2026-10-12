/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ProspectProjectDetailsApiTest
 * Author          : Arelia
 * Created Date    : Oct 6, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 6, 2026
 * Description     : This test class is for ProspectProjectDetailsApi
 */

@IsTest
private class ProspectProjectDetailsApiTest {

    private static final String TEST_EMAIL = 'projects@example.com';
    private static final String TEST_PHONE = '9876543210';
    private static final String TEST_PASSWORD = 'Example123!';
    private static final String CURRENT_EMAIL = 'current@example.com';
    private static final String CURRENT_PASSWORD = 'Current123!';

    private static final String SITE_SPACE = '1200';
    private static final String PROJECT_TYPE = 'Home';
    private static final String PROJECT_SCOPE = 'Kitchen';
    private static final String PLAN_LEVEL = 'Standard';
    private static final String CUSTOMER_BUDGET = '50000';
    private static final String PROJECT_DESCRIPTION = 'Project brief';

    private static Lead createClient() {
        Lead clientLead = new Lead(
            FirstName = 'Portal',
            LastName = 'Client',
            Company = 'self',
            Email = TEST_EMAIL,
            Phone = TEST_PHONE,
            Enter_Password__c = TEST_PASSWORD,
            Confirm_password__c = TEST_PASSWORD
        );

        insert clientLead;
        return clientLead;
    }

    private static Map<String, Object> createValidPayload(Id leadId, Boolean createNewProject, String siteLocation) {
        return new Map<String, Object>{
            'leadId' => leadId,
            'createNewProject' => createNewProject,
            'siteSpace' => SITE_SPACE,
            'typeOfProject' => PROJECT_TYPE,
            'projectScope' => PROJECT_SCOPE,
            'planLevel' => PLAN_LEVEL,
            'customerBudget' => CUSTOMER_BUDGET,
            'siteLocation' => siteLocation,
            'projectDescription' => PROJECT_DESCRIPTION
        };
    }

    private static void setPostRequest(Map<String, Object> payload) {
        RestRequest request = new RestRequest();
        request.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    private static void setGetRequest(String leadId) {
        RestRequest request = new RestRequest();

        if (leadId != null) {
            request.addParameter('leadId', leadId);
        }

        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    private static ProspectProjectDetailsApi.ProjectDetailsResponse submitProject(Id leadId, Boolean createNewProject, String siteLocation) {
        Map<String, Object> payload = createValidPayload(
            leadId,
            createNewProject,
            siteLocation
        );

        setPostRequest(payload);

        return ProspectProjectDetailsApi.updateProjectDetails();
    }

    private static ProspectProjectDetailsApi.ProjectDetailsResponse submitPayload(Map<String, Object> payload) {
        setPostRequest(payload);

        return ProspectProjectDetailsApi.updateProjectDetails();
    }

    private static ProspectProjectDetailsApi.ProjectDetailsResponse loadProjects(Id leadId) {
        setGetRequest(String.valueOf(leadId));

        return ProspectProjectDetailsApi.getProjectDetails();
    }

    private static void assertSuccessfulSubmission(ProspectProjectDetailsApi.ProjectDetailsResponse response) {
        System.assertEquals(
            true,
            response.success,
            response.message
        );

        System.assertEquals(
            true,
            response.projectSubmitted,
            'Project should be marked as submitted.'
        );

        System.assertNotEquals(
            null,
            response.leadId,
            'Lead Id should be returned after submission.'
        );
    }

    private static void assertBadRequest(ProspectProjectDetailsApi.ProjectDetailsResponse response) {
        System.assertEquals(
            false,
            response.success,
            'Request should fail.'
        );

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Expected HTTP 400 status.'
        );
    }

    private static Database.LeadConvertResult convertLead(Id leadId) {
        LeadStatus convertedStatus = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ];

        Database.LeadConvert conversion = new Database.LeadConvert();
        conversion.setLeadId(leadId);
        conversion.setOwnerId(UserInfo.getUserId());
        conversion.setConvertedStatus(convertedStatus.MasterLabel);
        conversion.setDoNotCreateOpportunity(true);

        return Database.convertLead(conversion);
    }

    @IsTest
    static void createsSeparateLeadAndPreservesOriginal() {
        Lead originalLead = createClient();

        ProspectProjectDetailsApi.ProjectDetailsResponse originalResponse =
            submitProject(
                originalLead.Id,
                false,
                'First site'
            );

        assertSuccessfulSubmission(originalResponse);

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse newProjectResponse =
            submitProject(
                originalLead.Id,
                true,
                'Second site'
            );

        Test.stopTest();

        assertSuccessfulSubmission(newProjectResponse);

        System.assertNotEquals(
            originalLead.Id,
            newProjectResponse.leadId,
            'Additional project should create a separate Lead.'
        );

        verifyAdditionalLead(
            originalLead,
            newProjectResponse.leadId
        );

        verifyOriginalLeadPreserved(originalLead.Id);

        verifySubmittedProjectCannotBeOverwritten(originalLead.Id);

        verifyBothProjectsAreReturned(
            originalLead.Id,
            newProjectResponse.leadId
        );
    }

    private static void verifyAdditionalLead(Lead originalLead, Id additionalLeadId) {
        Lead additionalLead = [
            SELECT
                Email,
                Enter_Password__c,
                Confirm_password__c,
                Portal_Account_Key__c,
                Site_Location__c,
                Project_Request_Submitted__c
            FROM Lead
            WHERE Id = :additionalLeadId
            LIMIT 1
        ];

        System.assertEquals(
            originalLead.Email,
            additionalLead.Email,
            'Email should be copied from the original Lead.'
        );

        System.assertEquals(
            originalLead.Enter_Password__c,
            additionalLead.Enter_Password__c,
            'Password should be copied from the original Lead.'
        );

        System.assertEquals(
            originalLead.Enter_Password__c,
            additionalLead.Confirm_password__c,
            'Confirmed password should match the original password.'
        );

        System.assertEquals(
            String.valueOf(originalLead.Id),
            additionalLead.Portal_Account_Key__c,
            'Additional Lead should reference the original Lead.'
        );

        System.assertEquals(
            'Second site',
            additionalLead.Site_Location__c,
            'Additional project should contain the new site location.'
        );

        System.assertEquals(
            true,
            additionalLead.Project_Request_Submitted__c,
            'Additional project should be marked as submitted.'
        );
    }

    private static void verifyOriginalLeadPreserved(Id originalLeadId) {
        Lead originalLead = [
            SELECT Site_Location__c
            FROM Lead
            WHERE Id = :originalLeadId
            LIMIT 1
        ];

        System.assertEquals(
            'First site',
            originalLead.Site_Location__c,
            'Original project details should remain unchanged.'
        );
    }

    private static void verifySubmittedProjectCannotBeOverwritten(Id originalLeadId) {
        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            submitProject(
                originalLeadId,
                false,
                'Overwrite'
            );

        System.assertEquals(
            false,
            response.success,
            'Previously submitted project should not be overwritten.'
        );

        System.assertEquals(
            409,
            RestContext.response.statusCode,
            'Previously submitted project should return HTTP 409.'
        );
    }

    private static void verifyBothProjectsAreReturned(Id originalLeadId, Id additionalLeadId) {
        List<Id> projectLeadIds = new List<Id>{
            originalLeadId,
            additionalLeadId
        };

        for (Id projectLeadId : projectLeadIds) {
            ProspectProjectDetailsApi.ProjectDetailsResponse response =
                loadProjects(projectLeadId);

            System.assertEquals(
                true,
                response.success,
                response.message
            );

            System.assertEquals(
                2,
                response.projects.size(),
                'Both linked projects should be returned.'
            );
        }
    }

    @IsTest
    static void invalidNewProjectDoesNotCreateLead() {
        Lead originalLead = createClient();

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            submitProject(
                originalLead.Id,
                true,
                ''
            );

        Test.stopTest();

        assertBadRequest(response);

        Integer leadCount = [
            SELECT COUNT()
            FROM Lead
        ];

        System.assertEquals(
            1,
            leadCount,
            'Invalid project submission should not create another Lead.'
        );
    }

    @IsTest
    static void convertedClientUsesCurrentCredentials() {
        Lead originalLead = createClient();

        ProspectProjectDetailsApi.ProjectDetailsResponse initialResponse =
            submitProject(
                originalLead.Id,
                false,
                'Original site'
            );

        assertSuccessfulSubmission(initialResponse);

        prepareLeadForConversion(originalLead.Id);

        Database.LeadConvertResult conversionResult =
            convertLead(originalLead.Id);

        System.assertEquals(
            true,
            conversionResult.isSuccess(),
            'Lead conversion should succeed.'
        );

        updateConvertedContact(conversionResult.getContactId());

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            submitProject(
                originalLead.Id,
                true,
                'New site'
            );

        Test.stopTest();

        assertSuccessfulSubmission(response);

        verifyCurrentContactCredentials(response.leadId);
    }

    private static void prepareLeadForConversion(Id leadId) {
        Lead leadToUpdate = new Lead(
            Id = leadId,
            Site_Visit_Manager_Approval__c = true,
            Approval_Status__c = 'Approved'
        );

        update leadToUpdate;
    }

    private static void updateConvertedContact(Id contactId) {
        Contact clientContact = new Contact(
            Id = contactId,
            Email = CURRENT_EMAIL,
            Password__c = CURRENT_PASSWORD
        );

        update clientContact;
    }

    private static void verifyCurrentContactCredentials(Id additionalLeadId) {
        Lead additionalLead = [
            SELECT
                Email,
                Enter_Password__c
            FROM Lead
            WHERE Id = :additionalLeadId
            LIMIT 1
        ];

        System.assertEquals(
            CURRENT_EMAIL,
            additionalLead.Email,
            'Additional Lead should use the current Contact email.'
        );

        System.assertEquals(
            CURRENT_PASSWORD,
            additionalLead.Enter_Password__c,
            'Additional Lead should use the current Contact password.'
        );
    }

    @IsTest
    static void rejectsInvalidRequestsWithoutCreatingProjects() {
        Lead originalLead = createClient();

        ProspectProjectDetailsApi.ProjectDetailsResponse initialResponse =
            submitProject(
                originalLead.Id,
                false,
                'First site'
            );

        assertSuccessfulSubmission(initialResponse);

        Map<String, Object> validPayload =
            createValidPayload(
                originalLead.Id,
                true,
                'Second site'
            );

        Test.startTest();

        verifyInvalidFieldValues(validPayload);
        verifyInvalidBudget(validPayload);
        verifyMissingRequestBody();
        verifyEmptyRequestBody();
        verifyInvalidGetRequests();

        Test.stopTest();

        Integer leadCount = [
            SELECT COUNT()
            FROM Lead
        ];

        System.assertEquals(
            1,
            leadCount,
            'Invalid requests should not create additional Leads.'
        );
    }

    private static void verifyInvalidFieldValues(Map<String, Object> validPayload) {
        Map<String, String> invalidValues = new Map<String, String>{
            'leadId' => 'not-an-id',
            'typeOfProject' => 'Invalid',
            'projectScope' => 'Invalid',
            'planLevel' => 'Invalid',
            'customerBudget' => 'invalid'
        };

        for (String fieldName : invalidValues.keySet()) {
            Map<String, Object> invalidPayload =
                validPayload.clone();

            invalidPayload.put(
                fieldName,
                invalidValues.get(fieldName)
            );

            ProspectProjectDetailsApi.ProjectDetailsResponse response =
                submitPayload(invalidPayload);

            assertBadRequest(response);
        }
    }

    private static void verifyInvalidBudget(Map<String, Object> validPayload) {
        Map<String, Object> zeroBudgetPayload =
            validPayload.clone();

        zeroBudgetPayload.put(
            'customerBudget',
            '0'
        );

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            submitPayload(zeroBudgetPayload);

        assertBadRequest(response);
    }

    private static void verifyMissingRequestBody() {
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            ProspectProjectDetailsApi.updateProjectDetails();

        assertBadRequest(response);
    }

    private static void verifyEmptyRequestBody() {
        RestRequest request = new RestRequest();
        request.requestBody = Blob.valueOf('{}');

        RestContext.request = request;
        RestContext.response = new RestResponse();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            ProspectProjectDetailsApi.updateProjectDetails();

        assertBadRequest(response);
    }

    private static void verifyInvalidGetRequests() {
        setGetRequest(null);

        ProspectProjectDetailsApi.ProjectDetailsResponse missingLeadResponse =
            ProspectProjectDetailsApi.getProjectDetails();

        assertBadRequest(missingLeadResponse);

        setGetRequest('not-an-id');

        ProspectProjectDetailsApi.ProjectDetailsResponse invalidLeadResponse =
            ProspectProjectDetailsApi.getProjectDetails();

        assertBadRequest(invalidLeadResponse);
    }
}
/**
 * -----------------------------------------------------------------------------
 * Class Name      : ProspectProjectDetailsApiTest
 * Author          : Arelia
 * Created Date    : Oct 6, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 23, 2026
 * Description     : Unit tests for ProspectProjectDetailsApi.
 *                   Covers GET and POST operations, initial project submission, additional project creation, linked
 *                   projects, converted customer credentials, field validations, duplicate submission prevention, and error handling.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ProspectProjectDetailsApiTest {

    private static final String TEST_EMAIL =
        'projects@example.com';
    private static final String TEST_PHONE =
        '9876543210';
    private static final String TEST_PASSWORD =
        'Example123!';
    private static final String CURRENT_EMAIL =
        'current@example.com';
    private static final String CURRENT_PASSWORD =
        'Current123!';

    private static final String SITE_SPACE = '1200';
    private static final String PROJECT_TYPE = 'Home';
    private static final String PROJECT_SCOPE = 'Kitchen';
    private static final String PLAN_LEVEL = 'Standard';
    private static final String CUSTOMER_BUDGET = '50000';
    private static final String PROJECT_DESCRIPTION =
        'Project brief';
    private static final String FIRST_SITE = 'First site';
    private static final String SECOND_SITE = 'Second site';

    private static final Integer STATUS_SUCCESS = 200;
    private static final Integer STATUS_BAD_REQUEST = 400;
    private static final Integer STATUS_NOT_FOUND = 404;
    private static final Integer STATUS_CONFLICT = 409;
    private static final Integer STATUS_SERVER_ERROR = 500;

    private static final String ENDPOINT =
        '/services/apexrest/registration/lead/project-details';

    /*
     * =========================================================
     * TEST DATA HELPERS
     * =========================================================
     */

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

    private static Map<String, Object> createValidPayload(
        Id leadId,
        Boolean createNewProject,
        String siteLocation
    ) {

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

    /*
     * =========================================================
     * REST REQUEST HELPERS
     * =========================================================
     */

    private static void setPostRequest(
        Map<String, Object> payload
    ) {

        RestRequest request = new RestRequest();

        request.requestURI = ENDPOINT;
        request.httpMethod = 'POST';

        if (payload != null) {
            request.requestBody =
                Blob.valueOf(JSON.serialize(payload));
        }

        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    private static void setRawPostRequest(
        String requestBody
    ) {

        RestRequest request = new RestRequest();

        request.requestURI = ENDPOINT;
        request.httpMethod = 'POST';

        if (requestBody != null) {
            request.requestBody =
                Blob.valueOf(requestBody);
        }

        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    private static void setGetRequest(
        String leadId
    ) {

        RestRequest request = new RestRequest();

        request.requestURI = ENDPOINT;
        request.httpMethod = 'GET';

        if (leadId != null) {
            request.addParameter('leadId', leadId);
        }

        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    private static ProspectProjectDetailsApi.ProjectDetailsResponse
        submitPayload(Map<String, Object> payload) {

        setPostRequest(payload);

        return ProspectProjectDetailsApi.updateProjectDetails();
    }

    private static ProspectProjectDetailsApi.ProjectDetailsResponse
        submitProject(
            Id leadId,
            Boolean createNewProject,
            String siteLocation
        ) {

        return submitPayload(
            createValidPayload(
                leadId,
                createNewProject,
                siteLocation
            )
        );
    }

    private static ProspectProjectDetailsApi.ProjectDetailsResponse
        loadProjects(Id leadId) {

        setGetRequest(String.valueOf(leadId));

        return ProspectProjectDetailsApi.getProjectDetails();
    }

    /*
     * =========================================================
     * ASSERTION HELPERS
     * =========================================================
     */

    private static void assertSuccessfulSubmission(
        ProspectProjectDetailsApi.ProjectDetailsResponse response
    ) {

        System.assertEquals(
            true,
            response.success,
            response.message
        );

        System.assertEquals(
            true,
            response.projectSubmitted,
            'Project should be submitted.'
        );

        System.assertNotEquals(
            null,
            response.leadId,
            'Submitted Lead ID should be returned.'
        );

        System.assertEquals(
            STATUS_SUCCESS,
            RestContext.response.statusCode,
            'Expected HTTP 200.'
        );

        System.assertEquals(
            'Project details submitted successfully.',
            response.message,
            'Unexpected submission message.'
        );
    }

    private static void assertBadRequest(
        ProspectProjectDetailsApi.ProjectDetailsResponse response
    ) {

        System.assertEquals(
            false,
            response.success,
            'Request should fail.'
        );

        System.assertEquals(
            STATUS_BAD_REQUEST,
            RestContext.response.statusCode,
            'Expected HTTP 400.'
        );
    }

    private static void assertNotFound(
        ProspectProjectDetailsApi.ProjectDetailsResponse response
    ) {

        System.assertEquals(
            false,
            response.success,
            'Missing record should fail.'
        );

        System.assertEquals(
            STATUS_NOT_FOUND,
            RestContext.response.statusCode,
            'Expected HTTP 404.'
        );
    }

    private static void assertValidationMessage(
        Map<String, Object> payload,
        String expectedMessage
    ) {

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            submitPayload(payload);

        assertBadRequest(response);

        System.assertEquals(
            expectedMessage,
            response.message,
            'Unexpected validation message.'
        );
    }

    /*
     * =========================================================
     * TEST 1 - INITIAL PROJECT SUBMISSION
     * =========================================================
     */

    @IsTest
    static void initialProjectSubmissionSucceeds() {

        Lead originalLead = createClient();

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            submitProject(
                originalLead.Id,
                false,
                FIRST_SITE
            );

        Test.stopTest();

        assertSuccessfulSubmission(response);

        System.assertEquals(
            originalLead.Id,
            response.leadId,
            'Existing Lead must be updated.'
        );

        Lead submittedLead = [
            SELECT
                Site_Space__c,
                Type_Of_Project__c,
                Project_Scope__c,
                Plan_Level__c,
                Customer_Budget__c,
                Site_Location__c,
                Project_Description__c,
                Project_Request_Quotation_Type__c,
                Project_Request_Submitted__c
            FROM Lead
            WHERE Id = :originalLead.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            submittedLead.Project_Request_Submitted__c
        );

        System.assertEquals(
            PROJECT_TYPE,
            submittedLead.Type_Of_Project__c
        );

        System.assertEquals(
            PROJECT_SCOPE,
            submittedLead.Project_Scope__c
        );

        System.assertEquals(
            PLAN_LEVEL,
            submittedLead.Plan_Level__c
        );

        System.assertEquals(
            Decimal.valueOf(CUSTOMER_BUDGET),
            submittedLead.Customer_Budget__c
        );

        System.assertEquals(
            FIRST_SITE,
            submittedLead.Site_Location__c
        );

        System.assertEquals(
            PROJECT_DESCRIPTION,
            submittedLead.Project_Description__c
        );

        System.assertEquals(
            'Manual',
            submittedLead.Project_Request_Quotation_Type__c
        );
    }

    /*
     * =========================================================
     * TEST 2 - ADDITIONAL PROJECT CREATION
     * =========================================================
     */

    @IsTest
    static void createsSeparateLeadAndPreservesOriginal() {

        Lead originalLead = createClient();

        assertSuccessfulSubmission(
            submitProject(
                originalLead.Id,
                false,
                FIRST_SITE
            )
        );

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            submitProject(
                originalLead.Id,
                true,
                SECOND_SITE
            );

        Test.stopTest();

        assertSuccessfulSubmission(response);

        System.assertNotEquals(
            originalLead.Id,
            response.leadId,
            'Additional project must create a new Lead.'
        );

        verifyAdditionalLead(
            originalLead,
            response.leadId
        );

        verifyOriginalLeadPreserved(originalLead.Id);

        verifyBothProjectsAreReturned(
            originalLead.Id,
            response.leadId
        );
    }

    private static void verifyAdditionalLead(
        Lead originalLead,
        Id additionalLeadId
    ) {

        Lead additionalLead = [
            SELECT
                FirstName,
                LastName,
                Email,
                Phone,
                Enter_Password__c,
                Confirm_password__c,
                Portal_Account_Key__c,
                Site_Location__c,
                Project_Request_Submitted__c,
                Project_Request_Quotation_Type__c
            FROM Lead
            WHERE Id = :additionalLeadId
            LIMIT 1
        ];

        System.assertEquals(
            originalLead.FirstName,
            additionalLead.FirstName
        );

        System.assertEquals(
            originalLead.LastName,
            additionalLead.LastName
        );

        System.assertEquals(
            originalLead.Email,
            additionalLead.Email
        );

        System.assertEquals(
            originalLead.Phone,
            additionalLead.Phone
        );

        System.assertEquals(
            originalLead.Enter_Password__c,
            additionalLead.Enter_Password__c
        );

        System.assertEquals(
            originalLead.Enter_Password__c,
            additionalLead.Confirm_password__c
        );

        System.assertEquals(
            String.valueOf(originalLead.Id),
            additionalLead.Portal_Account_Key__c,
            'New project must reference original Lead.'
        );

        System.assertEquals(
            SECOND_SITE,
            additionalLead.Site_Location__c
        );

        System.assertEquals(
            true,
            additionalLead.Project_Request_Submitted__c
        );

        System.assertEquals(
            'Manual',
            additionalLead.Project_Request_Quotation_Type__c
        );
    }

    private static void verifyOriginalLeadPreserved(
        Id originalLeadId
    ) {

        Lead originalLead = [
            SELECT Site_Location__c
            FROM Lead
            WHERE Id = :originalLeadId
            LIMIT 1
        ];

        System.assertEquals(
            FIRST_SITE,
            originalLead.Site_Location__c,
            'Original project must remain unchanged.'
        );
    }

    private static void verifyBothProjectsAreReturned(
        Id originalLeadId,
        Id additionalLeadId
    ) {

        List<Id> projectIds = new List<Id>{
            originalLeadId,
            additionalLeadId
        };

        for (Id projectId : projectIds) {

            ProspectProjectDetailsApi.ProjectDetailsResponse response =
                loadProjects(projectId);

            System.assertEquals(
                true,
                response.success,
                response.message
            );

            System.assertEquals(
                STATUS_SUCCESS,
                RestContext.response.statusCode
            );

            System.assertEquals(
                2,
                response.projects.size(),
                'Both linked projects must be returned.'
            );

            Set<Id> returnedIds = new Set<Id>();

            for (
                ProspectProjectDetailsApi.ProjectDetailsResponse item
                : response.projects
            ) {
                returnedIds.add(item.leadId);

                System.assertEquals(
                    true,
                    item.projectSubmitted
                );

                System.assertEquals(
                    true,
                    item.success
                );
            }

            System.assert(
                returnedIds.contains(originalLeadId),
                'Original project is missing.'
            );

            System.assert(
                returnedIds.contains(additionalLeadId),
                'Additional project is missing.'
            );
        }
    }

    /*
     * =========================================================
     * TEST 3 - DUPLICATE SUBMISSION PREVENTION
     * =========================================================
     */

    @IsTest
    static void submittedProjectCannotBeOverwritten() {

        Lead originalLead = createClient();

        assertSuccessfulSubmission(
            submitProject(
                originalLead.Id,
                false,
                FIRST_SITE
            )
        );

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            submitProject(
                originalLead.Id,
                false,
                'Overwrite'
            );

        Test.stopTest();

        System.assertEquals(
            false,
            response.success
        );

        System.assertEquals(
            true,
            response.projectSubmitted
        );

        System.assertEquals(
            originalLead.Id,
            response.leadId
        );

        System.assertEquals(
            STATUS_CONFLICT,
            RestContext.response.statusCode
        );

        System.assert(
            response.message.contains('already been submitted'),
            'Duplicate submission message is missing.'
        );

        verifyOriginalLeadPreserved(originalLead.Id);
    }

    /*
     * =========================================================
     * TEST 4 - INVALID ADDITIONAL PROJECT
     * =========================================================
     */

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

        System.assertEquals(
            'All project details are required.',
            response.message
        );

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Lead],
            'Invalid project must not create a Lead.'
        );
    }

    /*
     * =========================================================
     * TEST 5 - CONVERTED CLIENT CREDENTIALS
     * =========================================================
     */

    @IsTest
    static void convertedClientUsesCurrentCredentials() {

        Lead originalLead = createClient();

        assertSuccessfulSubmission(
            submitProject(
                originalLead.Id,
                false,
                FIRST_SITE
            )
        );

        prepareLeadForConversion(originalLead.Id);

        Database.LeadConvertResult conversionResult =
            convertLead(originalLead.Id);

        System.assertEquals(
            true,
            conversionResult.isSuccess(),
            'Lead conversion must succeed.'
        );

        updateConvertedContact(
            conversionResult.getContactId()
        );

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            submitProject(
                originalLead.Id,
                true,
                SECOND_SITE
            );

        Test.stopTest();

        assertSuccessfulSubmission(response);

        Lead additionalLead = [
            SELECT
                FirstName,
                LastName,
                Email,
                Phone,
                Enter_Password__c,
                Confirm_password__c,
                Portal_Account_Key__c
            FROM Lead
            WHERE Id = :response.leadId
            LIMIT 1
        ];

        System.assertEquals(
            CURRENT_EMAIL,
            additionalLead.Email
        );

        System.assertEquals(
            CURRENT_PASSWORD,
            additionalLead.Enter_Password__c
        );

        System.assertEquals(
            CURRENT_PASSWORD,
            additionalLead.Confirm_password__c
        );

        System.assertEquals(
            String.valueOf(originalLead.Id),
            additionalLead.Portal_Account_Key__c
        );
    }

    private static void prepareLeadForConversion(
        Id leadId
    ) {

        update new Lead(
            Id = leadId,
            Site_Visit_Manager_Approval__c = true,
            Approval_Status__c = 'Approved'
        );
    }

    private static Database.LeadConvertResult convertLead(
        Id leadId
    ) {

        LeadStatus convertedStatus = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ];

        Database.LeadConvert conversion =
            new Database.LeadConvert();

        conversion.setLeadId(leadId);
        conversion.setOwnerId(UserInfo.getUserId());
        conversion.setConvertedStatus(
            convertedStatus.MasterLabel
        );
        conversion.setDoNotCreateOpportunity(true);

        return Database.convertLead(conversion);
    }

    private static void updateConvertedContact(
        Id contactId
    ) {

        update new Contact(
            Id = contactId,
            Email = CURRENT_EMAIL,
            Password__c = CURRENT_PASSWORD
        );
    }

    /*
     * =========================================================
     * TEST 6 - GET UNSUBMITTED PROJECT
     * =========================================================
     */

    @IsTest
    static void getUnsubmittedProjectReturnsDetails() {

        Lead originalLead = createClient();

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            loadProjects(originalLead.Id);

        Test.stopTest();

        System.assertEquals(
            true,
            response.success,
            response.message
        );

        System.assertEquals(
            STATUS_SUCCESS,
            RestContext.response.statusCode
        );

        System.assertEquals(
            false,
            response.projectSubmitted
        );

        System.assertEquals(
            false,
            response.isConverted
        );

        System.assertEquals(
            originalLead.Id,
            response.leadId
        );

        System.assertEquals(
            originalLead.FirstName,
            response.firstName
        );

        System.assertEquals(
            originalLead.LastName,
            response.lastName
        );

        System.assertEquals(
            TEST_EMAIL,
            response.email
        );

        System.assertEquals(
            TEST_PHONE,
            response.phone
        );

        System.assertEquals(
            null,
            response.convertedOpportunityId
        );

        System.assertEquals(
            null,
            response.convertedAccountId
        );

        System.assertEquals(
            null,
            response.convertedContactId
        );

        System.assertEquals(
            'Project details have not been submitted yet.',
            response.message
        );

        System.assertEquals(
            1,
            response.projects.size()
        );

        System.assertEquals(
            originalLead.Id,
            response.projects[0].leadId
        );

        System.assertEquals(
            false,
            response.projects[0].projectSubmitted
        );
    }

    /*
     * =========================================================
     * TEST 7 - GET SUBMITTED PROJECT
     * =========================================================
     */

    @IsTest
    static void getSubmittedProjectReturnsAllFields() {

        Lead originalLead = createClient();

        assertSuccessfulSubmission(
            submitProject(
                originalLead.Id,
                false,
                FIRST_SITE
            )
        );

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            loadProjects(originalLead.Id);

        Test.stopTest();

        System.assertEquals(
            true,
            response.success
        );

        System.assertEquals(
            true,
            response.projectSubmitted
        );

        System.assertEquals(
            STATUS_SUCCESS,
            RestContext.response.statusCode
        );

        System.assertEquals(
            'Submitted project details loaded successfully.',
            response.message
        );

        System.assertEquals(
            SITE_SPACE,
            response.siteSpace
        );

        System.assertEquals(
            PROJECT_TYPE,
            response.typeOfProject
        );

        System.assertEquals(
            PROJECT_SCOPE,
            response.projectScope
        );

        System.assertEquals(
            PLAN_LEVEL,
            response.planLevel
        );

        System.assertEquals(
            Decimal.valueOf(CUSTOMER_BUDGET),
            Decimal.valueOf(response.customerBudget),
            'Customer budget should match.'
        );

        System.assertEquals(
            FIRST_SITE,
            response.siteLocation
        );

        System.assertEquals(
            PROJECT_DESCRIPTION,
            response.projectDescription
        );

        System.assertEquals(
            1,
            response.projects.size()
        );

        ProspectProjectDetailsApi.ProjectDetailsResponse item =
            response.projects[0];

        System.assertEquals(
            true,
            item.success
        );

        System.assertEquals(
            originalLead.Id,
            item.leadId
        );

        System.assertEquals(
            SITE_SPACE,
            item.siteSpace
        );

        System.assertEquals(
            PROJECT_TYPE,
            item.typeOfProject
        );

        System.assertEquals(
            PROJECT_SCOPE,
            item.projectScope
        );

        System.assertEquals(
            PLAN_LEVEL,
            item.planLevel
        );

        System.assertEquals(
            Decimal.valueOf(CUSTOMER_BUDGET),
            Decimal.valueOf(item.customerBudget),
            'Project item customer budget should match.'
        );

        System.assertEquals(
            FIRST_SITE,
            item.siteLocation
        );

        System.assertEquals(
            PROJECT_DESCRIPTION,
            item.projectDescription
        );
    }

    /*
     * =========================================================
     * TEST 8 - INVALID FIELD VALUES
     * =========================================================
     */

    @IsTest
    static void invalidFieldValuesAreRejected() {

        Lead originalLead = createClient();

        Map<String, Object> validPayload =
            createValidPayload(
                originalLead.Id,
                false,
                FIRST_SITE
            );

        Test.startTest();

        verifyInvalidFields(validPayload);
        verifyInvalidBudget(validPayload);

        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Lead],
            'Invalid requests must not create Leads.'
        );
    }

    private static void verifyInvalidFields(
        Map<String, Object> validPayload
    ) {

        Map<String, String> invalidValues =
            new Map<String, String>{
                'typeOfProject' => 'Invalid',
                'projectScope' => 'Invalid',
                'planLevel' => 'Invalid'
            };

        Map<String, String> expectedMessages =
            new Map<String, String>{
                'typeOfProject' =>
                    'Invalid Type Of Project value.',
                'projectScope' =>
                    'Invalid Project Scope value.',
                'planLevel' =>
                    'Invalid Plan Level value.'
            };

        for (String fieldName : invalidValues.keySet()) {

            Map<String, Object> invalidPayload =
                validPayload.clone();

            invalidPayload.put(
                fieldName,
                invalidValues.get(fieldName)
            );

            assertValidationMessage(
                invalidPayload,
                expectedMessages.get(fieldName)
            );
        }
    }

    private static void verifyInvalidBudget(
        Map<String, Object> validPayload
    ) {

        List<String> invalidBudgets =
            new List<String>{
                'invalid',
                'abc123',
                '50000abc'
            };

        for (String budgetValue : invalidBudgets) {

            Map<String, Object> payload =
                validPayload.clone();

            payload.put(
                'customerBudget',
                budgetValue
            );

            assertValidationMessage(
                payload,
                'Enter a valid customer budget.'
            );
        }

        List<String> nonPositiveBudgets =
            new List<String>{
                '0',
                '-100',
                '-50000'
            };

        for (String budgetValue : nonPositiveBudgets) {

            Map<String, Object> payload =
                validPayload.clone();

            payload.put(
                'customerBudget',
                budgetValue
            );

            assertValidationMessage(
                payload,
                'Customer budget must be greater than zero.'
            );
        }
    }

    /*
     * =========================================================
     * TEST 9 - MISSING REQUIRED FIELDS
     * =========================================================
     */

    @IsTest
    static void missingRequiredFieldsAreRejected() {

        Lead originalLead = createClient();

        Map<String, Object> validPayload =
            createValidPayload(
                originalLead.Id,
                false,
                FIRST_SITE
            );

        List<String> requiredFields =
            new List<String>{
                'siteSpace',
                'typeOfProject',
                'projectScope',
                'planLevel',
                'customerBudget',
                'siteLocation',
                'projectDescription'
            };

        Test.startTest();

        for (String fieldName : requiredFields) {

            Map<String, Object> payload =
                validPayload.clone();

            payload.remove(fieldName);

            assertValidationMessage(
                payload,
                'All project details are required.'
            );
        }

        Test.stopTest();
    }

    /*
     * =========================================================
     * TEST 10 - BLANK AND NULL FIELD VALUES
     * =========================================================
     */

    @IsTest
    static void blankAndNullValuesAreRejected() {

        Lead originalLead = createClient();

        Map<String, Object> validPayload =
            createValidPayload(
                originalLead.Id,
                false,
                FIRST_SITE
            );

        Test.startTest();

        Map<String, Object> blankPayload =
            validPayload.clone();

        blankPayload.put(
            'siteLocation',
            '   '
        );

        assertValidationMessage(
            blankPayload,
            'All project details are required.'
        );

        Map<String, Object> nullPayload =
            validPayload.clone();

        nullPayload.put(
            'siteLocation',
            null
        );

        assertValidationMessage(
            nullPayload,
            'All project details are required.'
        );

        Map<String, Object> stringNullPayload =
            validPayload.clone();

        stringNullPayload.put(
            'projectDescription',
            'null'
        );

        assertValidationMessage(
            stringNullPayload,
            'All project details are required.'
        );

        Map<String, Object> mixedCaseNullPayload =
            validPayload.clone();

        mixedCaseNullPayload.put(
            'projectDescription',
            'NULL'
        );

        assertValidationMessage(
            mixedCaseNullPayload,
            'All project details are required.'
        );

        Test.stopTest();
    }

    /*
     * =========================================================
     * TEST 11 - INTERIOR COMBO PACKAGE
     * =========================================================
     */

    @IsTest
    static void interiorComboPackageClearsProjectScope() {

        Lead originalLead = createClient();

        Map<String, Object> payload =
            createValidPayload(
                originalLead.Id,
                false,
                FIRST_SITE
            );

        payload.put(
            'typeOfProject',
            'Interior Combo Package'
        );

        payload.remove('projectScope');

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            submitPayload(payload);

        Test.stopTest();

        assertSuccessfulSubmission(response);

        Lead submittedLead = [
            SELECT
                Type_Of_Project__c,
                Project_Scope__c
            FROM Lead
            WHERE Id = :originalLead.Id
            LIMIT 1
        ];

        System.assertEquals(
            'Interior Combo Package',
            submittedLead.Type_Of_Project__c
        );

        System.assertEquals(
            null,
            submittedLead.Project_Scope__c,
            'Project Scope must be null for combo package.'
        );
    }

    /*
     * =========================================================
     * TEST 12 - ONLY PROJECT PLAN
     * =========================================================
     */

    @IsTest
    static void onlyProjectPlanClearsProjectScope() {

        Lead originalLead = createClient();

        Map<String, Object> payload =
            createValidPayload(
                originalLead.Id,
                false,
                FIRST_SITE
            );

        payload.put(
            'typeOfProject',
            'Only Project Plan'
        );

        payload.put(
            'projectScope',
            'Invalid Scope'
        );

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            submitPayload(payload);

        Test.stopTest();

        assertSuccessfulSubmission(response);

        Lead submittedLead = [
            SELECT
                Type_Of_Project__c,
                Project_Scope__c
            FROM Lead
            WHERE Id = :originalLead.Id
            LIMIT 1
        ];

        System.assertEquals(
            'Only Project Plan',
            submittedLead.Type_Of_Project__c
        );

        System.assertEquals(
            null,
            submittedLead.Project_Scope__c,
            'Project Scope must be cleared.'
        );
    }

    /*
     * =========================================================
     * TEST 13 - OFFICE PROJECT
     * =========================================================
     */

    @IsTest
    static void officeProjectSubmissionSucceeds() {

        Lead originalLead = createClient();

        Map<String, Object> payload =
            createValidPayload(
                originalLead.Id,
                false,
                FIRST_SITE
            );

        payload.put(
            'typeOfProject',
            'Office'
        );

        payload.put(
            'projectScope',
            'Fully Office Interiors'
        );

        payload.put(
            'planLevel',
            'Premium'
        );

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            submitPayload(payload);

        Test.stopTest();

        assertSuccessfulSubmission(response);

        Lead submittedLead = [
            SELECT
                Type_Of_Project__c,
                Project_Scope__c,
                Plan_Level__c
            FROM Lead
            WHERE Id = :originalLead.Id
            LIMIT 1
        ];

        System.assertEquals(
            'Office',
            submittedLead.Type_Of_Project__c
        );

        System.assertEquals(
            'Fully Office Interiors',
            submittedLead.Project_Scope__c
        );

        System.assertEquals(
            'Premium',
            submittedLead.Plan_Level__c
        );
    }

    /*
     * =========================================================
     * TEST 14 - INVALID POST LEAD IDs
     * =========================================================
     */

    @IsTest
    static void invalidPostLeadIdsAreRejected() {

        Lead originalLead = createClient();

        Map<String, Object> validPayload =
            createValidPayload(
                originalLead.Id,
                false,
                FIRST_SITE
            );

        Test.startTest();

        List<String> invalidIds =
            new List<String>{
                'not-an-id',
                '12345',
                String.valueOf(UserInfo.getUserId())
            };

        for (String invalidId : invalidIds) {

            Map<String, Object> payload =
                validPayload.clone();

            payload.put('leadId', invalidId);

            assertValidationMessage(
                payload,
                'Invalid Salesforce Lead ID.'
            );
        }

        Map<String, Object> missingIdPayload =
            validPayload.clone();

        missingIdPayload.remove('leadId');

        assertValidationMessage(
            missingIdPayload,
            'Lead ID is required.'
        );

        Map<String, Object> blankIdPayload =
            validPayload.clone();

        blankIdPayload.put('leadId', '   ');

        assertValidationMessage(
            blankIdPayload,
            'Lead ID is required.'
        );

        Test.stopTest();
    }

    /*
     * =========================================================
     * TEST 15 - INVALID GET LEAD IDs
     * =========================================================
     */

    @IsTest
    static void invalidGetRequestsAreRejected() {

        Test.startTest();

        setGetRequest(null);

        ProspectProjectDetailsApi.ProjectDetailsResponse missingId =
            ProspectProjectDetailsApi.getProjectDetails();

        assertBadRequest(missingId);

        System.assertEquals(
            'Salesforce Lead ID is required.',
            missingId.message
        );

        setGetRequest('invalid-id');

        ProspectProjectDetailsApi.ProjectDetailsResponse invalidId =
            ProspectProjectDetailsApi.getProjectDetails();

        assertBadRequest(invalidId);

        System.assertEquals(
            'Invalid Salesforce Lead ID.',
            invalidId.message
        );

        setGetRequest(
            String.valueOf(UserInfo.getUserId())
        );

        ProspectProjectDetailsApi.ProjectDetailsResponse wrongType =
            ProspectProjectDetailsApi.getProjectDetails();

        assertBadRequest(wrongType);

        Test.stopTest();
    }

    /*
     * =========================================================
     * TEST 16 - NONEXISTENT LEAD
     * =========================================================
     */

    @IsTest
    static void nonexistentLeadReturnsNotFound() {

        String nonexistentLeadId =
            '00Q000000000000';

        Test.startTest();

        setGetRequest(nonexistentLeadId);

        ProspectProjectDetailsApi.ProjectDetailsResponse getResponse =
            ProspectProjectDetailsApi.getProjectDetails();

        assertNotFound(getResponse);

        System.assertEquals(
            'The prospect Lead record was not found.',
            getResponse.message
        );

        Map<String, Object> payload =
            createValidPayload(
                null,
                false,
                FIRST_SITE
            );

        payload.put(
            'leadId',
            nonexistentLeadId
        );

        ProspectProjectDetailsApi.ProjectDetailsResponse postResponse =
            submitPayload(payload);

        assertNotFound(postResponse);

        Test.stopTest();
    }

    /*
     * =========================================================
     * TEST 17 - EMPTY AND MALFORMED REQUEST BODY
     * =========================================================
     */

    @IsTest
    static void invalidRequestBodiesAreHandled() {

        Test.startTest();

        setRawPostRequest(null);

        ProspectProjectDetailsApi.ProjectDetailsResponse missingBody =
            ProspectProjectDetailsApi.updateProjectDetails();

        assertBadRequest(missingBody);

        System.assertEquals(
            'Request body is required.',
            missingBody.message
        );

        setRawPostRequest('');

        ProspectProjectDetailsApi.ProjectDetailsResponse emptyBody =
            ProspectProjectDetailsApi.updateProjectDetails();

        assertBadRequest(emptyBody);

        setRawPostRequest('{}');

        ProspectProjectDetailsApi.ProjectDetailsResponse emptyJson =
            ProspectProjectDetailsApi.updateProjectDetails();

        assertBadRequest(emptyJson);

        System.assertEquals(
            'Lead ID is required.',
            emptyJson.message
        );

        setRawPostRequest('{invalid-json');

        ProspectProjectDetailsApi.ProjectDetailsResponse malformedJson =
            ProspectProjectDetailsApi.updateProjectDetails();

        System.assertEquals(
            false,
            malformedJson.success
        );

        System.assertEquals(
            STATUS_SERVER_ERROR,
            RestContext.response.statusCode,
            'Malformed JSON should return HTTP 500.'
        );

        Test.stopTest();
    }

    /*
     * =========================================================
     * TEST 18 - LINKED PROJECTS FROM CHILD LEAD
     * =========================================================
     */

    @IsTest
    static void additionalProjectCanCreateAnotherProject() {

        Lead originalLead = createClient();

        assertSuccessfulSubmission(
            submitProject(
                originalLead.Id,
                false,
                FIRST_SITE
            )
        );

        ProspectProjectDetailsApi.ProjectDetailsResponse secondResponse =
            submitProject(
                originalLead.Id,
                true,
                SECOND_SITE
            );

        assertSuccessfulSubmission(secondResponse);

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse thirdResponse =
            submitProject(
                secondResponse.leadId,
                true,
                'Third site'
            );

        Test.stopTest();

        assertSuccessfulSubmission(thirdResponse);

        Lead thirdLead = [
            SELECT
                Portal_Account_Key__c,
                Site_Location__c
            FROM Lead
            WHERE Id = :thirdResponse.leadId
            LIMIT 1
        ];

        System.assertEquals(
            String.valueOf(originalLead.Id),
            thirdLead.Portal_Account_Key__c,
            'All additional projects must share the original key.'
        );

        System.assertEquals(
            'Third site',
            thirdLead.Site_Location__c
        );

        ProspectProjectDetailsApi.ProjectDetailsResponse getResponse =
            loadProjects(thirdResponse.leadId);

        System.assertEquals(
            true,
            getResponse.success
        );

        System.assertEquals(
            3,
            getResponse.projects.size(),
            'All three projects must be returned.'
        );

        Set<Id> returnedIds = new Set<Id>();

        for (
            ProspectProjectDetailsApi.ProjectDetailsResponse item
            : getResponse.projects
        ) {
            returnedIds.add(item.leadId);
        }

        System.assert(
            returnedIds.contains(originalLead.Id)
        );

        System.assert(
            returnedIds.contains(secondResponse.leadId)
        );

        System.assert(
            returnedIds.contains(thirdResponse.leadId)
        );
    }

    /*
     * =========================================================
     * TEST 19 - GET CONVERTED LEAD DETAILS
     * =========================================================
     */

    @IsTest
    static void getConvertedLeadReturnsConversionDetails() {

        Lead originalLead = createClient();

        assertSuccessfulSubmission(
            submitProject(
                originalLead.Id,
                false,
                FIRST_SITE
            )
        );

        prepareLeadForConversion(originalLead.Id);

        Database.LeadConvertResult conversionResult =
            convertLead(originalLead.Id);

        System.assertEquals(
            true,
            conversionResult.isSuccess()
        );

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            loadProjects(originalLead.Id);

        Test.stopTest();

        System.assertEquals(
            true,
            response.success,
            response.message
        );

        System.assertEquals(
            true,
            response.isConverted
        );

        System.assertEquals(
            conversionResult.getContactId(),
            response.convertedContactId
        );

        System.assertEquals(
            conversionResult.getAccountId(),
            response.convertedAccountId
        );

        System.assertEquals(
            true,
            response.projectSubmitted
        );

        System.assertEquals(
            STATUS_SUCCESS,
            RestContext.response.statusCode
        );

        System.assertEquals(
            1,
            response.projects.size()
        );

        System.assertEquals(
            true,
            response.projects[0].isConverted
        );
    }

    /*
     * =========================================================
     * TEST 20 - SOURCE CUSTOMER WITHOUT CREDENTIALS
     * =========================================================
     */

    @IsTest
    static void missingSourceCredentialsAreRejected() {

        Lead sourceLead = createClient();

        // Email is blank. The source cannot create another
        // project without the required portal credentials.
        update new Lead(
            Id = sourceLead.Id,
            Email = null
        );

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            submitProject(
                sourceLead.Id,
                true,
                SECOND_SITE
            );

        Test.stopTest();

        assertBadRequest(response);

        System.assertEquals(
            'The source customer does not have portal credentials.',
            response.message
        );

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Lead],
            'No additional project should be created.'
        );
    }

    /*
     * =========================================================
     * TEST 21 - TRIMMED REQUEST VALUES
     * =========================================================
     */

    @IsTest
    static void requestValuesAreTrimmed() {

        Lead originalLead = createClient();

        Map<String, Object> payload =
            createValidPayload(
                originalLead.Id,
                false,
                '  Hyderabad  '
            );

        payload.put(
            'leadId',
            '  ' + String.valueOf(originalLead.Id) + '  '
        );

        payload.put(
            'customerBudget',
            ' 50000 '
        );

        payload.put(
            'projectDescription',
            '  Interior work  '
        );

        Test.startTest();

        ProspectProjectDetailsApi.ProjectDetailsResponse response =
            submitPayload(payload);

        Test.stopTest();

        assertSuccessfulSubmission(response);

        Lead submittedLead = [
            SELECT
                Site_Location__c,
                Customer_Budget__c,
                Project_Description__c
            FROM Lead
            WHERE Id = :originalLead.Id
            LIMIT 1
        ];

        System.assertEquals(
            'Hyderabad',
            submittedLead.Site_Location__c
        );

        System.assertEquals(
            Decimal.valueOf(CUSTOMER_BUDGET),
            submittedLead.Customer_Budget__c
        );

        System.assertEquals(
            'Interior work',
            submittedLead.Project_Description__c
        );
    }
}
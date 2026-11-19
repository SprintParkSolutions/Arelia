/**
 * -----------------------------------------------------------------------------
 * Class Name      : ProspectSupervisorDetailsApiTest
 * Author          : Arelia
 * Created Date    : Oct 16, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 16, 2026
 * Description     : Unit tests for ProspectSupervisorDetailsApi.
 *                   Validates Lead ID handling, supervisor assignment,
 *                   approval requirements, missing records, successful
 *                   responses, fallback contact information, and JSON
 *                   response structure.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ProspectSupervisorDetailsApiTest {

    private static final Integer STATUS_SUCCESS = 200;
    private static final Integer STATUS_BAD_REQUEST = 400;
    private static final Integer STATUS_NOT_FOUND = 404;

    private static final String API_ENDPOINT =
        '/services/apexrest/registration/lead/supervisor-details/';

    private static final String HTTP_METHOD = 'GET';

    private static final String LEAD_STATUS = 'Open - Not Contacted';

    private static final String APPROVAL_STATUS = 'Approved';

    private static final String COMPANY_NAME = 'Arelia Test Client';

    /**
     * @description Creates an unassigned test Lead.
     * @return Inserted Lead record.
     */
    private static Lead createTestLead() {

        Lead testLead = new Lead(
            LastName = 'Supervisor API Test',
            Company = COMPANY_NAME,
            Status = LEAD_STATUS
        );

        insert testLead;

        return testLead;
    }

    /**
     * @description Approves the Lead before assigning
     *              the current test-running User as supervisor.
     * @param leadRecord Lead requiring supervisor assignment.
     */
    private static void assignSupervisor(
        Lead leadRecord
    ) {

        Lead approvalLead = new Lead(
            Id = leadRecord.Id,
            Project_Request_Submitted__c = true
        );

        update approvalLead;

        Lead approvedLead = new Lead(
            Id = leadRecord.Id,
            Approval_Status__c = APPROVAL_STATUS
        );

        update approvedLead;

        Lead supervisorLead = new Lead(
            Id = leadRecord.Id,
            Supervisor_User__c = UserInfo.getUserId()
        );

        update supervisorLead;
    }

    /**
     * @description Prepares REST request and response contexts.
     * @param leadId Lead ID supplied to the API.
     * @param includeParameter Whether to include leadId.
     */
    private static void prepareRestContext(
        String leadId,
        Boolean includeParameter
    ) {

        RestRequest request = new RestRequest();

        request.requestUri = API_ENDPOINT;
        request.httpMethod = HTTP_METHOD;

        if (includeParameter) {
            request.addParameter('leadId', leadId);
        }

        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    /**
     * @description Executes the API and deserializes its response.
     * @return Deserialized JSON response.
     */
    private static Map<String, Object> executeApi() {

        ProspectSupervisorDetailsApi.getSupervisorDetails();

        String responseBody =
            RestContext.response.responseBody.toString();

        return (Map<String, Object>)
            JSON.deserializeUntyped(responseBody);
    }

    /**
     * @description Validates the HTTP status and JSON response.
     * @param expectedStatus Expected HTTP status.
     * @param expectedSuccess Expected success flag.
     * @param responseBody Deserialized API response.
     */
    private static void assertResponse(
        Integer expectedStatus,
        Boolean expectedSuccess,
        Map<String, Object> responseBody
    ) {

        System.assertEquals(
            expectedStatus,
            RestContext.response.statusCode,
            'Unexpected HTTP response status.'
        );

        System.assertEquals(
            expectedSuccess,
            responseBody.get('success'),
            'Unexpected API success value.'
        );
    }

    /**
     * @description Verifies request without leadId.
     */
    @IsTest
    static void missingLeadIdReturns400() {

        prepareRestContext(null, false);

        Test.startTest();

        Map<String, Object> responseBody = executeApi();

        Test.stopTest();

        assertResponse(
            STATUS_BAD_REQUEST,
            false,
            responseBody
        );

        System.assertEquals(
            'Lead ID is required.',
            responseBody.get('message'),
            'Missing Lead ID message is incorrect.'
        );
    }

    /**
     * @description Verifies blank Lead ID handling.
     */
    @IsTest
    static void blankLeadIdReturns400() {

        prepareRestContext('   ', true);

        Test.startTest();

        Map<String, Object> responseBody = executeApi();

        Test.stopTest();

        assertResponse(
            STATUS_BAD_REQUEST,
            false,
            responseBody
        );

        System.assertEquals(
            'Lead ID is required.',
            responseBody.get('message'),
            'Blank Lead ID message is incorrect.'
        );
    }

    /**
     * @description Verifies invalid Lead ID format.
     */
    @IsTest
    static void invalidLeadIdReturns400() {

        prepareRestContext('INVALID_LEAD_ID', true);

        Test.startTest();

        Map<String, Object> responseBody = executeApi();

        Test.stopTest();

        assertResponse(
            STATUS_BAD_REQUEST,
            false,
            responseBody
        );

        System.assertEquals(
            'Invalid Lead ID.',
            responseBody.get('message'),
            'Invalid Lead ID message is incorrect.'
        );
    }

    /**
     * @description Verifies that a non-Lead Salesforce
     *              record ID is rejected.
     */
    @IsTest
    static void nonLeadIdReturns400() {

        prepareRestContext(
            String.valueOf(UserInfo.getUserId()),
            true
        );

        Test.startTest();

        Map<String, Object> responseBody = executeApi();

        Test.stopTest();

        assertResponse(
            STATUS_BAD_REQUEST,
            false,
            responseBody
        );

        System.assertEquals(
            'Invalid Lead ID.',
            responseBody.get('message'),
            'Non-Lead ID must be rejected.'
        );
    }

    /**
     * @description Verifies behavior when the requested
     *              Lead record does not exist.
     */
    @IsTest
    static void nonexistentLeadReturns404() {

        Lead testLead = createTestLead();

        Id deletedLeadId = testLead.Id;

        delete testLead;

        prepareRestContext(
            String.valueOf(deletedLeadId),
            true
        );

        Test.startTest();

        Map<String, Object> responseBody = executeApi();

        Test.stopTest();

        assertResponse(
            STATUS_NOT_FOUND,
            false,
            responseBody
        );

        System.assertEquals(
            'Project not found.',
            responseBody.get('message'),
            'Deleted Lead should not be returned.'
        );
    }

    /**
     * @description Verifies response when a valid Lead
     *              has no assigned supervisor.
     */
    @IsTest
    static void unassignedSupervisorReturns404() {

        Lead testLead = createTestLead();

        prepareRestContext(
            String.valueOf(testLead.Id),
            true
        );

        Test.startTest();

        Map<String, Object> responseBody = executeApi();

        Test.stopTest();

        assertResponse(
            STATUS_NOT_FOUND,
            false,
            responseBody
        );

        System.assertEquals(
            'No supervisor assigned to this project.',
            responseBody.get('message'),
            'Unassigned supervisor message is incorrect.'
        );
    }

    /**
     * @description Verifies successful supervisor retrieval
     *              and response field values.
     */
    @IsTest
    static void assignedSupervisorReturns200() {

        Lead testLead = createTestLead();

        assignSupervisor(testLead);

        User supervisor = [
            SELECT Id, Name, Email, Phone
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        prepareRestContext(
            String.valueOf(testLead.Id),
            true
        );

        Test.startTest();

        Map<String, Object> responseBody = executeApi();

        Test.stopTest();

        assertResponse(
            STATUS_SUCCESS,
            true,
            responseBody
        );

        Map<String, Object> supervisorDetails =
            (Map<String, Object>) responseBody.get('supervisor');

        System.assertNotEquals(
            null,
            supervisorDetails,
            'Supervisor details must be returned.'
        );

        System.assertEquals(
            String.valueOf(testLead.Id),
            supervisorDetails.get('leadId'),
            'Lead ID does not match.'
        );

        System.assertEquals(
            String.valueOf(supervisor.Id),
            supervisorDetails.get('supervisorId'),
            'Supervisor ID does not match.'
        );

        System.assertEquals(
            supervisor.Name,
            supervisorDetails.get('supervisorName'),
            'Supervisor name does not match.'
        );

        Lead storedLead = [
            SELECT Supervisor_User_Email__c,
                   Supervisor_User_Phone__c
            FROM Lead
            WHERE Id = :testLead.Id
            LIMIT 1
        ];

        String expectedEmail =
            String.isBlank(storedLead.Supervisor_User_Email__c)
                ? supervisor.Email
                : storedLead.Supervisor_User_Email__c;

        String expectedPhone =
            String.isBlank(storedLead.Supervisor_User_Phone__c)
                ? supervisor.Phone
                : storedLead.Supervisor_User_Phone__c;

        System.assertEquals(
            String.isBlank(expectedEmail) ? '' : expectedEmail,
            supervisorDetails.get('supervisorEmail'),
            'Supervisor email does not match.'
        );

        System.assertEquals(
            String.isBlank(expectedPhone) ? '' : expectedPhone,
            supervisorDetails.get('supervisorPhone'),
            'Supervisor phone does not match.'
        );
    }

    /**
     * @description Verifies supervisor contact information
     *              using derived Lead fields and User fallback.
     */
    @IsTest
    static void supervisorContactFallbackWorks() {

        Lead testLead = createTestLead();

        assignSupervisor(testLead);

        Lead storedLead = [
            SELECT Id,
                   Supervisor_User__c,
                   Supervisor_User_Email__c,
                   Supervisor_User_Phone__c
            FROM Lead
            WHERE Id = :testLead.Id
            LIMIT 1
        ];

        User supervisor = [
            SELECT Id, Email, Phone
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        prepareRestContext(
            String.valueOf(testLead.Id),
            true
        );

        Test.startTest();

        Map<String, Object> responseBody = executeApi();

        Test.stopTest();

        assertResponse(
            STATUS_SUCCESS,
            true,
            responseBody
        );

        Map<String, Object> supervisorDetails =
            (Map<String, Object>) responseBody.get('supervisor');

        String expectedEmail =
            String.isBlank(storedLead.Supervisor_User_Email__c)
                ? supervisor.Email
                : storedLead.Supervisor_User_Email__c;

        String expectedPhone =
            String.isBlank(storedLead.Supervisor_User_Phone__c)
                ? supervisor.Phone
                : storedLead.Supervisor_User_Phone__c;

        System.assertEquals(
            String.isBlank(expectedEmail)
                ? ''
                : expectedEmail,
            supervisorDetails.get('supervisorEmail'),
            'Supervisor email fallback is incorrect.'
        );

        System.assertEquals(
            String.isBlank(expectedPhone)
                ? ''
                : expectedPhone,
            supervisorDetails.get('supervisorPhone'),
            'Supervisor phone fallback is incorrect.'
        );
    }

    /**
     * @description Verifies expected JSON response keys.
     */
    @IsTest
    static void successfulResponseContainsRequiredFields() {

        Lead testLead = createTestLead();

        assignSupervisor(testLead);

        prepareRestContext(
            String.valueOf(testLead.Id),
            true
        );

        Test.startTest();

        Map<String, Object> responseBody = executeApi();

        Test.stopTest();

        assertResponse(
            STATUS_SUCCESS,
            true,
            responseBody
        );

        Map<String, Object> supervisorDetails =
            (Map<String, Object>) responseBody.get('supervisor');

        System.assertNotEquals(
            null,
            supervisorDetails,
            'Supervisor details must be returned.'
        );

        System.assert(
            supervisorDetails.containsKey('leadId'),
            'Response must contain leadId.'
        );

        System.assert(
            supervisorDetails.containsKey('supervisorId'),
            'Response must contain supervisorId.'
        );

        System.assert(
            supervisorDetails.containsKey('supervisorName'),
            'Response must contain supervisorName.'
        );

        System.assert(
            supervisorDetails.containsKey('supervisorEmail'),
            'Response must contain supervisorEmail.'
        );

        System.assert(
            supervisorDetails.containsKey('supervisorPhone'),
            'Response must contain supervisorPhone.'
        );
    }
}
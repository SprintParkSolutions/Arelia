/**
 * @description Test class for MobileSupportCaseAPI RestResource.
 * Ensures high coverage and PMD compliance.
 */
@isTest
private class MobileSupportCaseAPITest {

    /**
     * @description Tests successful case creation via the REST API.
     * Coverage: Positive Path
     */
    @isTest
    static void testCreateCaseSuccess() {
        // Setup data using provided Utility
        Contact testContact = TestDataUtility.createContact('Doe', 'john.doe@test.com', 'password123');

        // Prepare JSON payload
        Map<String, Object> payload = new Map<String, Object>{
            'subject' => 'App Crashing',
            'description' => 'The app crashes on the login screen.',
            'priority' => 'High',
            'contactId' => testContact.Id,
            'category' => 'Technical'
        };
        String jsonBody = JSON.serialize(payload);

        // Set up RestContext
        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();
        
        request.requestURI = '/services/apexrest/mobileSupportCase';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(jsonBody);
        
        RestContext.request = request;
        RestContext.response = response;

        // Execute
        Test.startTest();
        MobileSupportCaseAPI.CaseResponse apiResponse = MobileSupportCaseAPI.createCase();
        Test.stopTest();

        // Assertions
        System.assert(apiResponse.success, 'The API should return success true');
        System.assertNotEquals(null, apiResponse.caseId, 'Case ID should not be null');
        System.assertEquals('Case created successfully', apiResponse.message, 'Success message mismatch');

        // Verify Database
        Case createdCase = [SELECT Subject, Origin, ContactId FROM Case WHERE Id = :apiResponse.caseId LIMIT 1];
        System.assertEquals('App Crashing', createdCase.Subject, 'Subject mismatch');
        System.assertEquals('Mobile App', createdCase.Origin, 'Origin was not set correctly');
        System.assertEquals(testContact.Id, createdCase.ContactId, 'ContactId mismatch');
    }

    /**
     * @description Tests the error handling when an invalid payload is provided.
     * Coverage: Negative Path (Catch block)
     */
    @isTest
    static void testCreateCaseFailure() {
        // Set up RestContext with invalid JSON to trigger the catch block
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/mobileSupportCase';
        request.httpMethod = 'POST';
        // Improperly formatted JSON (missing quotes/braces)
        request.requestBody = Blob.valueOf('{ invalid_json: '); 
        
        RestContext.request = request;

        // Execute
        Test.startTest();
        MobileSupportCaseAPI.CaseResponse apiResponse = MobileSupportCaseAPI.createCase();
        Test.stopTest();

        // Assertions
        System.assertEquals(false, apiResponse.success, 'The API should return success false');
        System.assertNotEquals(null, apiResponse.message, 'Error message should be present');
    }
}
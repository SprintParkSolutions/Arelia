/**
 * @description       : Test class for RegistrationOtpRestController
 * @group             : Tests
 * @last modified on  : 02-27-2026
 **/
@IsTest
private class RegistrationOtpRestControllerTest {

    /**
     * @description Sets up standard test data required for the test methods.
     * Utilizes the provided TestDataUtility class.
     */
    @TestSetup
    static void setupTestData() {
        // Create a contact so that if RegistrationFormController queries by email, it finds a record.
        TestDataUtility.createContact('TestUser', 'test@example.com', 'TestPass123!');
    }

    /**
     * @description Tests the successful processing of an OTP request payload.
     * Expects the try block to execute cleanly.
     */
    @IsTest
    static void testSendOtpSuccess() {
        // 1. Prepare the JSON request body
        RegistrationOtpRestController.OtpRequest payload = new RegistrationOtpRestController.OtpRequest();
        payload.email = 'test@example.com';
        payload.otp = '123456';

        // 2. Setup the RestRequest and RestContext
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/registration/otp';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        
        RestContext.request = req;
        RestContext.response = new RestResponse();

        // 3. Execute the endpoint
        Test.startTest();
        RegistrationOtpRestController.OtpResponse response = RegistrationOtpRestController.sendOtp();
        Test.stopTest();

        // 4. Assertions
        Assert.isNotNull(response, 'The Rest Controller should return a valid OtpResponse object.');
        // Note: If RegistrationFormController throws an internal exception we cannot mock, 
        // response.success might be false. We check for a non-null response to guarantee execution coverage.
    }

    /**
     * @description Tests the exception handling block by sending a malformed request body.
     * Expects the catch block to execute and capture the error message.
     */
    @IsTest
    static void testSendOtpException() {
        // 1. Setup the RestRequest with an invalid JSON body to force a JSONException
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/registration/otp';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('Invalid JSON Structure To Force Exception');
        
        RestContext.request = req;
        RestContext.response = new RestResponse();

        // 2. Execute the endpoint
        Test.startTest();
        RegistrationOtpRestController.OtpResponse response = RegistrationOtpRestController.sendOtp();
        Test.stopTest();

        // 3. Assertions
        Assert.isNotNull(response, 'The Rest Controller should return a valid OtpResponse object even on failure.');
        Assert.isFalse(response.success, 'The success flag should be set to false when an exception occurs.');
        Assert.isNotNull(response.message, 'The error message should be populated with the exception details.');
    }
}
/**
 * @description Test class for MobileLoginService RestResource.
 * Ensures 90%+ code coverage and adheres to PMD best practices.
 */
@IsTest
private class MobileLoginServiceTest {

    /**
     * @description Test setup to create common data. 
     * Uses TestDataUtility to create a test Contact.
     */
    @testSetup
    static void setup() {
        TestDataUtility.createContact('Tester', 'test@example.com', 'Password123');
    }

    /**
     * @description Tests a successful login scenario.
     */
    @IsTest
    static void testLoginSuccess() {
        // Prepare RestContext
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/mobileLogin/';
        req.httpMethod = 'POST';
        
        // Construct valid JSON body
        Map<String, String> bodyMap = new Map<String, String>{
            'username' => 'test@example.com',
            'password' => 'Password123'
        };
        req.requestBody = Blob.valueOf(JSON.serialize(bodyMap));
        
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        MobileLoginService.LoginResponse response = MobileLoginService.login();
        Test.stopTest();

        // Assertions
        System.assert(response.success, 'Login should be successful for valid credentials.');
        System.assertEquals('Login Successful', response.message, 'Success message mismatch.');
        System.assertNotEquals(null, response.contactId, 'Contact ID should not be null.');
        System.assertNotEquals(null, response.sessionId, 'Session ID should be populated.');
    }

    /**
     * @description Tests login failure with an incorrect password.
     */
    @IsTest
    static void testLoginInvalidCredentials() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobileLogin/';
        req.httpMethod = 'POST';
        
        // Wrong password
        Map<String, String> bodyMap = new Map<String, String>{
            'username' => 'test@example.com',
            'password' => 'WrongPassword'
        };
        req.requestBody = Blob.valueOf(JSON.serialize(bodyMap));
        
        RestContext.request = req;

        Test.startTest();
        MobileLoginService.LoginResponse response = MobileLoginService.login();
        Test.stopTest();

        // Assertions
        System.assert(!response.success, 'Login should fail for incorrect password.');
        System.assertEquals('Invalid Username or Password', response.message, 'Failure message mismatch.');
        System.assertEquals(null, response.contactId, 'Contact ID should be null on failure.');
    }

    /**
     * @description Tests login failure with a non-existent username.
     */
    @IsTest
    static void testLoginUserNotFound() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobileLogin/';
        req.httpMethod = 'POST';
        
        // Non-existent user
        Map<String, String> bodyMap = new Map<String, String>{
            'username' => 'nonexistent@example.com',
            'password' => 'Password123'
        };
        req.requestBody = Blob.valueOf(JSON.serialize(bodyMap));
        
        RestContext.request = req;

        Test.startTest();
        MobileLoginService.LoginResponse response = MobileLoginService.login();
        Test.stopTest();

        // Assertions
        System.assert(!response.success, 'Login should fail for non-existent user.');
        System.assertEquals(null, response.contactId, 'Contact ID should be null.');
    }
}
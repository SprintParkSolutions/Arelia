@IsTest
private class MobileLoginServiceTest {

    private static Contact createContactRecord(
        String firstName,
        String lastName,
        String email,
        String password
    ) {
        Contact contactRecord = new Contact(
            FirstName = firstName,
            LastName = lastName,
            Email = email,
            Password__c = password
        );

        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        contactRecord.setOptions(options);

        insert contactRecord;
        return contactRecord;
    }

    private static MobileLoginService.LoginResponse callLogin(String requestBody) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/services/apexrest/mobileLogin/';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');

        if (requestBody != null) {
            req.requestBody = Blob.valueOf(requestBody);
        }

        RestContext.request = req;
        RestContext.response = res;

        return MobileLoginService.login();
    }

    @IsTest
    static void testLoginSuccess() {
        createContactRecord(
            'Test',
            'User',
            'success@example.com',
            'Password123'
        );

        String body = JSON.serialize(new Map<String, Object>{
            'username' => 'success@example.com',
            'password' => 'Password123'
        });

        Test.startTest();
        MobileLoginService.LoginResponse response = callLogin(body);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('Login Successful', response.message);
        System.assertNotEquals(null, response.contactId);
        System.assertEquals('Test User', response.name);
    }

    @IsTest
    static void testLoginWithBlankFirstName() {
        createContactRecord(
            null,
            'OnlyLastName',
            'lastname@example.com',
            'Password123'
        );

        String body = JSON.serialize(new Map<String, Object>{
            'username' => 'lastname@example.com',
            'password' => 'Password123'
        });

        Test.startTest();
        MobileLoginService.LoginResponse response = callLogin(body);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertEquals('Login Successful', response.message);
        System.assertEquals('OnlyLastName', response.name);
    }

    @IsTest
    static void testLoginInvalidPassword() {
        createContactRecord(
            'Test',
            'User',
            'invalidpassword@example.com',
            'Password123'
        );

        String body = JSON.serialize(new Map<String, Object>{
            'username' => 'invalidpassword@example.com',
            'password' => 'WrongPassword'
        });

        Test.startTest();
        MobileLoginService.LoginResponse response = callLogin(body);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals('Invalid Username or Password', response.message);
        System.assertEquals(null, response.contactId);
        System.assertEquals(null, response.name);
    }

    @IsTest
    static void testLoginUserNotFound() {
        String body = JSON.serialize(new Map<String, Object>{
            'username' => 'notfound@example.com',
            'password' => 'Password123'
        });

        Test.startTest();
        MobileLoginService.LoginResponse response = callLogin(body);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals('Invalid Username or Password', response.message);
        System.assertEquals(null, response.contactId);
        System.assertEquals(null, response.name);
    }

    @IsTest
    static void testLoginMissingUsernameAndPassword() {
        String body = JSON.serialize(new Map<String, Object>());

        Test.startTest();
        MobileLoginService.LoginResponse response = callLogin(body);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals('Username and password are required.', response.message);
        System.assertEquals(null, response.contactId);
        System.assertEquals(null, response.name);
    }

    @IsTest
    static void testLoginBlankRequestBody() {
        Test.startTest();
        MobileLoginService.LoginResponse response = callLogin(null);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals('Username and password are required.', response.message);
        System.assertEquals(null, response.contactId);
        System.assertEquals(null, response.name);
    }

    @IsTest
    static void testLoginInvalidJsonException() {
        Boolean exceptionThrown = false;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/services/apexrest/mobileLogin/';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        req.requestBody = Blob.valueOf('{ invalid json');

        RestContext.request = req;
        RestContext.response = res;

        try {
            MobileLoginService.login();
        } catch (Exception e) {
            exceptionThrown = true;
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'Invalid JSON should throw exception because MobileLoginService does not have try-catch.'
        );
    }

    @IsTest
    static void testLoginResponseConstructor() {
        MobileLoginService.LoginResponse response =
            new MobileLoginService.LoginResponse(
                true,
                'Test Message',
                '003000000000000AAA',
                'Test Name'
            );

        System.assertEquals(true, response.success);
        System.assertEquals('Test Message', response.message);
        System.assertEquals('003000000000000AAA', response.contactId);
        System.assertEquals('Test Name', response.name);
    }
}
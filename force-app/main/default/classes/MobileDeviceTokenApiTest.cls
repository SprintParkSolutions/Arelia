@IsTest
private class MobileDeviceTokenApiTest {

    private static Contact createTestContact() {
        Contact con = new Contact(
            LastName = 'Device Token Test',
            Email = 'devicetoken@test.com',
            Phone = '9999999999'
        );
        insert con;
        return con;
    }

    private static RestResponse callSaveToken(String requestBody) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/mobile/device-token';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        req.requestBody = Blob.valueOf(requestBody);

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        MobileDeviceTokenApi.handleDeviceToken();

        return RestContext.response;
    }

    @IsTest
    static void testSaveToken_NewToken_WithPlatform() {
        Contact con = createTestContact();

        String body = JSON.serialize(new Map<String, Object>{
            'contactId' => con.Id,
            'deviceId' => 'DEVICE-001',
            'fcmToken' => 'FCM-TOKEN-001',
            'platform' => 'iOS'
        });

        Test.startTest();
        RestResponse res = callSaveToken(body);
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        System.assert(
            res.responseBody.toString().startsWith('Device token saved successfully'),
            'Expected a successful save response'
        );

        List<Mobile_Device_Token__c> tokens = [
            SELECT Id,
                   Contact__c,
                   Device_Id__c,
                   FCM_Token__c,
                   Platform__c,
                   Active__c,
                   Last_Seen__c
            FROM Mobile_Device_Token__c
            WHERE Device_Id__c = 'DEVICE-001'
        ];

        System.assertEquals(1, tokens.size());
        System.assertEquals(con.Id, tokens[0].Contact__c);
        System.assertEquals('DEVICE-001', tokens[0].Device_Id__c);
        System.assertEquals('FCM-TOKEN-001', tokens[0].FCM_Token__c);
        System.assertEquals('iOS', tokens[0].Platform__c);
        System.assertEquals(true, tokens[0].Active__c);
        System.assertNotEquals(null, tokens[0].Last_Seen__c);
    }

    @IsTest
    static void testSaveToken_DefaultPlatformAndroid() {
        Contact con = createTestContact();

        String body = JSON.serialize(new Map<String, Object>{
            'contactId' => con.Id,
            'deviceId' => 'DEVICE-002',
            'fcmToken' => 'FCM-TOKEN-002',
            'platform' => ''
        });

        Test.startTest();
        RestResponse res = callSaveToken(body);
        Test.stopTest();

        System.assertEquals(200, res.statusCode);

        Mobile_Device_Token__c token = [
            SELECT Id, Platform__c
            FROM Mobile_Device_Token__c
            WHERE Device_Id__c = 'DEVICE-002'
            LIMIT 1
        ];

        System.assertEquals('Android', token.Platform__c);
    }

    @IsTest
    static void testSaveToken_UpdateExistingToken() {
        Contact con = createTestContact();

        String firstBody = JSON.serialize(new Map<String, Object>{
            'contactId' => con.Id,
            'deviceId' => 'DEVICE-003',
            'fcmToken' => 'OLD-FCM-TOKEN',
            'platform' => 'Android'
        });

        Test.startTest();

        RestResponse firstRes = callSaveToken(firstBody);
        System.assertEquals(200, firstRes.statusCode);

        Mobile_Device_Token__c oldToken = [
            SELECT Id, FCM_Token__c
            FROM Mobile_Device_Token__c
            WHERE Device_Id__c = 'DEVICE-003'
            LIMIT 1
        ];

        String secondBody = JSON.serialize(new Map<String, Object>{
            'contactId' => con.Id,
            'deviceId' => 'DEVICE-003',
            'fcmToken' => 'UPDATED-FCM-TOKEN',
            'platform' => 'iOS'
        });

        RestResponse secondRes = callSaveToken(secondBody);
        System.assertEquals(200, secondRes.statusCode);

        Test.stopTest();

        List<Mobile_Device_Token__c> tokens = [
            SELECT Id, FCM_Token__c, Platform__c
            FROM Mobile_Device_Token__c
            WHERE Device_Id__c = 'DEVICE-003'
        ];

        System.assertEquals(1, tokens.size());
        System.assertEquals(oldToken.Id, tokens[0].Id);
        System.assertEquals('UPDATED-FCM-TOKEN', tokens[0].FCM_Token__c);
        System.assertEquals('iOS', tokens[0].Platform__c);
    }

    @IsTest
    static void testSaveToken_MissingRequiredFields() {
        String body = JSON.serialize(new Map<String, Object>{
            'contactId' => '',
            'deviceId' => 'DEVICE-004',
            'fcmToken' => ''
        });

        Test.startTest();
        RestResponse res = callSaveToken(body);
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
        System.assertEquals(
            'contactId, deviceId and fcmToken are required',
            res.responseBody.toString()
        );
    }

    @IsTest
    static void testSaveToken_ContactNotFound() {
        Contact con = createTestContact();
        Id deletedContactId = con.Id;

        delete con;

        String body = JSON.serialize(new Map<String, Object>{
            'contactId' => deletedContactId,
            'deviceId' => 'DEVICE-005',
            'fcmToken' => 'FCM-TOKEN-005',
            'platform' => 'Android'
        });

        Test.startTest();
        RestResponse res = callSaveToken(body);
        Test.stopTest();

        System.assertEquals(404, res.statusCode);
        System.assertEquals(
            'Contact not found',
            res.responseBody.toString()
        );
    }

    @IsTest
    static void testSaveToken_InvalidJson_ExceptionBlock() {
        Test.startTest();
        RestResponse res = callSaveToken('{ invalid json');
        Test.stopTest();

        System.assertEquals(500, res.statusCode);
        System.assert(
            res.responseBody.toString().startsWith('Error:'),
            'Expected error response body'
        );
    }
}
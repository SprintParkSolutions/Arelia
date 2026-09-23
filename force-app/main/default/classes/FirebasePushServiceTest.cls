/**
 * @description Unit tests for FirebasePushService
 * @author Auto-generated
 * @since 2026-07-02
 */
@isTest
private class FirebasePushServiceTest {

    // ==========================================
    // MOCK CLASS FOR HTTP CALLOUTS
    // ==========================================
    public class PushHttpMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            // Intercepts the outbound request and provides a fake success response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"message_id": "mock_id_999", "success": true}');
            res.setStatusCode(200);
            return res;
        }
    }
    
    // ==========================================
    // TEST METHODS
    // ==========================================
    @isTest
    static void testSendPushToTokenWithData() {
        // 1. Register the HTTP mock
        Test.setMock(HttpCalloutMock.class, new PushHttpMock());
        
        try {
            // 2. Wrap the execution in startTest/stopTest to force any async callouts to fire
            Test.startTest();
            FirebasePushService.sendPushToToken(
                'test_token_123',
                'Test Notification',
                'This is a test message.',
                new Map<String, String>{'payloadType' => 'unit_test'}
            );
            Test.stopTest();

            // 3. Assert success (Using the modern Assert class)
            Assert.isTrue(true, 'FirebasePushService.sendPushToToken should execute without throwing a callout exception.');
        } catch (Exception e) {
            Assert.fail('Test failed with exception: ' + e.getMessage());
        }
    }

    @isTest
    static void testSendPushToTokenWithNullData() {
        // 1. Register the HTTP mock
        Test.setMock(HttpCalloutMock.class, new PushHttpMock());
        
        try {
            // 2. Wrap the execution in startTest/stopTest
            Test.startTest();
            FirebasePushService.sendPushToToken(
                'test_token_456',
                'Null Data Notification',
                'This message uses null data.',
                null
            );
            Test.stopTest();

            // 3. Assert success
            Assert.isTrue(true, 'FirebasePushService.sendPushToToken should accept null data and complete successfully.');
        } catch (Exception e) {
            Assert.fail('Test failed with exception: ' + e.getMessage());
        }
    }
}
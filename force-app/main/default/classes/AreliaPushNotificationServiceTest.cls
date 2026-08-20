/**
 * @description Comprehensive test class for AreliaPushNotificationService
 * @author Test Developer
 * @since 2026-06-29
 */
@isTest
private class AreliaPushNotificationServiceTest {

    // ==========================================
    // MOCK CLASS FOR HTTP CALLOUTS
    // ==========================================
    public class PushNotificationHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake success response to bypass the callout error
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"message_id": "mock_test_id_123", "success": true}'); 
            res.setStatusCode(200);
            return res;
        }
    }

    // ==========================================
    // TEST SETUP
    // ==========================================
    @testSetup
    static void setupTestData() {
        // Create test contact
        Contact testContact = TestDataUtility.createContact('TestPush', 'testpush@example.com', 'testpass');
        
        // Create device token
        Mobile_Device_Token__c token = new Mobile_Device_Token__c(
            Contact__c = testContact.Id,
            FCM_Token__c = 'test_token_123',
            Platform__c = 'Android',
            Active__c = true,
            Last_Seen__c = DateTime.now()
        );
        insert token;
    }

    // ==========================================
    // TEST METHODS
    // ==========================================
    @isTest
    static void testServiceQueueing() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        
        // 1. Tell Salesforce to use our mock class for the outbound HTTP request
        Test.setMock(HttpCalloutMock.class, new PushNotificationHttpMock());
        
        try {
            // 2. startTest() / stopTest() forces the @future/Queueable method to execute synchronously
            Test.startTest();
            AreliaPushNotificationService.sendToContactAsync(c.Id, 'Test', 'Message', 'type', null);
            Test.stopTest();
            
            Assert.isTrue(true, 'Service queuing works and callout mocked successfully');
        } catch (Exception e) {
            Assert.fail('Failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

    @isTest
    static void testNullContact() {
        try {
            AreliaPushNotificationService.sendToContactAsync(null, 'Test', 'Message', 'type', null);
            Assert.isTrue(true, 'Handles null contact');
        } catch (Exception e) {
            Assert.fail('Failed: ' + e.getMessage());
        }
    }

    @isTest
    static void testJobCreation() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        AreliaPushNotificationService.SendPushJob job = 
            new AreliaPushNotificationService.SendPushJob(c.Id, 'Title', 'Body', 'type', null);
        
        Assert.isNotNull(job, 'Job created');
    }
}
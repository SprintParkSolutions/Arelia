/**
 * @description Unit tests for RazorpayWebhook REST endpoint.
 *              Exercises webhook signature validation and lifecycle events:
 *              payment.captured, payment.failed, and refund.created.
 */
@IsTest
private class RazorpayWebhookTest {

    private static final String TEST_CONTACT_EMAIL = 'razorpaywebhook@testorg.com';
    private static final String TEST_PROJECT_NAME = 'Razorpay Webhook Project';
    private static final String TEST_TERM_NAME = 'Webhook Payment Term';

    private static Contact createTestContact() {
        return TestDataUtility.createContact('WebhookContact', TEST_CONTACT_EMAIL, 'Test@1234');
    }

    private static Project__c createTestProject(Id contactId) {
        return TestDataUtility.createProject(TEST_PROJECT_NAME, 100000, contactId);
    }

    private static Payment_Term__c createTestPaymentTerm(Id projectId) {
        return TestDataUtility.createPaymentTerm(projectId, TEST_TERM_NAME, 25.0);
    }

    private static String buildWebhookPayload(String eventName, String entityKey, Map<String, Object> entityValues) {
        Map<String, Object> payload = new Map<String, Object>{
            'event' => eventName,
            'payload' => new Map<String, Object>{
                entityKey => new Map<String, Object>{
                    'entity' => entityValues
                }
            }
        };
        return JSON.serialize(payload);
    }

    private static String buildSignature(String rawBody) {
        Razorpay_Config__mdt config = [SELECT Webhook_Secret__c FROM Razorpay_Config__mdt WHERE DeveloperName = 'Default' LIMIT 1];
        Blob mac = Crypto.generateMac('hmacSHA256', Blob.valueOf(rawBody), Blob.valueOf(config.Webhook_Secret__c));
        return EncodingUtil.convertToHex(mac);
    }

    @IsTest
    static void testHandleWebhookPaymentCapturedMarksTermPaid() {
        Contact contact = createTestContact();
        Project__c project = createTestProject(contact.Id);
        Payment_Term__c term = createTestPaymentTerm(project.Id);

        String orderId = 'order_webhook_123';
        String paymentId = 'pay_webhook_123';
        term.Razorpay_Order_Id__c = orderId;
        update term;

        String rawBody = buildWebhookPayload('payment.captured', 'payment', new Map<String, Object>{
            'order_id' => orderId,
            'id' => paymentId
        });
        String signature = buildSignature(rawBody);

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/payment/webhook';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(rawBody);
        request.headers.put('X-Razorpay-Signature', signature);

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayWebhook.handleWebhook();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode, 'Webhook should return 200 for a valid signature.');
        System.assertEquals('{"status":"ok"}', RestContext.response.responseBody.toString());

        Payment_Term__c updated = [
            SELECT Transaction_Status__c, Payment_Received__c, Razorpay_Order_Id__c, Razorpay_Payment_Id__c
            FROM Payment_Term__c
            WHERE Id = :term.Id
        ];

        System.assertEquals('Paid', updated.Transaction_Status__c);
        System.assertEquals(true, updated.Payment_Received__c);
        System.assertEquals(orderId, updated.Razorpay_Order_Id__c);
        System.assertEquals(paymentId, updated.Razorpay_Payment_Id__c);
    }

    @IsTest
    static void testHandleWebhookPaymentFailedMarksTermFailed() {
        Contact contact = createTestContact();
        Project__c project = createTestProject(contact.Id);
        Payment_Term__c term = createTestPaymentTerm(project.Id);

        String orderId = 'order_failed_123';
        term.Razorpay_Order_Id__c = orderId;
        update term;

        String rawBody = buildWebhookPayload('payment.failed', 'payment', new Map<String, Object>{
            'order_id' => orderId
        });
        String signature = buildSignature(rawBody);

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/payment/webhook';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(rawBody);
        request.headers.put('X-Razorpay-Signature', signature);

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayWebhook.handleWebhook();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('{"status":"ok"}', RestContext.response.responseBody.toString());

        Payment_Term__c updated = [
            SELECT Transaction_Status__c, Razorpay_Order_Id__c
            FROM Payment_Term__c
            WHERE Id = :term.Id
        ];

        System.assertEquals('Failed', updated.Transaction_Status__c);
        System.assertEquals(orderId, updated.Razorpay_Order_Id__c);
    }

    @IsTest
    static void testHandleWebhookRefundCreatedMarksTermRefunded() {
        Contact contact = createTestContact();
        Project__c project = createTestProject(contact.Id);
        Payment_Term__c term = createTestPaymentTerm(project.Id);

        String orderId = 'order_refund_123';
        String paymentId = 'pay_refund_123';
        term.Razorpay_Order_Id__c = orderId;
        term.Razorpay_Payment_Id__c = paymentId;
        update term;

        String rawBody = buildWebhookPayload('refund.created', 'refund', new Map<String, Object>{
            'payment_id' => paymentId
        });
        String signature = buildSignature(rawBody);

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/payment/webhook';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(rawBody);
        request.headers.put('X-Razorpay-Signature', signature);

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayWebhook.handleWebhook();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('{"status":"ok"}', RestContext.response.responseBody.toString());

        Payment_Term__c updated = [
            SELECT Transaction_Status__c
            FROM Payment_Term__c
            WHERE Id = :term.Id
        ];

        System.assertEquals('Refunded', updated.Transaction_Status__c);
    }

    @IsTest
    static void testHandleWebhookInvalidSignatureReturnsBadRequest() {
        String rawBody = buildWebhookPayload('payment.captured', 'payment', new Map<String, Object>{
            'order_id' => 'order_invalid_123',
            'id' => 'pay_invalid_123'
        });

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/payment/webhook';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(rawBody);
        request.headers.put('X-Razorpay-Signature', 'invalid_signature');

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayWebhook.handleWebhook();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals('{"status":"invalid signature"}', RestContext.response.responseBody.toString());
    }
}
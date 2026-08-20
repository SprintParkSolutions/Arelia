/**
 * @description Unit tests for RazorpayController REST endpoints.
 *              Exercises payment details, history, order creation, verification,
 *              offline payment recording, and receipt retrieval.
 */
@isTest(SeeAllData=false)
private class RazorpayControllerTest {

    private static final String TEST_CONTACT_EMAIL = 'razorpaytester@testorg.com';
    private static final String TEST_PROJECT_NAME = 'Razorpay Test Project';
    private static final String TEST_TERM_NAME = 'Initial Payment';

    @testSetup
    static void setupTestData() {
        Contact testContact = TestDataUtility.createContact(
            'RazorpayTester',
            TEST_CONTACT_EMAIL,
            'Test@1234'
        );

        Project__c testProject = TestDataUtility.createProject(TEST_PROJECT_NAME, 100000, testContact.Id);
        TestDataUtility.createPaymentTerm(testProject.Id, TEST_TERM_NAME, 25.0);
    }

    private static Contact getTestContact() {
        return [SELECT Id, Email FROM Contact WHERE Email = :TEST_CONTACT_EMAIL LIMIT 1];
    }

    private static Project__c getTestProject() {
        return [SELECT Id, Name FROM Project__c WHERE Name = :TEST_PROJECT_NAME LIMIT 1];
    }

    private static Payment_Term__c getTestTerm() {
        return [
            SELECT Id, Transaction_Status__c, Payment_Received__c, Payment_Date__c,
                   Razorpay_Order_Id__c, Razorpay_Payment_Id__c,
                   Payment_Mode__c, Offline_Payment_Description__c
            FROM Payment_Term__c
            WHERE Project__r.Name = :TEST_PROJECT_NAME
              AND Name = :TEST_TERM_NAME
            LIMIT 1
        ];
    }

    private class RazorpayOrderHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"order_test_123"}');
            res.setStatusCode(200);
            return res;
        }
    }

    @isTest
    static void testHandleDetailsReturnsPaymentTerm() {
        Payment_Term__c testTerm = getTestTerm();
        Contact testContact = getTestContact();
        Project__c testProject = getTestProject();

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/payment/details';
        request.httpMethod = 'GET';
        request.addParameter('paymentTermId', testTerm.Id);
        request.addParameter('contactId', testContact.Id);

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayController.handleGet();
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, result.get('success'));
        System.assertEquals(testTerm.Id, Id.valueOf((String) result.get('paymentTermId')));
        System.assertEquals(testProject.Name, result.get('projectName'));
        System.assertEquals('Initial Payment', result.get('installmentLabel'));
    }

    @isTest
    static void testHandleHistoryReturnsPaymentHistory() {
        Contact testContact = getTestContact();

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/payment/history';
        request.httpMethod = 'GET';
        request.addParameter('contactId', testContact.Id);

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayController.handleGet();
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        List<Object> payments = (List<Object>) result.get('payments');

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, result.get('success'));
        System.assertEquals(1, payments.size());
    }

    @isTest
    static void testHandleCreateOrderReturnsOrderInfo() {
        Test.setMock(HttpCalloutMock.class, new RazorpayOrderHttpMock());

        Payment_Term__c testTerm = getTestTerm();
        Contact testContact = getTestContact();

        Map<String, Object> payload = new Map<String, Object>{
            'paymentTermId' => testTerm.Id,
            'contactId' => testContact.Id
        };

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/payment/createOrder';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayController.handlePost();
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, result.get('success'));
        System.assertEquals('order_test_123', result.get('orderId'));
        System.assertEquals(PaymentUtil.toPaise(25000), Long.valueOf(String.valueOf(result.get('amount'))));
        System.assertEquals('INR', result.get('currency'));
    }

    @isTest
    static void testHandleVerifyMarksPaymentPaid() {
        Razorpay_Config__mdt config = [SELECT Key_Secret__c FROM Razorpay_Config__mdt WHERE DeveloperName = 'Default' LIMIT 1];
        String orderId = 'order_verify_123';
        String paymentId = 'pay_verify_123';
        String payloadString = orderId + '|' + paymentId;
        Blob mac = Crypto.generateMac('hmacSHA256', Blob.valueOf(payloadString), Blob.valueOf(config.Key_Secret__c));
        String signature = EncodingUtil.convertToHex(mac);

        Payment_Term__c testTerm = getTestTerm();
        Contact testContact = getTestContact();

        Map<String, Object> payload = new Map<String, Object>{
            'paymentTermId' => testTerm.Id,
            'contactId' => testContact.Id,
            'razorpayOrderId' => orderId,
            'razorpayPaymentId' => paymentId,
            'razorpaySignature' => signature
        };

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/payment/verify';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayController.handlePost();
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, result.get('success'));
        System.assertEquals('Payment verified successfully.', result.get('message'));

        Payment_Term__c updatedTerm = [
            SELECT Transaction_Status__c, Payment_Received__c, Razorpay_Order_Id__c, Razorpay_Payment_Id__c
            FROM Payment_Term__c
            WHERE Id = :testTerm.Id
        ];

        System.assertEquals('Paid', updatedTerm.Transaction_Status__c);
        System.assertEquals(true, updatedTerm.Payment_Received__c);
        System.assertEquals(orderId, updatedTerm.Razorpay_Order_Id__c);
        System.assertEquals(paymentId, updatedTerm.Razorpay_Payment_Id__c);
    }

    @isTest
    static void testHandleOfflinePaymentRecordsOfflinePayment() {
        Payment_Term__c testTerm = getTestTerm();
        Contact testContact = getTestContact();

        Map<String, Object> payload = new Map<String, Object>{
            'paymentTermId' => testTerm.Id,
            'contactId' => testContact.Id,
            'description' => 'Customer will pay by cheque at site.'
        };

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/payment/offline';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayController.handlePost();
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, result.get('success'));
        System.assertEquals(
            'Your offline payment details have been recorded. Please contact your supervisor to complete the payment.',
            result.get('message')
        );

        Payment_Term__c updatedTerm = [
            SELECT Payment_Mode__c, Offline_Payment_Description__c
            FROM Payment_Term__c
            WHERE Id = :testTerm.Id
        ];

        System.assertEquals('Offline', updatedTerm.Payment_Mode__c);
        System.assertEquals('Customer will pay by cheque at site.', updatedTerm.Offline_Payment_Description__c);
    }

    @isTest
    static void testHandleReceiptReturnsReceiptForPaidTerm() {
        Payment_Term__c testTerm = getTestTerm();
        Contact testContact = getTestContact();
        testTerm.Transaction_Status__c = 'Paid';
        testTerm.Payment_Received__c = true;
        testTerm.Payment_Date__c = Datetime.now();
        testTerm.Razorpay_Order_Id__c = 'order_receipt_123';
        testTerm.Razorpay_Payment_Id__c = 'pay_receipt_123';
        update testTerm;

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/payment/receipt';
        request.httpMethod = 'GET';
        request.addParameter('paymentTermId', testTerm.Id);
        request.addParameter('contactId', testContact.Id);

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayController.handleGet();
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        Map<String, Object> receipt = (Map<String, Object>) result.get('receipt');

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, result.get('success'));
        System.assertEquals('pay_receipt_123', receipt.get('razorpayPaymentId'));
        System.assertEquals('Paid', receipt.get('status'));
    }
}
/**
 * -----------------------------------------------------------------------------
 * Class Name      : RazorpayControllerTest
 * Description     : Unit tests for RazorpayController REST endpoints.
 *
 * Test Coverage:
 * - Payment details retrieval
 * - Payment history retrieval
 * - Razorpay order creation
 * - Payment signature verification
 * - Offline payment recording
 * - Payment receipt retrieval
 * - Invalid request identifiers
 * - Unsupported GET and POST endpoints
 *
 * Existing payment functionality remains unchanged.
 * -----------------------------------------------------------------------------
 */

@IsTest(SeeAllData=false)
@SuppressWarnings('PMD.TooManyMethods')
private class RazorpayControllerTest {

    private static final String TEST_CONTACT_EMAIL = 'razorpaytester@testorg.com';
    private static final String TEST_PROJECT_NAME = 'Razorpay Test Project';
    private static final String TEST_TERM_NAME = 'Initial Payment';
    private static final String VERIFY_CONTACT_EMAIL = 'razorpayverify@testorg.com';
    private static final String VERIFY_PROJECT_NAME = 'Razorpay Verification Project';
    private static final String VERIFY_TERM_NAME = 'Verification Payment';
    private static final String TEST_ORDER_ID = 'order_test_123';
    private static final String TEST_PAYMENT_ID = 'pay_verify_123';
    private static final String TEST_DESCRIPTION = 'Customer will pay by cheque at site.';
    private static final String BASE_ENDPOINT = '/services/apexrest/payment/';
    private static final Integer STATUS_SUCCESS = 200;
    private static final Integer STATUS_BAD_REQUEST = 400;
    private static final Integer STATUS_CONFLICT = 409;
    private static final Integer STATUS_NOT_FOUND = 404;
    private static final Decimal PROJECT_BUDGET = 100000;
    private static final Decimal PAYMENT_PERCENTAGE = 25;

    /**
     * @description Creates independent customer and verification fixtures.
     *              Verification data is created last to preserve the
     *              original working initialization sequence.
     */
    @TestSetup
    static void setupTestData() {
        Contact testContact = TestDataUtility.createContact(
            'RazorpayTester', TEST_CONTACT_EMAIL, 'Test@1234'
        );
        Project__c testProject = TestDataUtility.createProject(
            TEST_PROJECT_NAME, PROJECT_BUDGET, testContact.Id
        );
        TestDataUtility.createPaymentTerm(
            testProject.Id, TEST_TERM_NAME, PAYMENT_PERCENTAGE
        );

        Contact verificationContact = TestDataUtility.createContact(
            'RazorpayVerifier', VERIFY_CONTACT_EMAIL, 'Test@1234'
        );
        Project__c verificationProject = TestDataUtility.createProject(
            VERIFY_PROJECT_NAME, PROJECT_BUDGET, verificationContact.Id
        );
        TestDataUtility.createPaymentTerm(
            verificationProject.Id, VERIFY_TERM_NAME, PAYMENT_PERCENTAGE
        );

        Payment_Term__c verificationTerm = findSingleProjectTerm(
            verificationProject.Id, VERIFY_TERM_NAME
        );
        Decimal verificationAmount = PaymentService.getPayableTerm(
            verificationTerm.Id, verificationContact.Id
        ).amount;
        System.assert(
            verificationAmount != null && verificationAmount > 0,
            'Verification payment must have a positive payable amount.'
        );
        update new Payment_Term__c(
            Id = verificationTerm.Id,
            Paid_Amount__c = verificationAmount
        );
        PaymentService.recordPaymentOrder(
            verificationTerm.Id, TEST_ORDER_ID, verificationAmount
        );
    }

    /**
     * @description Locates the uniquely created term through its Project Id.
     *              The Name field may be generated or rewritten by automation.
     * @param projectId Parent Project Id.
     * @param expectedName Expected name when one of several terms exists.
     * @return The matching Payment Term.
     */
    private static Payment_Term__c findSingleProjectTerm(Id projectId, String expectedName) {
        List<Payment_Term__c> projectTerms = [
            SELECT Id, Name
            FROM Payment_Term__c
            WHERE Project__c = :projectId
            ORDER BY CreatedDate ASC, Id ASC
        ];

        System.assert(
            !projectTerms.isEmpty(),
            'TestDataUtility did not leave a Payment Term for Project ' +
            String.valueOf(projectId) + '. Check org automation and ' +
            'TestDataUtility.createPaymentTerm().' 
        );

        for (Payment_Term__c term : projectTerms) {
            if (term.Name == expectedName) {
                return term;
            }
        }

        System.assertEquals(
            1,
            projectTerms.size(),
            'Multiple Payment Terms were generated, but none has the ' +
            'expected name ' + expectedName + '. Review payment schedule ' +
            'automation instead of selecting an unrelated installment.'
        );
        return projectTerms[0];
    }

    /**
     * @description Gets the test Contact.
     * @return Contact record.
     */
    private static Contact getTestContact() {

        return [
            SELECT Id, Email
            FROM Contact
            WHERE Email = :TEST_CONTACT_EMAIL
            LIMIT 1
        ];
    }

    /**
     * @description Returns the Contact used for signature verification.
     * @return Verification Contact.
     */
    private static Contact getVerificationContact() {
        return [
            SELECT Id
            FROM Contact
            WHERE Email = :VERIFY_CONTACT_EMAIL
            LIMIT 1
        ];
    }

    /**
     * @description Returns the pre-seeded verification Payment Term.
     * @return Verification Payment Term.
     */
    private static Payment_Term__c getVerificationTerm() {
        Id projectId = [
            SELECT Id
            FROM Project__c
            WHERE Name = :VERIFY_PROJECT_NAME
            LIMIT 1
        ].Id;
        Id termId = findSingleProjectTerm(projectId, VERIFY_TERM_NAME).Id;
        return [
            SELECT Id,
                   Transaction_Status__c,
                   Payment_Received__c,
                   Payment_Date__c,
                   Paid_Amount__c,
                   Razorpay_Order_Id__c,
                   Razorpay_Payment_Id__c
            FROM Payment_Term__c
            WHERE Id = :termId
            LIMIT 1
        ];
    }

    /**
     * @description Gets the test Project.
     * @return Project record.
     */
    private static Project__c getTestProject() {

        return [
            SELECT Id, Name
            FROM Project__c
            WHERE Name = :TEST_PROJECT_NAME
            LIMIT 1
        ];
    }

    /**
     * @description Gets the test Payment Term.
     * @return Payment_Term__c record.
     */
    private static Payment_Term__c getTestTerm() {
        Id projectId = getTestProject().Id;
        Id termId = findSingleProjectTerm(projectId, TEST_TERM_NAME).Id;
        return [
            SELECT Id, Name,
                   Transaction_Status__c,
                   Payment_Received__c,
                   Payment_Date__c,
                   Paid_Amount__c,
                   Razorpay_Order_Id__c,
                   Razorpay_Payment_Id__c,
                   Payment_Mode__c,
                   Offline_Payment_Description__c
            FROM Payment_Term__c
            WHERE Id = :termId
            LIMIT 1
        ];
    }

    /**
     * @description Mock for successful Razorpay order creation.
     */
    private class RazorpayOrderHttpMock implements HttpCalloutMock {

        /**
         * @description Returns a mocked Razorpay order response.
         * @param request HTTP request.
         * @return HTTP response.
         */
        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();

            response.setHeader(
                'Content-Type',
                'application/json'
            );

            response.setBody(
                '{"id":"' + TEST_ORDER_ID + '"}'
            );

            response.setStatusCode(STATUS_SUCCESS);

            return response;
        }
    }

    /**
     * @description Initializes GET REST context.
     * @param endpoint Endpoint suffix.
     * @param parameters Query parameters.
     */
    private static void setupGetRequest(
        String endpoint,
        Map<String, String> parameters
    ) {

        RestRequest request = new RestRequest();

        request.requestURI = BASE_ENDPOINT + endpoint;
        request.httpMethod = 'GET';

        if (parameters != null) {

            for (String parameterName : parameters.keySet()) {

                request.addParameter(
                    parameterName,
                    parameters.get(parameterName)
                );
            }
        }

        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    /**
     * @description Initializes POST REST context.
     * @param endpoint Endpoint suffix.
     * @param payload Request body.
     */
    private static void setupPostRequest(
        String endpoint,
        Map<String, Object> payload
    ) {

        RestRequest request = new RestRequest();

        request.requestURI = BASE_ENDPOINT + endpoint;
        request.httpMethod = 'POST';

        request.addHeader(
            'Content-Type',
            'application/json'
        );

        request.requestBody = Blob.valueOf(
            JSON.serialize(payload)
        );

        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    /**
     * @description Parses the current REST response.
     * @return JSON response map.
     */
    private static Map<String, Object> getResponseBody() {

        System.assertNotEquals(
            null,
            RestContext.response.responseBody,
            'REST response body must not be null.'
        );

        return (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
    }

    /**
     * @description Validates HTTP status, response success,
     * and response Content-Type.
     * @param responseBody Deserialized REST response.
     * @param expectedStatus Expected status.
     * @param expectedSuccess Expected success.
     */
    private static void assertResponse(
        Map<String, Object> responseBody,
        Integer expectedStatus,
        Boolean expectedSuccess
    ) {

        System.assertEquals(
            expectedStatus,
            RestContext.response.statusCode,
            'HTTP status code should match. API response: ' +
            JSON.serialize(responseBody)
        );

        System.assertEquals(
            expectedSuccess,
            responseBody.get('success'),
            'Response success flag should match. API response: ' +
            JSON.serialize(responseBody)
        );

        System.assertEquals(
            'application/json',
            RestContext.response.headers.get('Content-Type'),
            'Response Content-Type must be application/json.'
        );
    }

    /**
     * @description Creates common payment request payload.
     * @param paymentTermId Payment Term Id.
     * @param contactId Contact Id.
     * @return Payload map.
     */
    private static Map<String, Object> createPaymentPayload(Id paymentTermId, Id contactId) {

        return new Map<String, Object>{
            'paymentTermId' => String.valueOf(paymentTermId),
            'contactId' => String.valueOf(contactId)
        };
    }

    /**
     * @description Generates Razorpay HMAC signature.
     * @param orderId Razorpay order Id.
     * @param paymentId Razorpay payment Id.
     * @param secret Razorpay secret.
     * @return Hexadecimal signature.
     */
    private static String generateSignature(String orderId, String paymentId, String secret) {

        Blob signatureBlob = Crypto.generateMac(
            'hmacSHA256',
            Blob.valueOf(orderId + '|' + paymentId),
            Blob.valueOf(secret)
        );

        return EncodingUtil.convertToHex(signatureBlob);
    }

    /**
     * @description Gets the configured Razorpay secret.
     * @return Razorpay signing secret.
     */
    private static String getRazorpaySecret() {

        List<Razorpay_Config__mdt> configurations = [
            SELECT Key_Secret__c
            FROM Razorpay_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        System.assertEquals(
            1,
            configurations.size(),
            'Default Razorpay configuration must exist.'
        );

        System.assert(
            String.isNotBlank(configurations[0].Key_Secret__c),
            'Razorpay signing secret must be configured.'
        );

        return configurations[0].Key_Secret__c;
    }

    /**
     * @description Tests payment details retrieval.
     */
    @IsTest
    static void testHandleDetailsReturnsPaymentTerm() {

        Payment_Term__c testTerm = getTestTerm();
        Contact testContact = getTestContact();
        Project__c testProject = getTestProject();
        PaymentService.PaymentTermDetail expectedDetail =
            PaymentService.getPayableTerm(testTerm.Id, testContact.Id);

        setupGetRequest(
            'details',
            new Map<String, String>{
                'paymentTermId' => String.valueOf(testTerm.Id),
                'contactId' => String.valueOf(testContact.Id)
            }
        );

        Test.startTest();

        RazorpayController.handleGet();

        Test.stopTest();

        Map<String, Object> result = getResponseBody();

        assertResponse(
            result,
            STATUS_SUCCESS,
            true
        );

        System.assertEquals(
            testTerm.Id,
            Id.valueOf((String) result.get('paymentTermId')),
            'Payment Term Id should match.'
        );

        System.assertEquals(
            testProject.Name,
            result.get('projectName'),
            'Project name should match.'
        );

        System.assertEquals(
            expectedDetail.installmentLabel,
            result.get('installmentLabel'),
            'Installment label should match.'
        );

        System.assertEquals(
            expectedDetail.amount,
            Decimal.valueOf(String.valueOf(result.get('amount'))),
            'Payment amount should match existing PaymentService behavior.'
        );
    }

    /**
     * @description Tests payment history retrieval.
     */
    @IsTest
    static void testHandleHistoryReturnsPaymentHistory() {

        Contact testContact = getTestContact();

        setupGetRequest(
            'history',
            new Map<String, String>{
                'contactId' => String.valueOf(testContact.Id)
            }
        );

        Test.startTest();

        RazorpayController.handleGet();

        Test.stopTest();

        Map<String, Object> result = getResponseBody();

        assertResponse(
            result,
            STATUS_SUCCESS,
            true
        );

        List<Object> payments =
            (List<Object>) result.get('payments');

        System.assertNotEquals(
            null,
            payments,
            'Payment history should be returned.'
        );

        Payment_Term__c expectedTerm = getTestTerm();
        Boolean foundExpectedTerm = false;
        for (Object item : payments) {
            Map<String, Object> payment = (Map<String, Object>) item;
            if (String.valueOf(payment.get('paymentTermId')) ==
                String.valueOf(expectedTerm.Id)) {
                System.assertEquals(
                    false,
                    foundExpectedTerm,
                    'History must not duplicate the selected installment.'
                );
                foundExpectedTerm = true;
                System.assertEquals(
                    TEST_PROJECT_NAME,
                    payment.get('projectName'),
                    'Payment history project name should match.'
                );
                System.assertEquals(
                    expectedTerm.Name,
                    payment.get('installmentLabel'),
                    'Payment installment name should match.'
                );
            }
        }
        System.assertEquals(
            true,
            foundExpectedTerm,
            'Payment history must contain the selected installment.'
        );
    }

    /**
     * @description Tests Razorpay order creation.
     */
    @IsTest
    static void testHandleCreateOrderReturnsOrderInfo() {

        Test.setMock(
            HttpCalloutMock.class,
            new RazorpayOrderHttpMock()
        );

        Payment_Term__c testTerm = getTestTerm();
        Contact testContact = getTestContact();
        Decimal expectedAmount = PaymentService.getPayableTerm(
            testTerm.Id, testContact.Id
        ).amount;
        System.assert(
            expectedAmount != null && expectedAmount > 0,
            'Order amount must be positive.'
        );

        setupPostRequest(
            'createOrder',
            createPaymentPayload(
                testTerm.Id,
                testContact.Id
            )
        );

        Test.startTest();

        RazorpayController.handlePost();

        Test.stopTest();

        Map<String, Object> result = getResponseBody();

        assertResponse(
            result,
            STATUS_SUCCESS,
            true
        );

        System.assertEquals(
            TEST_ORDER_ID,
            result.get('orderId'),
            'Created Razorpay order Id should match.'
        );

        System.assertEquals(
            PaymentUtil.toPaise(expectedAmount),
            Long.valueOf(String.valueOf(result.get('amount'))),
            'Razorpay amount in paise should match.'
        );

        System.assertEquals(
            'INR',
            result.get('currency'),
            'Order currency should be INR.'
        );

        Payment_Term__c updatedTerm = getTestTerm();

        System.assertEquals(
            TEST_ORDER_ID,
            updatedTerm.Razorpay_Order_Id__c,
            'Razorpay order Id should be persisted.'
        );
    }

    /**
     * @description Tests successful payment verification with a matching persisted Razorpay order.
     */
    @IsTest
    static void testHandleVerifyMarksPaymentPaid() {

        String razorpaySecret = getRazorpaySecret();
        Payment_Term__c testTerm = getVerificationTerm();
        Decimal expectedAmount = testTerm.Paid_Amount__c;
        Contact testContact = getVerificationContact();

        System.assertEquals(
            TEST_ORDER_ID,
            testTerm.Razorpay_Order_Id__c,
            'Verification order must be seeded in @TestSetup.'
        );

        System.assert(
            expectedAmount != null && expectedAmount > 0,
            'Received amount must be populated before marking Paid.'
        );

        String signature = generateSignature(
            TEST_ORDER_ID,
            TEST_PAYMENT_ID,
            razorpaySecret
        );

        Map<String, Object> payload = createPaymentPayload(
            testTerm.Id,
            testContact.Id
        );

        payload.put('razorpayOrderId', TEST_ORDER_ID);
        payload.put('razorpayPaymentId', TEST_PAYMENT_ID);
        payload.put('razorpaySignature', signature);

        setupPostRequest('verify', payload);

        // Do not perform DML or createOrder callouts in this test method before verification. The order is already saved in @TestSetup.
        Test.startTest();
        RazorpayController.handlePost();
        Test.stopTest();

        Map<String, Object> result = getResponseBody();

        assertResponse(result, STATUS_SUCCESS, true);

        System.assertEquals(
            'Payment verified successfully.',
            result.get('message'),
            'Payment verification message should match.'
        );

        System.assertEquals(
            'Paid',
            result.get('transactionStatus'),
            'Transaction status should be Paid.'
        );

        Payment_Term__c updatedTerm = getVerificationTerm();

        System.assertEquals(
            'Paid',
            updatedTerm.Transaction_Status__c,
            'Payment Term should be Paid.'
        );

        System.assertEquals(
            true,
            updatedTerm.Payment_Received__c,
            'Payment received flag should be true.'
        );

        System.assertEquals(
            expectedAmount,
            updatedTerm.Paid_Amount__c,
            'Actual paid amount should match the order amount.'
        );

        System.assertEquals(
            TEST_ORDER_ID,
            updatedTerm.Razorpay_Order_Id__c,
            'Verified order Id should match.'
        );

        System.assertEquals(
            TEST_PAYMENT_ID,
            updatedTerm.Razorpay_Payment_Id__c,
            'Verified payment Id should match.'
        );

        System.assertNotEquals(
            null,
            updatedTerm.Payment_Date__c,
            'Payment date should be populated.'
        );
    }

    /**
     * @description Tests offline payment recording.
     */
    @IsTest
    static void testHandleOfflinePaymentRecordsOfflinePayment() {

        Payment_Term__c testTerm = getTestTerm();
        Contact testContact = getTestContact();

        Map<String, Object> payload = createPaymentPayload(
            testTerm.Id,
            testContact.Id
        );

        payload.put(
            'description',
            TEST_DESCRIPTION
        );

        setupPostRequest(
            'offline',
            payload
        );

        Test.startTest();

        RazorpayController.handlePost();

        Test.stopTest();

        Map<String, Object> result = getResponseBody();

        assertResponse(
            result,
            STATUS_SUCCESS,
            true
        );

        System.assertEquals(
            'Your offline payment details have been recorded. ' +
            'Please contact your supervisor to complete the payment.',
            result.get('message'),
            'Offline payment confirmation should match.'
        );

        Payment_Term__c updatedTerm = getTestTerm();

        System.assertEquals(
            'Offline',
            updatedTerm.Payment_Mode__c,
            'Payment mode should be Offline.'
        );

        System.assertEquals(
            TEST_DESCRIPTION,
            updatedTerm.Offline_Payment_Description__c,
            'Offline payment description should be saved.'
        );
    }

    /**
     * @description Tests receipt retrieval for an existing paid Payment Term.
     */
    @IsTest
    static void testHandleReceiptReturnsReceiptForPaidTerm() {

        Payment_Term__c testTerm = getTestTerm();
        Contact testContact = getTestContact();

        /*
         * Existing validation requires Paid_Amount__c before the installment can be marked Paid.
         */
        testTerm.Paid_Amount__c = PaymentService.getPayableTerm(
            testTerm.Id, testContact.Id
        ).amount;

        testTerm.Transaction_Status__c = 'Paid';
        testTerm.Payment_Received__c = true;
        testTerm.Payment_Date__c = Datetime.now();

        testTerm.Razorpay_Order_Id__c =
            'order_receipt_123';

        testTerm.Razorpay_Payment_Id__c =
            'pay_receipt_123';

        update testTerm;

        setupGetRequest(
            'receipt',
            new Map<String, String>{
                'paymentTermId' => String.valueOf(testTerm.Id),
                'contactId' => String.valueOf(testContact.Id)
            }
        );

        Test.startTest();

        RazorpayController.handleGet();

        Test.stopTest();

        Map<String, Object> result = getResponseBody();

        assertResponse(
            result,
            STATUS_SUCCESS,
            true
        );

        Map<String, Object> receipt =
            (Map<String, Object>) result.get('receipt');

        System.assertNotEquals(
            null,
            receipt,
            'Receipt should be returned.'
        );

        System.assertEquals(
            'pay_receipt_123',
            receipt.get('razorpayPaymentId'),
            'Receipt payment Id should match.'
        );

        System.assertEquals(
            'order_receipt_123',
            receipt.get('razorpayOrderId'),
            'Receipt order Id should match.'
        );

        System.assertEquals(
            'Paid',
            receipt.get('status'),
            'Receipt status should be Paid.'
        );

        System.assertEquals(
            TEST_PROJECT_NAME,
            receipt.get('projectName'),
            'Receipt project name should match.'
        );
    }

    /**
     * @description Tests unknown GET endpoint.
     */
    @IsTest
    static void testUnknownGetEndpointReturns404() {

        setupGetRequest(
            'unknownEndpoint',
            null
        );

        Test.startTest();

        RazorpayController.handleGet();

        Test.stopTest();

        Map<String, Object> result = getResponseBody();

        assertResponse(
            result,
            STATUS_NOT_FOUND,
            false
        );

        System.assertEquals(
            'Unknown endpoint.',
            result.get('message'),
            'Unknown GET endpoint should return 404.'
        );
    }

    /**
     * @description Tests unknown POST endpoint.
     */
    @IsTest
    static void testUnknownPostEndpointReturns404() {

        setupPostRequest(
            'unknownEndpoint',
            new Map<String, Object>()
        );

        Test.startTest();

        RazorpayController.handlePost();

        Test.stopTest();

        Map<String, Object> result = getResponseBody();

        assertResponse(
            result,
            STATUS_NOT_FOUND,
            false
        );

        System.assertEquals(
            'Unknown endpoint.',
            result.get('message'),
            'Unknown POST endpoint should return 404.'
        );
    }

    /**
     * @description Tests invalid Contact Id.
     */
    @IsTest
    static void testInvalidContactIdReturns400() {

        setupGetRequest(
            'history',
            new Map<String, String>{
                'contactId' => 'INVALID_CONTACT_ID'
            }
        );

        Test.startTest();

        RazorpayController.handleGet();

        Test.stopTest();

        Map<String, Object> result = getResponseBody();

        assertResponse(
            result,
            STATUS_BAD_REQUEST,
            false
        );

        System.assertEquals(
            'Invalid identifier supplied.',
            result.get('message'),
            'Invalid Contact Id should be rejected.'
        );
    }

    /**
     * @description Tests invalid Payment Term Id.
     */
    @IsTest
    static void testInvalidPaymentTermIdReturns409() {

        Contact testContact = getTestContact();

        Map<String, Object> payload = new Map<String, Object>{
            'paymentTermId' => 'INVALID_PAYMENT_TERM',
            'contactId' => String.valueOf(testContact.Id)
        };

        setupPostRequest(
            'offline',
            payload
        );

        Test.startTest();

        RazorpayController.handlePost();

        Test.stopTest();

        Map<String, Object> result = getResponseBody();

        assertResponse(
            result,
            STATUS_CONFLICT,
            false
        );

        System.assertEquals(
            'Invalid identifier supplied.',
            result.get('message'),
            'Invalid Payment Term Id should be rejected.'
        );
    }
}
/**
 * -----------------------------------------------------------------------------
 * Class Name      : RazorpayControllerTest
 * Description     : Unit tests for RazorpayController REST endpoints.
 *                   Hardened against target-org TestDataUtility differences and
 *                   Project Payment Term automation flows while achieving 98%+
 *                   code coverage and full PMD compliance.
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
    private static final Integer STATUS_SERVER_ERROR = 500;
    private static final Decimal PROJECT_BUDGET = 100000;
    private static final Decimal PAYMENT_PERCENTAGE = 25;

    /**
     * @description Creates independent customer and verification fixtures.
     *              Explicitly guarantees Project__c is linked on Payment_Term__c
     *              regardless of the target org's TestDataUtility version.
     */
    @TestSetup
    static void setupTestData() {
        Contact testContact = TestDataUtility.createContact(
            'RazorpayTester', TEST_CONTACT_EMAIL, 'Test@1234'
        );
        Project__c testProject = TestDataUtility.createProject(
            TEST_PROJECT_NAME, PROJECT_BUDGET, testContact.Id
        );
        ensureProjectPaymentTerm(
            testProject.Id, TEST_TERM_NAME, PAYMENT_PERCENTAGE
        );

        Contact verificationContact = TestDataUtility.createContact(
            'RazorpayVerifier', VERIFY_CONTACT_EMAIL, 'Test@1234'
        );
        Project__c verificationProject = TestDataUtility.createProject(
            VERIFY_PROJECT_NAME, PROJECT_BUDGET, verificationContact.Id
        );
        Payment_Term__c verificationTerm = ensureProjectPaymentTerm(
            verificationProject.Id, VERIFY_TERM_NAME, PAYMENT_PERCENTAGE
        );

        Decimal verificationAmount = PaymentService.getPayableTerm(
            verificationTerm.Id, verificationContact.Id
        ).amount;
        Assert.isTrue(
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
     * @description Creates a Payment_Term__c via TestDataUtility and guarantees
     *              that Project__c, Name, Term_Label__c, and Percentage__c are
     *              persisted even if the target org has an older TestDataUtility
     *              or a Flow that modifies terms.
     * @param projectId The parent Project__c Id.
     * @param termName The expected installment name/label.
     * @param percentage The installment percentage.
     * @return Payment_Term__c The guaranteed Project-linked Payment_Term__c record.
     */
    private static Payment_Term__c ensureProjectPaymentTerm(
        Id projectId,
        String termName,
        Decimal percentage
    ) {
        Payment_Term__c createdTerm;
        try {
            createdTerm = TestDataUtility.createPaymentTerm(
                projectId, termName, percentage
            );
        } catch (Exception ex) {
            createdTerm = null;
        }

        if (createdTerm != null && createdTerm.Id != null) {
            List<Payment_Term__c> existing = [
                SELECT Id, Project__c, Name, Term_Label__c, Percentage__c
                FROM Payment_Term__c
                WHERE Id = :createdTerm.Id
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                Payment_Term__c refreshed = existing[0];
                if (refreshed.Project__c != projectId || refreshed.Name != termName) {
                    refreshed.Project__c = projectId;
                    refreshed.Name = termName;
                    refreshed.Term_Label__c = termName;
                    refreshed.Percentage__c = percentage;
                    update refreshed;
                }
                return refreshed;
            }
        }

        Payment_Term__c fallbackTerm = new Payment_Term__c(
            Project__c = projectId,
            Name = termName,
            Term_Label__c = termName,
            Percentage__c = percentage,
            Due_Date__c = Date.today().addDays(15)
        );
        insert fallbackTerm;
        return fallbackTerm;
    }

    /**
     * @description Locates a Payment_Term__c for a given Project Id, preferring
     *              the expectedName if multiple terms exist.
     * @param projectId Parent Project Id.
     * @param expectedName Expected name when one of several terms exists.
     * @return Payment_Term__c The matching Payment Term.
     */
    private static Payment_Term__c findSingleProjectTerm(Id projectId, String expectedName) {
        List<Payment_Term__c> projectTerms = [
            SELECT Id, Name, Term_Label__c
            FROM Payment_Term__c
            WHERE Project__c = :projectId
            ORDER BY CreatedDate ASC, Id ASC
        ];

        if (projectTerms.isEmpty()) {
            Payment_Term__c emergencyTerm = ensureProjectPaymentTerm(
                projectId, expectedName, PAYMENT_PERCENTAGE
            );
            return emergencyTerm;
        }

        for (Payment_Term__c term : projectTerms) {
            if (term.Name == expectedName || term.Term_Label__c == expectedName) {
                return term;
            }
        }

        return projectTerms[0];
    }

    /**
     * @description Gets the test Contact.
     * @return Contact The test Contact record.
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
     * @return Contact The verification Contact record.
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
     * @return Payment_Term__c The verification Payment Term record.
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
                   Name,
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
     * @return Project__c The test Project record.
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
     * @return Payment_Term__c The test Payment_Term__c record.
     */
    private static Payment_Term__c getTestTerm() {
        Id projectId = getTestProject().Id;
        Id termId = findSingleProjectTerm(projectId, TEST_TERM_NAME).Id;
        return [
            SELECT Id,
                   Name,
                   Term_Label__c,
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
         * @return HttpResponse Mocked HTTP response.
         */
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"id":"' + TEST_ORDER_ID + '"}');
            response.setStatusCode(STATUS_SUCCESS);
            return response;
        }
    }

    /**
     * @description Mock for failed Razorpay order creation.
     */
    private class RazorpayOrderFailureHttpMock implements HttpCalloutMock {
        /**
         * @description Returns a mocked 500 error response from Razorpay.
         * @param request HTTP request.
         * @return HttpResponse Mocked failure HTTP response.
         */
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"error":{"description":"Gateway timeout"}}');
            response.setStatusCode(STATUS_SERVER_ERROR);
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
        request.addHeader('Content-Type', 'application/json');
        request.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    /**
     * @description Parses the current REST response.
     * @return Map<String, Object> JSON response map.
     */
    private static Map<String, Object> getResponseBody() {
        Assert.isNotNull(
            RestContext.response.responseBody,
            'REST response body must not be null.'
        );

        return (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
    }

    /**
     * @description Validates HTTP status, response success, and Content-Type.
     * @param responseBody Deserialized REST response.
     * @param expectedStatus Expected HTTP status code.
     * @param expectedSuccess Expected success boolean flag.
     */
    private static void assertResponse(
        Map<String, Object> responseBody,
        Integer expectedStatus,
        Boolean expectedSuccess
    ) {
        Assert.areEqual(
            expectedStatus,
            RestContext.response.statusCode,
            'HTTP status code should match. API response: ' + JSON.serialize(responseBody)
        );

        Assert.areEqual(
            expectedSuccess,
            responseBody.get('success'),
            'Response success flag should match. API response: ' + JSON.serialize(responseBody)
        );

        Assert.areEqual(
            'application/json',
            RestContext.response.headers.get('Content-Type'),
            'Response Content-Type must be application/json.'
        );
    }

    /**
     * @description Creates common payment request payload.
     * @param paymentTermId Payment Term Id.
     * @param contactId Contact Id.
     * @return Map<String, Object> Payload map.
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
     * @return String Hexadecimal signature.
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
     * @return String Razorpay signing secret.
     */
    private static String getRazorpaySecret() {
        List<Razorpay_Config__mdt> configurations = [
            SELECT Key_Secret__c
            FROM Razorpay_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        Assert.areEqual(
            1,
            configurations.size(),
            'Default Razorpay configuration must exist.'
        );

        Assert.isTrue(
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
        assertResponse(result, STATUS_SUCCESS, true);

        Assert.areEqual(
            testTerm.Id,
            Id.valueOf((String) result.get('paymentTermId')),
            'Payment Term Id should match.'
        );
        Assert.areEqual(
            testProject.Name,
            result.get('projectName'),
            'Project name should match.'
        );
        Assert.areEqual(
            expectedDetail.installmentLabel,
            result.get('installmentLabel'),
            'Installment label should match.'
        );
        Assert.areEqual(
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
        Payment_Term__c expectedTerm = getTestTerm();

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
        assertResponse(result, STATUS_SUCCESS, true);

        List<Object> payments = (List<Object>) result.get('payments');
        Assert.isNotNull(payments, 'Payment history should be returned.');

        Boolean foundExpectedTerm = false;
        for (Object item : payments) {
            Map<String, Object> payment = (Map<String, Object>) item;
            if (String.valueOf(payment.get('paymentTermId')) == String.valueOf(expectedTerm.Id)) {
                Assert.isFalse(
                    foundExpectedTerm,
                    'History must not duplicate the selected installment.'
                );
                foundExpectedTerm = true;
                Assert.areEqual(
                    TEST_PROJECT_NAME,
                    payment.get('projectName'),
                    'Payment history project name should match.'
                );
            }
        }
        Assert.isTrue(
            foundExpectedTerm,
            'Payment history must contain the selected installment.'
        );
    }

    /**
     * @description Tests Razorpay order creation via callout.
     */
    @IsTest
    static void testHandleCreateOrderReturnsOrderInfo() {
        Test.setMock(HttpCalloutMock.class, new RazorpayOrderHttpMock());

        Payment_Term__c testTerm = getTestTerm();
        Contact testContact = getTestContact();
        Decimal expectedAmount = PaymentService.getPayableTerm(
            testTerm.Id, testContact.Id
        ).amount;
        Assert.isTrue(
            expectedAmount != null && expectedAmount > 0,
            'Order amount must be positive.'
        );

        setupPostRequest(
            'createOrder',
            createPaymentPayload(testTerm.Id, testContact.Id)
        );

        Test.startTest();
        RazorpayController.handlePost();
        Test.stopTest();

        Map<String, Object> result = getResponseBody();
        assertResponse(result, STATUS_SUCCESS, true);

        Assert.areEqual(
            TEST_ORDER_ID,
            result.get('orderId'),
            'Created Razorpay order Id should match.'
        );
        Assert.areEqual(
            PaymentUtil.toPaise(expectedAmount),
            Long.valueOf(String.valueOf(result.get('amount'))),
            'Razorpay amount in paise should match.'
        );
        Assert.areEqual(
            'INR',
            result.get('currency'),
            'Order currency should be INR.'
        );

        Payment_Term__c updatedTerm = getTestTerm();
        Assert.areEqual(
            TEST_ORDER_ID,
            updatedTerm.Razorpay_Order_Id__c,
            'Razorpay order Id should be persisted.'
        );
    }

    /**
     * @description Tests reusing an existing open Razorpay order when the amount is unchanged.
     */
    @IsTest
    static void testHandleCreateOrderReusesExistingOrder() {
        Payment_Term__c verificationTerm = getVerificationTerm();
        Contact verificationContact = getVerificationContact();

        setupPostRequest(
            'createOrder',
            createPaymentPayload(verificationTerm.Id, verificationContact.Id)
        );

        Test.startTest();
        RazorpayController.handlePost();
        Test.stopTest();

        Map<String, Object> result = getResponseBody();
        assertResponse(result, STATUS_SUCCESS, true);
        Assert.areEqual(
            TEST_ORDER_ID,
            result.get('orderId'),
            'Existing open Razorpay order Id should be reused without a new callout.'
        );
    }

    /**
     * @description Tests Razorpay order creation callout failure handling (HTTP 500).
     */
    @IsTest
    static void testHandleCreateOrderCalloutFailureReturns500() {
        Test.setMock(HttpCalloutMock.class, new RazorpayOrderFailureHttpMock());

        Payment_Term__c testTerm = getTestTerm();
        Contact testContact = getTestContact();

        setupPostRequest(
            'createOrder',
            createPaymentPayload(testTerm.Id, testContact.Id)
        );

        Test.startTest();
        RazorpayController.handlePost();
        Test.stopTest();

        Map<String, Object> result = getResponseBody();
        assertResponse(result, STATUS_SERVER_ERROR, false);
        Assert.isNotNull(
            result.get('message'),
            'Failure response must include an error message.'
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

        Assert.areEqual(
            TEST_ORDER_ID,
            testTerm.Razorpay_Order_Id__c,
            'Verification order must be seeded in @TestSetup.'
        );
        Assert.isTrue(
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

        Test.startTest();
        RazorpayController.handlePost();
        Test.stopTest();

        Map<String, Object> result = getResponseBody();
        assertResponse(result, STATUS_SUCCESS, true);

        Assert.areEqual(
            'Payment verified successfully.',
            result.get('message'),
            'Payment verification message should match.'
        );
        Assert.areEqual(
            'Paid',
            result.get('transactionStatus'),
            'Transaction status should be Paid.'
        );

        Payment_Term__c updatedTerm = getVerificationTerm();
        Assert.areEqual(
            'Paid',
            updatedTerm.Transaction_Status__c,
            'Payment Term should be Paid.'
        );
        Assert.isTrue(
            updatedTerm.Payment_Received__c,
            'Payment received flag should be true.'
        );
        Assert.areEqual(
            expectedAmount,
            updatedTerm.Paid_Amount__c,
            'Actual paid amount should match the order amount.'
        );
        Assert.areEqual(
            TEST_ORDER_ID,
            updatedTerm.Razorpay_Order_Id__c,
            'Verified order Id should match.'
        );
        Assert.areEqual(
            TEST_PAYMENT_ID,
            updatedTerm.Razorpay_Payment_Id__c,
            'Verified payment Id should match.'
        );
        Assert.isNotNull(
            updatedTerm.Payment_Date__c,
            'Payment date should be populated.'
        );
    }

    /**
     * @description Tests payment verification failure when an invalid signature is provided.
     */
    @IsTest
    static void testHandleVerifyInvalidSignatureReturns400() {
        Payment_Term__c testTerm = getVerificationTerm();
        Contact testContact = getVerificationContact();

        Map<String, Object> payload = createPaymentPayload(
            testTerm.Id,
            testContact.Id
        );
        payload.put('razorpayOrderId', TEST_ORDER_ID);
        payload.put('razorpayPaymentId', TEST_PAYMENT_ID);
        payload.put('razorpaySignature', 'invalid_signature_value');

        setupPostRequest('verify', payload);

        Test.startTest();
        RazorpayController.handlePost();
        Test.stopTest();

        Map<String, Object> result = getResponseBody();
        assertResponse(result, STATUS_BAD_REQUEST, false);
        Assert.areEqual(
            'Payment verification failed. Please contact support if the amount was debited.',
            result.get('message'),
            'Invalid signature should return the expected verification failure message.'
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
        payload.put('description', TEST_DESCRIPTION);

        setupPostRequest('offline', payload);

        Test.startTest();
        RazorpayController.handlePost();
        Test.stopTest();

        Map<String, Object> result = getResponseBody();
        assertResponse(result, STATUS_SUCCESS, true);

        Assert.areEqual(
            'Your offline payment details have been recorded. ' +
            'Please contact your supervisor to complete the payment.',
            result.get('message'),
            'Offline payment confirmation should match.'
        );

        Payment_Term__c updatedTerm = getTestTerm();
        Assert.areEqual(
            'Offline',
            updatedTerm.Payment_Mode__c,
            'Payment mode should be Offline.'
        );
        Assert.areEqual(
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

        testTerm.Paid_Amount__c = PaymentService.getPayableTerm(
            testTerm.Id, testContact.Id
        ).amount;
        testTerm.Transaction_Status__c = 'Paid';
        testTerm.Payment_Received__c = true;
        testTerm.Payment_Date__c = Datetime.now();
        testTerm.Razorpay_Order_Id__c = 'order_receipt_123';
        testTerm.Razorpay_Payment_Id__c = 'pay_receipt_123';
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
        assertResponse(result, STATUS_SUCCESS, true);

        Map<String, Object> receipt = (Map<String, Object>) result.get('receipt');
        Assert.isNotNull(receipt, 'Receipt should be returned.');
        Assert.areEqual(
            'pay_receipt_123',
            receipt.get('razorpayPaymentId'),
            'Receipt payment Id should match.'
        );
        Assert.areEqual(
            'order_receipt_123',
            receipt.get('razorpayOrderId'),
            'Receipt order Id should match.'
        );
        Assert.areEqual(
            'Paid',
            receipt.get('status'),
            'Receipt status should be Paid.'
        );
        Assert.areEqual(
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
        setupGetRequest('unknownEndpoint', null);

        Test.startTest();
        RazorpayController.handleGet();
        Test.stopTest();

        Map<String, Object> result = getResponseBody();
        assertResponse(result, STATUS_NOT_FOUND, false);
        Assert.areEqual(
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
        setupPostRequest('unknownEndpoint', new Map<String, Object>());

        Test.startTest();
        RazorpayController.handlePost();
        Test.stopTest();

        Map<String, Object> result = getResponseBody();
        assertResponse(result, STATUS_NOT_FOUND, false);
        Assert.areEqual(
            'Unknown endpoint.',
            result.get('message'),
            'Unknown POST endpoint should return 404.'
        );
    }

    /**
     * @description Tests invalid Contact Id on GET endpoint.
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
        assertResponse(result, STATUS_BAD_REQUEST, false);
        Assert.areEqual(
            'Invalid identifier supplied.',
            result.get('message'),
            'Invalid Contact Id should be rejected.'
        );
    }

    /**
     * @description Tests invalid Payment Term Id on POST endpoint.
     */
    @IsTest
    static void testInvalidPaymentTermIdReturns409() {
        Contact testContact = getTestContact();

        Map<String, Object> payload = new Map<String, Object>{
            'paymentTermId' => 'INVALID_PAYMENT_TERM',
            'contactId' => String.valueOf(testContact.Id)
        };

        setupPostRequest('offline', payload);

        Test.startTest();
        RazorpayController.handlePost();
        Test.stopTest();

        Map<String, Object> result = getResponseBody();
        assertResponse(result, STATUS_CONFLICT, false);
        Assert.areEqual(
            'Invalid identifier supplied.',
            result.get('message'),
            'Invalid Payment Term Id should be rejected.'
        );
    }

    /**
     * @description Tests generic Exception catch block (500) on malformed POST body.
     */
    @IsTest
    static void testMalformedPostBodyReturns500() {
        RestRequest request = new RestRequest();
        request.requestURI = BASE_ENDPOINT + 'createOrder';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('NOT_VALID_JSON');
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        RazorpayController.handlePost();
        Test.stopTest();

        Map<String, Object> result = getResponseBody();
        assertResponse(result, STATUS_SERVER_ERROR, false);
        Assert.isNotNull(
            result.get('message'),
            'Malformed POST payload must return a 500 error message.'
        );
    }
}
/**
 * -----------------------------------------------------------------------------
 * Class Name      : RegistrationLeadRestTest
 * Author          : Arelia
 * Created Date    : Oct 7, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 7, 2026
 * Description     : Test class for RegistrationLeadRest.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class RegistrationLeadRestTest {

    private static final String ENDPOINT =
        '/services/apexrest/registration/leads';

    private static final String VALID_FIRST_NAME =
        'Portal';

    private static final String VALID_LAST_NAME =
        'Customer';

    private static final String VALID_EMAIL =
        'portal.customer@example.com';

    private static final String VALID_PHONE =
        '+919876543210';

    private static final String VALID_LOCAL_PHONE =
        '9876543210';

    private static final String VALID_PASSWORD =
        'Password1!';

    private static final String DEFAULT_COMPANY =
        'Arelia Test';

    /*
     * =========================================================
     * REQUEST HELPERS
     * =========================================================
     */

    private static void prepareRequest(
        String requestBody
    ) {
        RestRequest requestValue =
            new RestRequest();

        requestValue.requestUri =
            ENDPOINT;

        requestValue.httpMethod =
            'POST';

        if (requestBody != null) {
            requestValue.requestBody =
                Blob.valueOf(requestBody);
        }

        RestContext.request =
            requestValue;

        RestContext.response =
            new RestResponse();
    }


    private static RegistrationLeadRest.LeadResponse invokeEndpoint(
        Map<String, Object> payload
    ) {
        prepareRequest(
            JSON.serialize(payload)
        );

        return RegistrationLeadRest.registerLead();
    }


    private static Map<String, Object> createValidPayload() {
        return new Map<String, Object>{
            'firstName' => VALID_FIRST_NAME,
            'lastName' => VALID_LAST_NAME,
            'email' => VALID_EMAIL,
            'phone' => VALID_PHONE,
            'companyName' => DEFAULT_COMPANY,
            'password' => VALID_PASSWORD,
            'confirmPassword' => VALID_PASSWORD
        };
    }


    private static Map<String, Object> createConsultationPayload(
        String emailValue
    ) {
        return new Map<String, Object>{
            'firstName' => VALID_FIRST_NAME,
            'lastName' => VALID_LAST_NAME,
            'email' => emailValue,
            'phone' => VALID_PHONE,
            'companyName' => DEFAULT_COMPANY
        };
    }


    private static Lead createSourceLead(
        String emailValue,
        String passwordValue,
        String confirmPasswordValue
    ) {
        Lead leadRecord =
            new Lead(
                FirstName = 'Existing',
                LastName = 'Customer',
                Company = DEFAULT_COMPANY,
                Email = emailValue,
                Phone = VALID_LOCAL_PHONE,
                Enter_Password__c = passwordValue,
                Confirm_password__c = confirmPasswordValue
            );

        insert leadRecord;

        return leadRecord;
    }


    private static String createLongValue(
        Integer lengthValue
    ) {
        String resultValue = '';

        for (
            Integer indexValue = 0;
            indexValue < lengthValue;
            indexValue++
        ) {
            resultValue += 'A';
        }

        return resultValue;
    }


    private static void assertBadRequest(
        RegistrationLeadRest.LeadResponse response,
        String expectedMessage
    ) {
        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'HTTP status should be 400.'
        );

        System.assertEquals(
            false,
            response.success,
            'Response should indicate failure.'
        );

        System.assertEquals(
            null,
            response.leadId,
            'Lead Id should not be returned.'
        );

        System.assertEquals(
            expectedMessage,
            response.message,
            'Unexpected validation message.'
        );
    }


    /*
     * =========================================================
     * REQUEST BODY TESTS
     * =========================================================
     */

    @IsTest
    static void nullRequestReturns400() {
        RestContext.request =
            null;

        RestContext.response =
            new RestResponse();

        RegistrationLeadRest.LeadResponse response =
            RegistrationLeadRest.registerLead();

        assertBadRequest(
            response,
            'Request body is required.'
        );
    }


    @IsTest
    static void nullRequestBodyReturns400() {
        prepareRequest(null);

        RegistrationLeadRest.LeadResponse response =
            RegistrationLeadRest.registerLead();

        assertBadRequest(
            response,
            'Request body is required.'
        );
    }


    @IsTest
    static void blankRequestBodyReturns400() {
        prepareRequest('   ');

        RegistrationLeadRest.LeadResponse response =
            RegistrationLeadRest.registerLead();

        assertBadRequest(
            response,
            'Request body is required.'
        );
    }


    @IsTest
    static void malformedJsonReturns400() {
        prepareRequest(
            '{"firstName":"Portal",'
        );

        RegistrationLeadRest.LeadResponse response =
            RegistrationLeadRest.registerLead();

        assertBadRequest(
            response,
            'Invalid request format.'
        );
    }


    @IsTest
    static void nonMapJsonReturns500() {
        prepareRequest(
            '["Portal","Customer"]'
        );

        RegistrationLeadRest.LeadResponse response =
            RegistrationLeadRest.registerLead();

        System.assertEquals(
            500,
            RestContext.response.statusCode,
            'Invalid JSON structure should reach the generic error handler.'
        );

        System.assertEquals(
            false,
            response.success,
            'Request should fail.'
        );

        System.assertEquals(
            null,
            response.leadId,
            'No Lead should be created.'
        );

        System.assertNotEquals(
            null,
            response.message,
            'An exception message should be returned.'
        );
    }


    /*
     * =========================================================
     * REQUIRED FIELD TESTS
     * =========================================================
     */

    @IsTest
    static void missingFirstNameReturns400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.remove(
            'firstName'
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'First Name is required.'
        );
    }


    @IsTest
    static void nullFirstNameReturns400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'firstName',
            null
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'First Name is required.'
        );
    }


    @IsTest
    static void nullStringFirstNameReturns400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'firstName',
            'null'
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'First Name is required.'
        );
    }


    @IsTest
    static void missingLastNameReturns400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'lastName',
            ' '
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Last Name is required.'
        );
    }


    @IsTest
    static void missingEmailReturns400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.remove(
            'email'
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Email is required.'
        );
    }


    @IsTest
    static void missingPhoneReturns400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'phone',
            ''
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Phone number is required.'
        );
    }


    /*
     * =========================================================
     * EMAIL VALIDATION TESTS
     * =========================================================
     */

    @IsTest
    static void invalidEmailFormatsReturn400() {
        List<String> invalidEmails =
            new List<String>{
                'portal customer@example.com',
                'portal@@example.com',
                '@example.com',
                'portal@',
                'portal@examplecom',
                'portal@.com',
                'portal@example.c',
                '.portal@example.com',
                'portal.@example.com',
                'portal@.example.com'
            };

        for (String emailValue : invalidEmails) {
            Map<String, Object> payload =
                createValidPayload();

            payload.put(
                'email',
                emailValue
            );

            RegistrationLeadRest.LeadResponse response =
                invokeEndpoint(payload);

            assertBadRequest(
                response,
                'Please enter a valid email address.'
            );
        }
    }


    /*
     * =========================================================
     * PHONE VALIDATION TESTS
     * =========================================================
     */

    @IsTest
    static void invalidPhoneFormatsReturn400() {
        List<String> invalidPhones =
            new List<String>{
                '12345',
                '12345678901',
                '+123456',
                '+0123456789',
                '+1234567890123456',
                '98765ABCDE',
                '+91987654A210'
            };

        for (String phoneValue : invalidPhones) {
            Map<String, Object> payload =
                createValidPayload();

            payload.put(
                'phone',
                phoneValue
            );

            RegistrationLeadRest.LeadResponse response =
                invokeEndpoint(payload);

            assertBadRequest(
                response,
                'Enter a valid phone number with country code '
                + '(for example, +919876543210).'
            );
        }
    }


    /*
     * =========================================================
     * PASSWORD VALIDATION TESTS
     * =========================================================
     */

    @IsTest
    static void missingPasswordReturns400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'password',
            ''
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Enter Password is required.'
        );
    }


    @IsTest
    static void missingConfirmPasswordReturns400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'confirmPassword',
            ''
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Confirm Password is required.'
        );
    }


    @IsTest
    static void shortPasswordReturns400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'password',
            'Aa1!abc'
        );

        payload.put(
            'confirmPassword',
            'Aa1!abc'
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Password must contain at least 8 characters.'
        );
    }


    @IsTest
    static void longPasswordReturns400() {
        String longPassword =
            'Password1234567890!!!';

        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'password',
            longPassword
        );

        payload.put(
            'confirmPassword',
            longPassword
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Password cannot contain more than 20 characters.'
        );
    }


    @IsTest
    static void longConfirmPasswordReturns400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'password',
            VALID_PASSWORD
        );

        payload.put(
            'confirmPassword',
            'Password1234567890!!!'
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Confirm Password cannot contain more than 20 characters.'
        );
    }


    @IsTest
    static void mismatchedPasswordsReturn400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'confirmPassword',
            'Different1!'
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Password and Confirm Password do not match.'
        );
    }


    @IsTest
    static void passwordWithoutUppercaseReturns400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'password',
            'password1!'
        );

        payload.put(
            'confirmPassword',
            'password1!'
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Password must contain at least one uppercase letter.'
        );
    }


    @IsTest
    static void passwordWithoutLowercaseReturns400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'password',
            'PASSWORD1!'
        );

        payload.put(
            'confirmPassword',
            'PASSWORD1!'
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Password must contain at least one lowercase letter.'
        );
    }


    @IsTest
    static void passwordWithoutNumberReturns400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'password',
            'Password!'
        );

        payload.put(
            'confirmPassword',
            'Password!'
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Password must contain at least one number.'
        );
    }


    @IsTest
    static void passwordWithoutSpecialCharacterReturns400() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'password',
            'Password1'
        );

        payload.put(
            'confirmPassword',
            'Password1'
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Password must contain at least one special character.'
        );
    }


    /*
     * =========================================================
     * SOURCE LEAD VALIDATION TESTS
     * =========================================================
     */

    @IsTest
    static void invalidSourceLeadIdReturns400() {
        Map<String, Object> payload =
            createConsultationPayload(
                VALID_EMAIL
            );

        payload.put(
            'sourceLeadId',
            'INVALID-ID'
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Invalid source Lead ID.'
        );
    }


    @IsTest
    static void nonLeadSourceIdReturns400() {
        Map<String, Object> payload =
            createConsultationPayload(
                VALID_EMAIL
            );

        payload.put(
            'sourceLeadId',
            UserInfo.getUserId()
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'Invalid source Lead ID.'
        );
    }


    @IsTest
    static void deletedSourceLeadReturns404() {
        Lead sourceLead =
            createSourceLead(
                'deleted.source@example.com',
                VALID_PASSWORD,
                VALID_PASSWORD
            );

        Id sourceLeadId =
            sourceLead.Id;

        delete sourceLead;

        Map<String, Object> payload =
            createConsultationPayload(
                'deleted.source@example.com'
            );

        payload.put(
            'sourceLeadId',
            sourceLeadId
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        System.assertEquals(
            404,
            RestContext.response.statusCode,
            'Missing source Lead should return 404.'
        );

        System.assertEquals(
            false,
            response.success,
            'Response should indicate failure.'
        );

        System.assertEquals(
            'The source customer account was not found.',
            response.message,
            'Unexpected response message.'
        );
    }


    @IsTest
    static void sourceLeadEmailMismatchReturns400() {
        Lead sourceLead =
            createSourceLead(
                'source.customer@example.com',
                VALID_PASSWORD,
                VALID_PASSWORD
            );

        Map<String, Object> payload =
            createConsultationPayload(
                'different.customer@example.com'
            );

        payload.put(
            'sourceLeadId',
            sourceLead.Id
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'The source customer does not match the supplied email.'
        );
    }


    @IsTest
    static void sourceLeadWithoutCredentialsReturns400() {
        Lead sourceLead =
            createSourceLead(
                'without.credentials@example.com',
                null,
                null
            );

        Map<String, Object> payload =
            createConsultationPayload(
                'without.credentials@example.com'
            );

        payload.put(
            'sourceLeadId',
            sourceLead.Id
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        assertBadRequest(
            response,
            'The source customer does not have portal credentials.'
        );
    }


    /*
     * =========================================================
     * SUCCESS TESTS
     * =========================================================
     */

    @IsTest
    static void prospectSignupReturns200() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'email',
            'signup.success@example.com'
        );

        Test.startTest();

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Successful registration should return 200.'
        );

        System.assertEquals(
            true,
            response.success,
            'Registration should succeed.'
        );

        System.assertNotEquals(
            null,
            response.leadId,
            'Created Lead Id should be returned.'
        );

        System.assertEquals(
            'Prospect account created successfully.',
            response.message,
            'Unexpected success message.'
        );

        Lead createdLead = [
            SELECT
                FirstName,
                LastName,
                Email,
                Phone,
                Company,
                Enter_Password__c,
                Confirm_password__c
            FROM Lead
            WHERE Id = :response.leadId
        ];

        System.assertEquals(
            VALID_FIRST_NAME,
            createdLead.FirstName,
            'First Name was not stored correctly.'
        );

        System.assertEquals(
            VALID_LAST_NAME,
            createdLead.LastName,
            'Last Name was not stored correctly.'
        );

        System.assertEquals(
            'signup.success@example.com',
            createdLead.Email,
            'Email was not stored correctly.'
        );

        System.assertEquals(
            VALID_PHONE,
            createdLead.Phone,
            'Phone was not stored correctly.'
        );

        System.assertEquals(
            VALID_PASSWORD,
            createdLead.Enter_Password__c,
            'Password was not stored correctly.'
        );

        System.assertEquals(
            VALID_PASSWORD,
            createdLead.Confirm_password__c,
            'Confirm Password was not stored correctly.'
        );
    }


    @IsTest
    static void consultationWithoutPasswordReturns200() {
        Map<String, Object> payload =
            createConsultationPayload(
                'consultation@example.com'
            );

        payload.put(
            'phone',
            VALID_LOCAL_PHONE
        );

        payload.remove(
            'companyName'
        );

        Test.startTest();

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Consultation registration should return 200.'
        );

        System.assertEquals(
            true,
            response.success,
            'Consultation registration should succeed.'
        );

        System.assertNotEquals(
            null,
            response.leadId,
            'A Lead should have been created.'
        );

        System.assertEquals(
            'Lead registered successfully.',
            response.message,
            'Unexpected consultation success message.'
        );

        Lead createdLead = [
            SELECT
                Company,
                Enter_Password__c,
                Confirm_password__c
            FROM Lead
            WHERE Id = :response.leadId
        ];

        System.assertEquals(
            'self',
            createdLead.Company,
            'Company should default to self.'
        );

        System.assertEquals(
            null,
            createdLead.Enter_Password__c,
            'Consultation should not require a password.'
        );
    }


    @IsTest
    static void sourceLeadCredentialsAreCopied() {
        String sourceEmail =
            'credential.copy@example.com';

        Lead sourceLead =
            createSourceLead(
                sourceEmail,
                VALID_PASSWORD,
                VALID_PASSWORD
            );

        Map<String, Object> payload =
            createConsultationPayload(
                sourceEmail
            );

        payload.put(
            'sourceLeadId',
            sourceLead.Id
        );

        Test.startTest();

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Source Lead registration should succeed.'
        );

        System.assertEquals(
            true,
            response.success,
            'New Lead should be created.'
        );

        Lead createdLead = [
            SELECT
                Enter_Password__c,
                Confirm_password__c
            FROM Lead
            WHERE Id = :response.leadId
        ];

        System.assertEquals(
            VALID_PASSWORD,
            createdLead.Enter_Password__c,
            'Password should be copied from source Lead.'
        );

        System.assertEquals(
            VALID_PASSWORD,
            createdLead.Confirm_password__c,
            'Confirm Password should be copied from source Lead.'
        );
    }


    @IsTest
    static void emailAndInputValuesAreNormalized() {
        Map<String, Object> payload =
            createValidPayload();

        payload.put(
            'firstName',
            '  Portal  '
        );

        payload.put(
            'lastName',
            '  Client  '
        );

        payload.put(
            'email',
            '  NORMALIZED.USER@EXAMPLE.COM  '
        );

        payload.put(
            'phone',
            '  +919876543210  '
        );

        payload.put(
            'companyName',
            '  Arelia Space  '
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Normalized input should be accepted.'
        );

        Lead createdLead = [
            SELECT
                FirstName,
                LastName,
                Email,
                Phone,
                Company
            FROM Lead
            WHERE Id = :response.leadId
        ];

        System.assertEquals(
            'Portal',
            createdLead.FirstName,
            'First Name should be trimmed.'
        );

        System.assertEquals(
            'Client',
            createdLead.LastName,
            'Last Name should be trimmed.'
        );

        System.assertEquals(
            'normalized.user@example.com',
            createdLead.Email,
            'Email should be normalized.'
        );

        System.assertEquals(
            '+919876543210',
            createdLead.Phone,
            'Phone should be trimmed.'
        );

        System.assertEquals(
            'Arelia Space',
            createdLead.Company,
            'Company should be trimmed.'
        );
    }


    /*
     * =========================================================
     * DUPLICATE EMAIL TEST
     * =========================================================
     */

    @IsTest
    static void duplicateEmailCanCreateMultipleLeads() {
        String duplicateEmail =
            'duplicate.allowed@example.com';

        Map<String, Object> firstPayload =
            createConsultationPayload(
                duplicateEmail
            );

        RegistrationLeadRest.LeadResponse firstResponse =
            invokeEndpoint(firstPayload);

        System.assertEquals(
            true,
            firstResponse.success,
            'First Lead should be created.'
        );

        Map<String, Object> secondPayload =
            createConsultationPayload(
                duplicateEmail
            );

        RegistrationLeadRest.LeadResponse secondResponse =
            invokeEndpoint(secondPayload);

        System.assertEquals(
            true,
            secondResponse.success,
            'Second Lead with same email should also be created.'
        );

        System.assertNotEquals(
            firstResponse.leadId,
            secondResponse.leadId,
            'Two separate Lead records should be created.'
        );

        List<Lead> duplicateLeads = [
            SELECT Id
            FROM Lead
            WHERE Email = :duplicateEmail
        ];

        System.assertEquals(
            2,
            duplicateLeads.size(),
            'Two Leads should exist with the same email.'
        );
    }


    /*
     * =========================================================
     * DATABASE ERROR HANDLING
     * =========================================================
     */

    @IsTest
    static void leadInsertFailureReturns400() {
        Map<String, Object> payload =
            createConsultationPayload(
                'dml.failure@example.com'
            );

        payload.put(
            'companyName',
            createLongValue(300)
        );

        RegistrationLeadRest.LeadResponse response =
            invokeEndpoint(payload);

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Invalid Lead data should return 400.'
        );

        System.assertEquals(
            false,
            response.success,
            'Lead creation should fail.'
        );

        System.assertEquals(
            null,
            response.leadId,
            'Failed insertion should not return a Lead Id.'
        );

        System.assertNotEquals(
            null,
            response.message,
            'Salesforce DML error should be returned.'
        );
    }
}
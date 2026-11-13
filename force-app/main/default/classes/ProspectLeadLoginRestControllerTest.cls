/**
 * -----------------------------------------------------------------------------
 * Class Name      : ProspectLeadLoginRestControllerTest
 * Author          : Arelia
 * Created Date    : Oct 12, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 12, 2026
 * Description     : Test class for ProspectLeadLoginRestController.
 *                   Covers login validation, authentication,
 *                   portal account linking and converted Leads.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ProspectLeadLoginRestControllerTest {

    private static final String ENDPOINT =
        '/services/apexrest/registration/lead/login';

    private static final String HTTP_POST = 'POST';

    private static final String VALID_EMAIL =
        'prospect.login@example.com';

    private static final String VALID_PASSWORD =
        'SecurePass123';

    private static final String INVALID_PASSWORD =
        'WrongPass123';

    private static final String INVALID_LOGIN_MESSAGE =
        'Invalid email address or password.';

    private static final String SUCCESS_MESSAGE =
        'Sign in successful.';

    private static final Integer HTTP_OK = 200;
    private static final Integer HTTP_BAD_REQUEST = 400;
    private static final Integer HTTP_UNAUTHORIZED = 401;

    /**
     * Creates a Lead owned by the running User.
     */
    private static Lead createLead(
        String firstNameValue,
        String lastNameValue,
        String emailValue,
        String passwordValue
    ) {
        return new Lead(
            FirstName = firstNameValue,
            LastName = lastNameValue,
            Company = 'Arelia Test Company',
            Email = emailValue,
            Phone = '9876543210',
            Status = getOpenLeadStatus(),
            OwnerId = UserInfo.getUserId(),
            Enter_Password__c = passwordValue,
            Project_Request_Submitted__c = false
        );
    }

    /**
     * Returns a non-converted Lead status.
     */
    private static String getOpenLeadStatus() {

        List<LeadStatus> statuses = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = false
            ORDER BY SortOrder
            LIMIT 1
        ];

        System.assert(
            !statuses.isEmpty(),
            'An open Lead status must exist.'
        );

        return statuses[0].MasterLabel;
    }

    /**
     * Returns a converted Lead status.
     */
    private static String getConvertedLeadStatus() {

        List<LeadStatus> statuses = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            ORDER BY SortOrder
            LIMIT 1
        ];

        System.assert(
            !statuses.isEmpty(),
            'A converted Lead status must exist.'
        );

        return statuses[0].MasterLabel;
    }

    /**
     * Initializes the REST request and response.
     */
    private static void prepareRequest(
        String requestBody
    ) {
        RestRequest requestValue = new RestRequest();

        requestValue.requestURI = ENDPOINT;
        requestValue.httpMethod = HTTP_POST;

        if (requestBody != null) {
            requestValue.requestBody =
                Blob.valueOf(requestBody);
        }

        RestContext.request = requestValue;
        RestContext.response = new RestResponse();
    }

    /**
     * Builds a login request.
     */
    private static String buildRequest(
        String emailValue,
        String passwordValue
    ) {
        Map<String, Object> payload =
            new Map<String, Object>{
                'email' => emailValue,
                'password' => passwordValue
            };

        return JSON.serialize(payload);
    }

    /**
     * Executes the REST login method.
     */
    private static ProspectLeadLoginRestController.LoginResponse
        executeLogin(String requestBody) {

        prepareRequest(requestBody);

        return ProspectLeadLoginRestController.loginProspect();
    }

    /**
     * Validates an unsuccessful login response.
     */
    private static void assertFailure(
        ProspectLeadLoginRestController.LoginResponse responseValue,
        Integer expectedStatus,
        String expectedMessage
    ) {
        System.assertEquals(
            expectedStatus,
            RestContext.response.statusCode,
            'Unexpected HTTP status.'
        );

        System.assertEquals(
            false,
            responseValue.success,
            'Login must fail.'
        );

        System.assertEquals(
            expectedMessage,
            responseValue.message,
            'Unexpected error message.'
        );

        System.assertEquals(
            false,
            responseValue.projectSubmitted,
            'Project submitted should be false.'
        );

        System.assertEquals(
            null,
            responseValue.leadId,
            'Failed login must not return a Lead Id.'
        );
    }

    /**
     * Validates a successful login response.
     */
    private static void assertSuccess(
        ProspectLeadLoginRestController.LoginResponse responseValue,
        Id expectedLeadId
    ) {
        System.assertEquals(
            HTTP_OK,
            RestContext.response.statusCode,
            'Login should return HTTP 200.'
        );

        System.assertEquals(
            true,
            responseValue.success,
            'Login should succeed.'
        );

        System.assertEquals(
            SUCCESS_MESSAGE,
            responseValue.message,
            'Unexpected success message.'
        );

        System.assertEquals(
            expectedLeadId,
            responseValue.leadId,
            'Incorrect Lead Id returned.'
        );
    }

    /**
     * Creates and converts a Lead using User ownership.
     */
    private static Database.LeadConvertResult
        createConvertedLead(Id leadId) {

        Database.LeadConvert conversionRequest =
            new Database.LeadConvert();

        conversionRequest.setLeadId(leadId);

        conversionRequest.setConvertedStatus(
            getConvertedLeadStatus()
        );

        conversionRequest.setOwnerId(
            UserInfo.getUserId()
        );

        Database.LeadConvertResult conversionResult =
            Database.convertLead(conversionRequest);

        System.assertEquals(
            true,
            conversionResult.isSuccess(),
            'Lead conversion should succeed.'
        );

        return conversionResult;
    }

    /**
     * Creates a Lead with required conversion validations.
     */
    private static Lead createConversionReadyLead(
        String firstNameValue,
        String lastNameValue
    ) {
        Lead leadRecord = createLead(
            firstNameValue,
            lastNameValue,
            VALID_EMAIL,
            VALID_PASSWORD
        );

        leadRecord.Project_Request_Submitted__c = true;
        leadRecord.Site_Visit_Manager_Approval__c = true;
        leadRecord.Approval_Status__c = 'Approved';

        return leadRecord;
    }

    /**
     * Verifies successful login for an unconverted Lead.
     */
    @IsTest
    static void validLoginReturns200() {

        Lead leadRecord = createLead(
            'Arelia',
            'Client',
            VALID_EMAIL,
            VALID_PASSWORD
        );

        insert leadRecord;

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    VALID_EMAIL,
                    VALID_PASSWORD
                )
            );

        Test.stopTest();

        assertSuccess(
            responseValue,
            leadRecord.Id
        );

        System.assertEquals(
            'Arelia Client',
            responseValue.fullName
        );

        System.assertEquals(
            VALID_EMAIL,
            responseValue.email
        );

        System.assertEquals(
            '9876543210',
            responseValue.phone
        );

        System.assertEquals(
            null,
            responseValue.contactId
        );

        System.assertEquals(
            false,
            responseValue.projectSubmitted
        );
    }

    /**
     * Verifies successful login with a submitted project.
     */
    @IsTest
    static void submittedProjectReturnsTrue() {

        Lead leadRecord = createLead(
            'Project',
            'Client',
            VALID_EMAIL,
            VALID_PASSWORD
        );

        leadRecord.Project_Request_Submitted__c = true;

        insert leadRecord;

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    VALID_EMAIL,
                    VALID_PASSWORD
                )
            );

        Test.stopTest();

        assertSuccess(
            responseValue,
            leadRecord.Id
        );

        System.assertEquals(
            true,
            responseValue.projectSubmitted,
            'Project submitted should be true.'
        );
    }

    /**
     * Verifies email trimming and case normalization.
     */
    @IsTest
    static void mixedCaseEmailReturns200() {

        Lead leadRecord = createLead(
            'Email',
            'Client',
            VALID_EMAIL,
            VALID_PASSWORD
        );

        insert leadRecord;

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    '  PROSPECT.LOGIN@EXAMPLE.COM  ',
                    VALID_PASSWORD
                )
            );

        Test.stopTest();

        assertSuccess(
            responseValue,
            leadRecord.Id
        );
    }

    /**
     * Verifies missing request body.
     */
    @IsTest
    static void missingBodyReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(null);

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Request body is required.'
        );
    }

    /**
     * Verifies empty request body.
     */
    @IsTest
    static void emptyBodyReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin('');

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Request body is required.'
        );
    }

    /**
     * Verifies whitespace-only request body.
     */
    @IsTest
    static void whitespaceBodyReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin('   ');

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Request body is required.'
        );
    }

    /**
     * Verifies missing email attribute.
     */
    @IsTest
    static void missingEmailReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                '{"password":"SecurePass123"}'
            );

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Email address is required.'
        );
    }

    /**
     * Verifies null email attribute.
     */
    @IsTest
    static void nullEmailReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                '{"email":null,"password":"SecurePass123"}'
            );

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Email address is required.'
        );
    }

    /**
     * Verifies blank email attribute.
     */
    @IsTest
    static void blankEmailReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    '   ',
                    VALID_PASSWORD
                )
            );

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Email address is required.'
        );
    }

    /**
     * Verifies literal null email string.
     */
    @IsTest
    static void literalNullEmailReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    'null',
                    VALID_PASSWORD
                )
            );

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Email address is required.'
        );
    }

    /**
     * Verifies invalid email format.
     */
    @IsTest
    static void invalidEmailReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    'invalid-email',
                    VALID_PASSWORD
                )
            );

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Please enter a valid email address.'
        );
    }

    /**
     * Verifies invalid email domain.
     */
    @IsTest
    static void invalidDomainReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    'prospect@example',
                    VALID_PASSWORD
                )
            );

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Please enter a valid email address.'
        );
    }

    /**
     * Verifies missing password.
     */
    @IsTest
    static void missingPasswordReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                '{"email":"prospect.login@example.com"}'
            );

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Password is required.'
        );
    }

    /**
     * Verifies null password.
     */
    @IsTest
    static void nullPasswordReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                '{"email":"prospect.login@example.com",'
                + '"password":null}'
            );

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Password is required.'
        );
    }

    /**
     * Verifies blank password.
     */
    @IsTest
    static void blankPasswordReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    VALID_EMAIL,
                    '   '
                )
            );

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Password is required.'
        );
    }

    /**
     * Verifies incorrect password.
     */
    @IsTest
    static void wrongPasswordReturns401() {

        Lead leadRecord = createLead(
            'Wrong',
            'Password',
            VALID_EMAIL,
            VALID_PASSWORD
        );

        insert leadRecord;

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    VALID_EMAIL,
                    INVALID_PASSWORD
                )
            );

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_UNAUTHORIZED,
            INVALID_LOGIN_MESSAGE
        );
    }

    /**
     * Verifies an unknown email address.
     */
    @IsTest
    static void unknownEmailReturns401() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    'unknown@example.com',
                    VALID_PASSWORD
                )
            );

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_UNAUTHORIZED,
            INVALID_LOGIN_MESSAGE
        );
    }

    /**
     * Verifies rejected login for a different password.
     */
    @IsTest
    static void incorrectPasswordReturns401() {

        Lead leadRecord = createLead(
            'Case',
            'Sensitive',
            VALID_EMAIL,
            VALID_PASSWORD
        );

        insert leadRecord;

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    VALID_EMAIL,
                    'DifferentPass123'
                )
            );

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_UNAUTHORIZED,
            INVALID_LOGIN_MESSAGE
        );
    }

    /**
     * Verifies correct Lead selection for duplicate emails.
     */
    @IsTest
    static void duplicateEmailMatchesPassword() {

        Lead firstLead = createLead(
            'First',
            'Client',
            VALID_EMAIL,
            'FirstPass123'
        );

        Lead secondLead = createLead(
            'Second',
            'Client',
            VALID_EMAIL,
            'SecondPass123'
        );

        insert new List<Lead>{
            firstLead,
            secondLead
        };

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    VALID_EMAIL,
                    'SecondPass123'
                )
            );

        Test.stopTest();

        assertSuccess(
            responseValue,
            secondLead.Id
        );

        System.assertEquals(
            'Second Client',
            responseValue.fullName
        );
    }

    /**
     * Verifies null JSON payload handling.
     */
    @IsTest
    static void nullJsonPayloadReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin('null');

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Email address is required.'
        );
    }

    /**
     * Verifies malformed JSON handling.
     */
    @IsTest
    static void malformedJsonReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                '{"email":'
            );

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Invalid request format.'
        );
    }

    /**
     * Verifies empty JSON handling.
     */
    @IsTest
    static void emptyJsonReturns400() {

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin('{}');

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_BAD_REQUEST,
            'Email address is required.'
        );
    }

    /**
     * Verifies portal account identity resolution.
     */
    @IsTest
    static void portalAccountKeyReturnsOriginalLead() {

        Lead originalLead = createLead(
            'Original',
            'Client',
            VALID_EMAIL,
            VALID_PASSWORD
        );

        insert originalLead;

        Lead additionalLead = createLead(
            'Additional',
            'Client',
            VALID_EMAIL,
            VALID_PASSWORD
        );

        additionalLead.Portal_Account_Key__c =
            String.valueOf(originalLead.Id);

        insert additionalLead;

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    VALID_EMAIL,
                    VALID_PASSWORD
                )
            );

        Test.stopTest();

        assertSuccess(
            responseValue,
            originalLead.Id
        );

        System.assertEquals(
            'Original Client',
            responseValue.fullName
        );
    }

    /**
     * Verifies mismatched account credentials
     * do not replace the authenticated Lead.
     */
    @IsTest
    static void invalidPortalAccountKeepsMatchedLead() {

        Lead originalLead = createLead(
            'Original',
            'Client',
            VALID_EMAIL,
            'OriginalPass123'
        );

        insert originalLead;

        Lead additionalLead = createLead(
            'Additional',
            'Client',
            VALID_EMAIL,
            VALID_PASSWORD
        );

        additionalLead.Portal_Account_Key__c =
            String.valueOf(originalLead.Id);

        insert additionalLead;

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    VALID_EMAIL,
                    VALID_PASSWORD
                )
            );

        Test.stopTest();

        assertSuccess(
            responseValue,
            additionalLead.Id
        );

        System.assertEquals(
            'Additional Client',
            responseValue.fullName
        );
    }

    /**
     * Verifies unmatched account email does not
     * replace the authenticated Lead.
     */
    @IsTest
    static void differentAccountEmailKeepsMatchedLead() {

        Lead originalLead = createLead(
            'Original',
            'Client',
            'original@example.com',
            VALID_PASSWORD
        );

        insert originalLead;

        Lead additionalLead = createLead(
            'Additional',
            'Client',
            VALID_EMAIL,
            VALID_PASSWORD
        );

        additionalLead.Portal_Account_Key__c =
            String.valueOf(originalLead.Id);

        insert additionalLead;

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    VALID_EMAIL,
                    VALID_PASSWORD
                )
            );

        Test.stopTest();

        assertSuccess(
            responseValue,
            additionalLead.Id
        );
    }

    /**
     * Verifies authentication through converted Contact.
     */
    @IsTest
    static void convertedLeadLoginReturns200() {

        Lead leadRecord = createConversionReadyLead(
            'Converted',
            'Client'
        );

        insert leadRecord;

        Database.LeadConvertResult conversionResult =
            createConvertedLead(leadRecord.Id);

        Id contactId = conversionResult.getContactId();

        Contact contactRecord = [
            SELECT
                Id,
                FirstName,
                LastName,
                Email,
                Phone,
                Password__c
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ];

        contactRecord.Password__c = VALID_PASSWORD;

        update contactRecord;

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    VALID_EMAIL,
                    VALID_PASSWORD
                )
            );

        Test.stopTest();

        assertSuccess(
            responseValue,
            leadRecord.Id
        );

        System.assertEquals(
            contactId,
            responseValue.contactId,
            'Converted Contact Id should match.'
        );

        System.assertEquals(
            'Converted Client',
            responseValue.fullName
        );

        System.assertEquals(
            VALID_EMAIL,
            responseValue.email
        );

        System.assertEquals(
            true,
            responseValue.projectSubmitted
        );
    }

    /**
     * Verifies converted Contact password
     * matching is case-sensitive.
     */
    @IsTest
    static void convertedPasswordMismatchReturns401() {

        Lead leadRecord = createConversionReadyLead(
            'Converted',
            'Password'
        );

        insert leadRecord;

        Database.LeadConvertResult conversionResult =
            createConvertedLead(leadRecord.Id);

        Contact contactRecord = new Contact(
            Id = conversionResult.getContactId(),
            Password__c = VALID_PASSWORD
        );

        update contactRecord;

        Test.startTest();

        ProspectLeadLoginRestController.LoginResponse
            responseValue = executeLogin(
                buildRequest(
                    VALID_EMAIL,
                    'securepass123'
                )
            );

        Test.stopTest();

        assertFailure(
            responseValue,
            HTTP_UNAUTHORIZED,
            INVALID_LOGIN_MESSAGE
        );
    }
}
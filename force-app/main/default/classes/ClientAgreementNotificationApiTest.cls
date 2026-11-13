/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementNotificationApiTest
 * Author          : Arelia
 * Created Date    : Oct 6, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 6, 2026
 * Description     : This test class is for ClientAgreementNotificationApi
 */

@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.TooManyMethods')
private class ClientAgreementNotificationApiTest {

    private static final String CLIENT_EMAIL = 'agreement@example.com';
    private static final String LEAD_LAST_NAME = 'Agreement Client';
    private static final String LEAD_COMPANY = 'self';
    private static final String OPPORTUNITY_NAME = 'Agreement project';
    private static final String NOTIFICATION_SENT = 'CLIENT_AGREEMENT_SENT';
    private static final String NOTIFICATION_SIGNED = 'CLIENT_AGREEMENT_SIGNED';
    private static final String TITLE_SENT = 'Client Agreement Available';
    private static final String TITLE_SIGNED = 'Client Agreement Signed';
    private static final Integer STATUS_SUCCESS = 200;
    private static final Integer STATUS_BAD_REQUEST = 400;
    private static final Integer STATUS_FORBIDDEN = 403;
    private static final Integer STATUS_NOT_FOUND = 404;
    private static final String API_ENDPOINT = '/services/apexrest/client-portal/client-agreement-notification';

    /**
     * @description Creates REST request context and invokes ClientAgreementNotificationApi.getNotification().
     * @param leadId Lead Id supplied to REST API.
     * @param opportunityId Optional Opportunity Id.
     * @return NotificationResponse returned by REST API.
     */
    private static ClientAgreementNotificationApi.NotificationResponse readNotice(String leadId, String opportunityId) {
        RestRequest request = new RestRequest();
        request.requestURI = API_ENDPOINT;
        request.httpMethod = 'GET';

        if (leadId != null) {
            request.addParameter(
                'leadId',
                leadId
            );
        }

        if (opportunityId != null) {
            request.addParameter(
                'opportunityId',
                opportunityId
            );
        }

        RestContext.request = request;
        RestContext.response = new RestResponse();

        return ClientAgreementNotificationApi.getNotification();
    }

    /**
     * @description Creates an approved Lead using the required Arelia Lead conversion fields.
     * @return Newly created Lead.
     */
    private static Lead createLead() {

        Lead leadRecord = new Lead(
            LastName = LEAD_LAST_NAME,
            Company = LEAD_COMPANY,
            Email = CLIENT_EMAIL,
            Phone = '9876543210',
            Enter_Password__c = 'Example123!',
            Confirm_password__c = 'Example123!',
            Site_Visit_Manager_Approval__c = true,
            Approval_Status__c = 'Approved'
        );

        insert leadRecord;

        return leadRecord;
    }

    /**
     * @description Converts an approved Lead and creates the associated Opportunity.
     * @param leadId Lead Id to convert.
     * @return Successful LeadConvertResult.
     */
    private static Database.LeadConvertResult convertLead(
        Id leadId
    ) {

        LeadStatus convertedStatus = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ];

        Database.LeadConvert conversion =
            new Database.LeadConvert();

        conversion.setLeadId(leadId);

        conversion.setConvertedStatus(
            convertedStatus.MasterLabel
        );

        conversion.setOpportunityName(
            OPPORTUNITY_NAME
        );

        Database.LeadConvertResult result =
            Database.convertLead(conversion);

        System.assertEquals(
            true,
            result.isSuccess(),
            'Lead conversion should succeed.'
        );

        System.assertNotEquals(
            null,
            result.getOpportunityId(),
            'Converted Opportunity Id should be populated.'
        );

        return result;
    }

    /**
     * @description Updates Client Agreement status and client email on an Opportunity.
     * @param opportunityId Opportunity record Id.
     * @param isSent Agreement sent status.
     * @param isSigned Agreement signed status.
     * @param clientEmail Client email address.
     */
    private static void updateAgreementStatus(
        Id opportunityId,
        Boolean isSent,
        Boolean isSigned,
        String clientEmail
    ) {

        Opportunity opportunityRecord = new Opportunity(
            Id = opportunityId,
            Client_Agreement_Sent__c = isSent,
            Client_Agreement_Signed__c = isSigned,
            Email__c = clientEmail
        );

        update opportunityRecord;
    }

    /**
     * @description Verifies REST response status and expected success state.
     * @param response API response.
     * @param expectedStatus Expected HTTP status code.
     * @param expectedSuccess Expected success flag.
     */
    private static void assertResponseStatus(
        ClientAgreementNotificationApi.NotificationResponse response,
        Integer expectedStatus,
        Boolean expectedSuccess
    ) {

        System.assertNotEquals(
            null,
            response,
            'API response should not be null.'
        );

        System.assertEquals(
            expectedSuccess,
            response.success,
            'API success flag should match expected value.'
        );

        System.assertEquals(
            expectedStatus,
            RestContext.response.statusCode,
            'HTTP status code should match expected value.'
        );
    }

    /**
     * @description Verifies agreement notification visibility, title, and type.
     * @param response API response.
     * @param expectedTitle Expected notification title.
     * @param expectedType Expected notification type.
     */
    private static void assertNotificationDetails(
        ClientAgreementNotificationApi.NotificationResponse response,
        String expectedTitle,
        String expectedType
    ) {

        System.assertEquals(
            true,
            response.showNotification,
            'Notification should be visible.'
        );

        System.assertEquals(
            expectedTitle,
            response.notificationTitle,
            'Notification title should match.'
        );

        System.assertEquals(
            expectedType,
            response.notificationType,
            'Notification type should match.'
        );

        System.assert(
            String.isNotBlank(response.notificationMessage),
            'Notification message should not be blank.'
        );
    }

    /**
     * @description Verifies no notification is displayed.
     * @param response API response.
     */
    private static void assertNoNotification(ClientAgreementNotificationApi.NotificationResponse response) {

        assertResponseStatus(
            response,
            STATUS_SUCCESS,
            true
        );

        System.assertEquals(
            false,
            response.showNotification,
            'Notification should not be displayed.'
        );
    }

    /**
     * @description Verifies API error response.
     * @param response API response.
     * @param expectedStatus Expected HTTP status.
     * @param expectedMessage Expected error message.
     */
    private static void assertErrorResponse(
        ClientAgreementNotificationApi.NotificationResponse response,
        Integer expectedStatus,
        String expectedMessage
    ) {

        assertResponseStatus(
            response,
            expectedStatus,
            false
        );

        System.assertEquals(
            expectedMessage,
            response.message,
            'Error message should match.'
        );

        System.assertEquals(
            false,
            response.showNotification,
            'Error response should not display notification.'
        );
    }

    /**
     * @description Tests the complete agreement notification flow before and after Lead conversion.
     */
    @IsTest
    static void checkboxControlsNoticeAndOwnershipIsChecked() {

        Lead leadRecord = createLead();

        Test.startTest();

        // Lead is not converted.
        ClientAgreementNotificationApi.NotificationResponse
            beforeConversion = readNotice(
                String.valueOf(leadRecord.Id),
                null
            );

        assertNoNotification(beforeConversion);

        // Convert the Lead.
        Database.LeadConvertResult conversionResult =
            convertLead(leadRecord.Id);

        // Client Agreement not sent.
        updateAgreementStatus(
            conversionResult.getOpportunityId(),
            false,
            false,
            CLIENT_EMAIL
        );

        ClientAgreementNotificationApi.NotificationResponse
            beforeAgreement = readNotice(
                String.valueOf(leadRecord.Id),
                null
            );

        assertNoNotification(beforeAgreement);

        System.assertEquals(
            false,
            beforeAgreement.clientAgreementSent,
            'Agreement sent status should be false.'
        );

        System.assertEquals(
            false,
            beforeAgreement.clientAgreementSigned,
            'Agreement signed status should be false.'
        );

        // Client Agreement sent.
        updateAgreementStatus(
            conversionResult.getOpportunityId(),
            true,
            false,
            CLIENT_EMAIL
        );

        ClientAgreementNotificationApi.NotificationResponse
            afterAgreement = readNotice(
                String.valueOf(leadRecord.Id),
                null
            );

        Test.stopTest();

        assertResponseStatus(
            afterAgreement,
            STATUS_SUCCESS,
            true
        );

        assertNotificationDetails(
            afterAgreement,
            TITLE_SENT,
            NOTIFICATION_SENT
        );

        System.assertEquals(
            conversionResult.getOpportunityId(),
            afterAgreement.opportunityId,
            'Converted Opportunity Id should match.'
        );

        System.assertEquals(
            OPPORTUNITY_NAME,
            afterAgreement.opportunityName,
            'Opportunity name should match.'
        );

        System.assertEquals(
            CLIENT_EMAIL,
            afterAgreement.clientEmail,
            'Client email should match.'
        );

        System.assertEquals(
            true,
            afterAgreement.clientAgreementSent,
            'Agreement sent flag should be true.'
        );

        System.assertEquals(
            false,
            afterAgreement.clientAgreementSigned,
            'Agreement signed flag should be false.'
        );

        System.assert(
            afterAgreement.notificationMessage.contains(
                CLIENT_EMAIL
            ),
            'Notification should contain client email.'
        );

        System.assertEquals(
            'Notification status retrieved successfully.',
            afterAgreement.message,
            'Success message should match.'
        );
    }

    /**
     * @description Tests the signed Client Agreement notification when an agreement is signed.
     */
    @IsTest
    static void signedAgreementDisplaysSignedNotification() {

        Lead leadRecord = createLead();

        Database.LeadConvertResult conversionResult =
            convertLead(leadRecord.Id);

        updateAgreementStatus(
            conversionResult.getOpportunityId(),
            true,
            true,
            CLIENT_EMAIL
        );

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(leadRecord.Id),
                null
            );

        Test.stopTest();

        assertResponseStatus(
            response,
            STATUS_SUCCESS,
            true
        );

        assertNotificationDetails(
            response,
            TITLE_SIGNED,
            NOTIFICATION_SIGNED
        );

        System.assertEquals(
            true,
            response.clientAgreementSent,
            'Agreement sent flag should remain true.'
        );

        System.assertEquals(
            true,
            response.clientAgreementSigned,
            'Agreement signed flag should be true.'
        );

        System.assertEquals(
            'Your Client Agreement has been successfully signed. ' +
            'Please check your registered email address to download ' +
            'a copy of the signed agreement.',
            response.notificationMessage,
            'Signed agreement notification message should match.'
        );

        System.assertEquals(
            conversionResult.getOpportunityId(),
            response.opportunityId,
            'Opportunity Id should match.'
        );
    }

    /**
     * @description Verifies signed agreement notification takes priority when both flags are true.
     */
    @IsTest
    static void signedNotificationTakesPriorityOverSentNotification() {

        Lead leadRecord = createLead();

        Database.LeadConvertResult conversionResult =
            convertLead(leadRecord.Id);

        updateAgreementStatus(
            conversionResult.getOpportunityId(),
            true,
            true,
            CLIENT_EMAIL
        );

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(leadRecord.Id),
                String.valueOf(conversionResult.getOpportunityId())
            );

        Test.stopTest();

        assertResponseStatus(
            response,
            STATUS_SUCCESS,
            true
        );

        assertNotificationDetails(
            response,
            TITLE_SIGNED,
            NOTIFICATION_SIGNED
        );

        System.assertEquals(
            true,
            response.clientAgreementSigned,
            'Signed status should remain true.'
        );
    }

    /**
     * @description Tests missing Lead Id validation.
     */
    @IsTest
    static void missingLeadIdReturns400() {

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                null,
                null
            );

        Test.stopTest();

        assertErrorResponse(
            response,
            STATUS_BAD_REQUEST,
            'A valid Lead Id is required.'
        );
    }

    /**
     * @description Tests invalid Lead Id format.
     */
    @IsTest
    static void invalidLeadIdReturns400() {

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                'INVALID_ID',
                null
            );

        Test.stopTest();

        assertErrorResponse(
            response,
            STATUS_BAD_REQUEST,
            'A valid Lead Id is required.'
        );
    }

    /**
     * @description Tests incorrect SObject Id supplied as the Lead Id.
     */
    @IsTest
    static void accountIdUsedAsLeadIdReturns400() {

        Account accountRecord = new Account(
            Name = 'Test Account'
        );

        insert accountRecord;

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(accountRecord.Id),
                null
            );

        Test.stopTest();

        assertErrorResponse(
            response,
            STATUS_BAD_REQUEST,
            'A valid Lead Id is required.'
        );
    }

    /**
     * @description Tests unauthorized Opportunity access.
     */
    @IsTest
    static void mismatchingOpportunityReturns403() {

        Lead leadRecord = createLead();

        convertLead(leadRecord.Id);

        Opportunity anotherOpportunity = new Opportunity(
            Name = 'Different Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );

        insert anotherOpportunity;

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(leadRecord.Id),
                String.valueOf(anotherOpportunity.Id)
            );

        Test.stopTest();

        assertErrorResponse(
            response,
            STATUS_FORBIDDEN,
            'You are not authorized to access this Opportunity.'
        );
    }

    /**
     * @description Tests an Account Id supplied as the Opportunity Id.
     */
    @IsTest
    static void accountIdAsOpportunityReturns403() {

        Lead leadRecord = createLead();

        Database.LeadConvertResult conversionResult =
            convertLead(leadRecord.Id);

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(leadRecord.Id),
                String.valueOf(conversionResult.getAccountId())
            );

        Test.stopTest();

        assertErrorResponse(
            response,
            STATUS_FORBIDDEN,
            'You are not authorized to access this Opportunity.'
        );
    }

    /**
     * @description Tests client email fallback when Opportunity Email__c is blank.
     */
    @IsTest
    static void blankEmailUsesRegisteredEmailText() {

        Lead leadRecord = createLead();

        Database.LeadConvertResult conversionResult =
            convertLead(leadRecord.Id);

        updateAgreementStatus(
            conversionResult.getOpportunityId(),
            true,
            false,
            null
        );

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(leadRecord.Id),
                null
            );

        Test.stopTest();

        assertResponseStatus(
            response,
            STATUS_SUCCESS,
            true
        );

        assertNotificationDetails(
            response,
            TITLE_SENT,
            NOTIFICATION_SENT
        );

        System.assert(
            response.notificationMessage.contains(
                'your registered email'
            ),
            'Notification should use registered email fallback.'
        );

        System.assertEquals(
            null,
            response.clientEmail,
            'Client email should remain null.'
        );
    }

    /**
     * @description Verifies access using the matching converted Opportunity Id.
     */
    @IsTest
    static void matchingOpportunityIdIsAllowed() {

        Lead leadRecord = createLead();

        Database.LeadConvertResult conversionResult =
            convertLead(leadRecord.Id);

        updateAgreementStatus(
            conversionResult.getOpportunityId(),
            true,
            false,
            CLIENT_EMAIL
        );

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(leadRecord.Id),
                String.valueOf(conversionResult.getOpportunityId())
            );

        Test.stopTest();

        assertResponseStatus(
            response,
            STATUS_SUCCESS,
            true
        );

        assertNotificationDetails(
            response,
            TITLE_SENT,
            NOTIFICATION_SENT
        );

        System.assertEquals(
            conversionResult.getOpportunityId(),
            response.opportunityId,
            'Matching Opportunity should be accessible.'
        );
    }

    /**
     * @description Tests a valid Lead Id whose record has been deleted.
     */
    @IsTest
    static void leadNotFoundReturns404() {

        Lead leadRecord = createLead();

        Id deletedLeadId = leadRecord.Id;

        delete leadRecord;

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(deletedLeadId),
                null
            );

        Test.stopTest();

        assertErrorResponse(
            response,
            STATUS_NOT_FOUND,
            'Prospect Lead not found.'
        );
    }

    /**
     * @description Tests when a converted Opportunity is deleted but the Lead still references it.
     */
    @IsTest
    static void convertedOpportunityNotFoundReturns404() {

        Lead leadRecord = createLead();

        Database.LeadConvertResult conversionResult =
            convertLead(leadRecord.Id);

        Id opportunityId =
            conversionResult.getOpportunityId();

        delete new Opportunity(
            Id = opportunityId
        );

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(leadRecord.Id),
                null
            );

        Test.stopTest();

        assertErrorResponse(
            response,
            STATUS_NOT_FOUND,
            'Opportunity not found.'
        );
    }

    /**
     * @description Verifies that an unconverted Lead returns HTTP 200 without notification details.
     */
    @IsTest
    static void unconvertedLeadReturnsNoNotification() {

        Lead leadRecord = createLead();

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(leadRecord.Id),
                null
            );

        Test.stopTest();

        assertNoNotification(response);

        System.assertEquals(
            null,
            response.opportunityId,
            'Unconverted Lead should not have an Opportunity Id.'
        );

        System.assertEquals(
            false,
            response.clientAgreementSent,
            'Agreement sent should default to false.'
        );

        System.assertEquals(
            false,
            response.clientAgreementSigned,
            'Agreement signed should default to false.'
        );
    }

    /**
     * @description Tests Agreement Signed status when Agreement Sent is false.
     * The API prioritizes the signed flag.
     */
    @IsTest
    static void signedAgreementDisplaysNotificationWhenSentFlagIsFalse() {

        Lead leadRecord = createLead();

        Database.LeadConvertResult conversionResult =
            convertLead(leadRecord.Id);

        updateAgreementStatus(
            conversionResult.getOpportunityId(),
            false,
            true,
            CLIENT_EMAIL
        );

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(leadRecord.Id),
                null
            );

        Test.stopTest();

        assertResponseStatus(
            response,
            STATUS_SUCCESS,
            true
        );

        assertNotificationDetails(
            response,
            TITLE_SIGNED,
            NOTIFICATION_SIGNED
        );

        System.assertEquals(
            false,
            response.clientAgreementSent,
            'Agreement sent flag should remain false.'
        );

        System.assertEquals(
            true,
            response.clientAgreementSigned,
            'Signed status should remain true.'
        );
    }

    /**
     * @description Tests REST response headers returned by the notification API.
     */
    @IsTest
    static void responseHeadersShouldBeConfigured() {

        Lead leadRecord = createLead();

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(leadRecord.Id),
                null
            );

        Test.stopTest();

        assertNoNotification(response);

        System.assertEquals(
            'no-store',
            RestContext.response.headers.get('Cache-Control'),
            'Cache-Control should prevent response caching.'
        );

        System.assertEquals(
            'application/json',
            RestContext.response.headers.get('Content-Type'),
            'Content-Type should be application/json.'
        );
    }

    /**
     * @description Tests blank Opportunity Id parameter.
     * The API should resolve the converted Opportunity from the Lead instead of rejecting an empty parameter.
     */
    @IsTest
    static void blankOpportunityIdUsesConvertedOpportunity() {

        Lead leadRecord = createLead();

        Database.LeadConvertResult conversionResult =
            convertLead(leadRecord.Id);

        updateAgreementStatus(
            conversionResult.getOpportunityId(),
            true,
            false,
            CLIENT_EMAIL
        );

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(leadRecord.Id),
                ''
            );

        Test.stopTest();

        assertResponseStatus(
            response,
            STATUS_SUCCESS,
            true
        );

        assertNotificationDetails(
            response,
            TITLE_SENT,
            NOTIFICATION_SENT
        );

        System.assertEquals(
            conversionResult.getOpportunityId(),
            response.opportunityId,
            'Converted Opportunity should be resolved automatically.'
        );
    }

    /**
     * @description Tests invalid Opportunity Id format when supplied with a converted Lead.
     * The API returns HTTP 403 because the supplied value does not match ConvertedOpportunityId.
     */
    @IsTest
    static void invalidOpportunityIdReturns403() {

        Lead leadRecord = createLead();

        convertLead(leadRecord.Id);

        Test.startTest();

        ClientAgreementNotificationApi.NotificationResponse response =
            readNotice(
                String.valueOf(leadRecord.Id),
                'INVALID_OPPORTUNITY'
            );

        Test.stopTest();

        assertErrorResponse(
            response,
            STATUS_FORBIDDEN,
            'You are not authorized to access this Opportunity.'
        );
    }
}
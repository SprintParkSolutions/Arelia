/**
 * -----------------------------------------------------------------------------
 * Class Name      : ProformaInvoiceClientPushJobTest
 * Author          : Arelia
 * Created Date    : Oct 12, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 12, 2026
 * Description     : Unit tests for ProformaInvoiceClientPushJob.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ProformaInvoiceClientPushJobTest {

    private static final String EVENT_SENT =
        'PROFORMA_SENT';

    private static final String EVENT_APPROVED =
        'MANAGER_APPROVED';

    private static final String STATUS_SENT =
        'Sent';

    private static final String STATUS_APPROVED =
        'Approved';

    private static final String TEST_TOKEN =
        'test_proforma_fcm_token_123';

    private static final String SECOND_TOKEN =
        'test_proforma_fcm_token_456';

    private static final String SECURE_TOKEN =
        'test_proforma_secure_token_123';

    private static final String TEST_EMAIL =
        'proforma.test@example.com';

    /**
     * Mock Firebase HTTP responses.
     */
    private class FirebaseSuccessMock
        implements HttpCalloutMock {

        public HTTPResponse respond(
            HTTPRequest requestValue
        ) {
            HttpResponse responseValue =
                new HttpResponse();

            responseValue.setStatusCode(200);

            responseValue.setHeader(
                'Content-Type',
                'application/json'
            );

            responseValue.setBody(
                '{"name":"projects/test/messages/123",' +
                '"access_token":"test_access_token",' +
                '"token_type":"Bearer",' +
                '"expires_in":3600}'
            );

            return responseValue;
        }
    }

    /**
     * Mock an unsuccessful Firebase HTTP response.
     */
    private class FirebaseFailureMock
        implements HttpCalloutMock {

        public HTTPResponse respond(
            HTTPRequest requestValue
        ) {
            HttpResponse responseValue =
                new HttpResponse();

            responseValue.setStatusCode(500);

            responseValue.setHeader(
                'Content-Type',
                'application/json'
            );

            responseValue.setBody(
                '{"error":{"code":500,' +
                '"message":"Firebase server error",' +
                '"status":"INTERNAL"}}'
            );

            return responseValue;
        }
    }

    /**
     * Create a Lead eligible for conversion.
     */
    private static Lead createLead(
        String uniqueValue
    ) {
        Lead prospect = new Lead(
            FirstName = 'Proforma',
            LastName = 'Client ' + uniqueValue,
            Company = 'Arelia Test ' + uniqueValue,
            Email = uniqueValue + '@example.com',
            OwnerId = UserInfo.getUserId(),
            Status = getOpenLeadStatus(),
            Approval_Status__c = STATUS_APPROVED,
            Site_Visit_Manager_Approval__c = true,
            Project_Request_Submitted__c = true
        );

        insert prospect;

        return prospect;
    }

    /**
     * Retrieve a valid unconverted Lead status.
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
            'An open Lead status is required.'
        );

        return statuses[0].MasterLabel;
    }

    /**
     * Retrieve a valid converted Lead status.
     */
    private static String getConvertedLeadStatus() {
        List<LeadStatus> statuses = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ];

        System.assert(
            !statuses.isEmpty(),
            'A converted Lead status is required.'
        );

        return statuses[0].MasterLabel;
    }

    /**
     * Convert Lead and return its Opportunity.
     */
    private static Id convertLead(
        Lead prospect
    ) {
        Database.LeadConvert requestValue =
            new Database.LeadConvert();

        requestValue.setLeadId(
            prospect.Id
        );

        requestValue.setConvertedStatus(
            getConvertedLeadStatus()
        );

        requestValue.setOwnerId(
            UserInfo.getUserId()
        );

        requestValue.setDoNotCreateOpportunity(
            false
        );

        Database.LeadConvertResult resultValue =
            Database.convertLead(
                requestValue,
                false
            );

        System.assertEquals(
            true,
            resultValue.isSuccess(),
            'Lead conversion must succeed: ' +
            JSON.serialize(resultValue.getErrors())
        );

        System.assertNotEquals(
            null,
            resultValue.getOpportunityId(),
            'Converted Opportunity must exist.'
        );

        return resultValue.getOpportunityId();
    }

    /**
     * Create a converted Lead and Opportunity.
     */
    private static Id createOpportunity(
        String uniqueValue
    ) {
        Lead prospect = createLead(
            uniqueValue
        );

        return convertLead(
            prospect
        );
    }

    /**
     * Retrieve converted Lead ID from Opportunity.
     */
    private static Id getConvertedLeadId(
        Id opportunityId
    ) {
        List<Lead> prospects = [
            SELECT Id
            FROM Lead
            WHERE ConvertedOpportunityId = :opportunityId
            LIMIT 1
        ];

        System.assertEquals(
            1,
            prospects.size(),
            'Converted Lead must exist.'
        );

        return prospects[0].Id;
    }

    /**
     * Create a test Proforma Invoice.
     */
    private static Proforma_Invoice__c createInvoice(
        Id opportunityId,
        String statusValue,
        Boolean managerApproved,
        String secureToken
    ) {
        Proforma_Invoice__c invoice =
            new Proforma_Invoice__c();

        invoice.Opportunity__c =
            opportunityId;

        invoice.Status__c =
            statusValue;

        invoice.Manager_Approval__c =
            managerApproved;

        invoice.Secure_Token__c =
            secureToken;

        insert invoice;

        return invoice;
    }

    /**
     * Create a Prospect device token.
     */
    private static Prospect_Device_Token__c createDevice(
        Id leadId,
        String deviceId,
        String fcmToken,
        Boolean activeValue
    ) {
        Prospect_Device_Token__c device =
            new Prospect_Device_Token__c();

        device.Prospect_Lead__c =
            leadId;

        device.Device_Id__c =
            deviceId;

        device.FCM_Token__c =
            fcmToken;

        device.Active__c =
            activeValue;

        insert device;

        return device;
    }

    /**
     * Execute Queueable within test transaction.
     */
    private static void executeJob(
        Set<Id> invoiceIds,
        String eventValue
    ) {
        Test.startTest();

        System.enqueueJob(
            new ProformaInvoiceClientPushJob(
                invoiceIds,
                eventValue
            )
        );

        Test.stopTest();
    }

    /**
     * Verify null invoice IDs are handled.
     */
    @IsTest
    static void nullInvoiceIdsHandled() {
        executeJob(
            null,
            EVENT_SENT
        );

        System.assert(
            true,
            'Null invoice IDs must be handled.'
        );
    }

    /**
     * Verify empty invoice IDs are handled.
     */
    @IsTest
    static void emptyInvoiceIdsHandled() {
        executeJob(
            new Set<Id>(),
            EVENT_SENT
        );

        System.assert(
            true,
            'Empty invoice IDs must be handled.'
        );
    }

    /**
     * Verify blank notification event.
     */
    @IsTest
    static void blankNotificationEventHandled() {
        Id opportunityId =
            createOpportunity('BlankEvent');

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                false,
                SECURE_TOKEN
            );

        executeJob(
            new Set<Id>{ invoice.Id },
            ''
        );

        System.assertNotEquals(
            null,
            invoice.Id,
            'Invoice must remain available.'
        );
    }

    /**
     * Verify null notification event.
     */
    @IsTest
    static void nullNotificationEventHandled() {
        Id opportunityId =
            createOpportunity('NullEvent');

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                false,
                SECURE_TOKEN
            );

        executeJob(
            new Set<Id>{ invoice.Id },
            null
        );

        System.assertNotEquals(
            null,
            invoice.Id,
            'Invoice must remain available.'
        );
    }

    /**
     * Verify non-existing invoice IDs.
     */
    @IsTest
    static void nonexistentInvoiceHandled() {
        Id opportunityId =
            createOpportunity('MissingInvoice');

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                false,
                SECURE_TOKEN
            );

        Id deletedInvoiceId =
            invoice.Id;

        delete invoice;

        executeJob(
            new Set<Id>{ deletedInvoiceId },
            EVENT_SENT
        );

        Integer remainingInvoices = [
            SELECT COUNT()
            FROM Proforma_Invoice__c
            WHERE Id = :deletedInvoiceId
        ];

        System.assertEquals(
            0,
            remainingInvoices,
            'Deleted invoice must not be processed.'
        );
    }

    /**
     * Verify PROFORMA_SENT notification.
     */
    @IsTest
    static void proformaSentNotificationSucceeds() {
        Id opportunityId =
            createOpportunity('SentSuccess');

        Id leadId =
            getConvertedLeadId(opportunityId);

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                false,
                SECURE_TOKEN
            );

        createDevice(
            leadId,
            'sent-device',
            TEST_TOKEN,
            true
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseSuccessMock()
        );

        executeJob(
            new Set<Id>{ invoice.Id },
            EVENT_SENT
        );

        Proforma_Invoice__c resultValue = [
            SELECT Id, Status__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
        ];

        System.assertEquals(
            STATUS_SENT,
            resultValue.Status__c,
            'Invoice status must remain Sent.'
        );
    }

    /**
     * Verify MANAGER_APPROVED notification.
     */
    @IsTest
    static void managerApprovedNotificationSucceeds() {
        Id opportunityId =
            createOpportunity('ManagerSuccess');

        Id leadId =
            getConvertedLeadId(opportunityId);

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                true,
                SECURE_TOKEN
            );

        createDevice(
            leadId,
            'approved-device',
            TEST_TOKEN,
            true
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseSuccessMock()
        );

        executeJob(
            new Set<Id>{ invoice.Id },
            EVENT_APPROVED
        );

        Proforma_Invoice__c resultValue = [
            SELECT Manager_Approval__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
        ];

        System.assertEquals(
            true,
            resultValue.Manager_Approval__c,
            'Manager approval must remain true.'
        );
    }

    /**
     * Verify Sent event skips invoice with other status.
     */
    @IsTest
    static void incorrectSentStatusSkipsPush() {
        Id opportunityId =
            createOpportunity('WrongStatus');

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityId,
                STATUS_APPROVED,
                false,
                SECURE_TOKEN
            );

        executeJob(
            new Set<Id>{ invoice.Id },
            EVENT_SENT
        );

        Proforma_Invoice__c resultValue = [
            SELECT Status__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
        ];

        System.assertEquals(
            STATUS_APPROVED,
            resultValue.Status__c,
            'Invoice status must remain unchanged.'
        );
    }

    /**
     * Verify manager approval false skips push.
     */
    @IsTest
    static void managerApprovalFalseSkipsPush() {
        Id opportunityId =
            createOpportunity('NotManagerApproved');

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                false,
                SECURE_TOKEN
            );

        executeJob(
            new Set<Id>{ invoice.Id },
            EVENT_APPROVED
        );

        Proforma_Invoice__c resultValue = [
            SELECT Manager_Approval__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
        ];

        System.assertEquals(
            false,
            resultValue.Manager_Approval__c,
            'Manager approval must remain false.'
        );
    }

    /**
     * Verify unsupported notification event.
     */
    @IsTest
    static void unsupportedEventSkipsPush() {
        Id opportunityId =
            createOpportunity('UnsupportedEvent');

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                true,
                SECURE_TOKEN
            );

        executeJob(
            new Set<Id>{ invoice.Id },
            'UNKNOWN_EVENT'
        );

        System.assertNotEquals(
            null,
            invoice.Id,
            'Unsupported events must not fail.'
        );
    }

    /**
     * Verify invoice without converted Lead.
     */
    @IsTest
    static void opportunityWithoutConvertedLeadSkipsPush() {
        Account testAccount = new Account(
            Name = 'Arelia Standalone Account'
        );

        insert testAccount;

        Opportunity opportunityRecord =
            new Opportunity(
                Name = 'Standalone Proforma Opportunity',
                AccountId = testAccount.Id,
                StageName = getOpportunityStage(),
                CloseDate = Date.today().addDays(30)
            );

        insert opportunityRecord;

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityRecord.Id,
                STATUS_SENT,
                false,
                SECURE_TOKEN
            );

        executeJob(
            new Set<Id>{ invoice.Id },
            EVENT_SENT
        );

        Integer convertedLeadCount = [
            SELECT COUNT()
            FROM Lead
            WHERE ConvertedOpportunityId = :opportunityRecord.Id
        ];

        System.assertEquals(
            0,
            convertedLeadCount,
            'Standalone Opportunity must have no converted Lead.'
        );
    }

    /**
     * Retrieve valid Opportunity stage.
     */
    private static String getOpportunityStage() {
        List<OpportunityStage> stages = [
            SELECT MasterLabel
            FROM OpportunityStage
            WHERE IsActive = true
            ORDER BY SortOrder
            LIMIT 1
        ];

        System.assert(
            !stages.isEmpty(),
            'An active Opportunity stage is required.'
        );

        return stages[0].MasterLabel;
    }

    /**
     * Verify missing secure token skips push.
     */
    @IsTest
    static void missingSecureTokenSkipsPush() {
        Id opportunityId =
            createOpportunity('MissingSecureToken');

        Id leadId =
            getConvertedLeadId(opportunityId);

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                false,
                null
            );

        Prospect_Device_Token__c device =
            createDevice(
                leadId,
                'missing-secure-device',
                TEST_TOKEN,
                true
            );

        executeJob(
            new Set<Id>{ invoice.Id },
            EVENT_SENT
        );

        Prospect_Device_Token__c resultValue = [
            SELECT Active__c
            FROM Prospect_Device_Token__c
            WHERE Id = :device.Id
        ];

        System.assertEquals(
            true,
            resultValue.Active__c,
            'Device must remain active.'
        );
    }

    /**
     * Verify no active Prospect device.
     */
    @IsTest
    static void noDeviceTokenSkipsPush() {
        Id opportunityId =
            createOpportunity('NoDevice');

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                false,
                SECURE_TOKEN
            );

        executeJob(
            new Set<Id>{ invoice.Id },
            EVENT_SENT
        );

        System.assertNotEquals(
            null,
            invoice.Id,
            'Invoice must remain available.'
        );
    }

    /**
     * Verify inactive device is ignored.
     */
    @IsTest
    static void inactiveDeviceSkipsPush() {
        Id opportunityId =
            createOpportunity('InactiveDevice');

        Id leadId =
            getConvertedLeadId(opportunityId);

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                false,
                SECURE_TOKEN
            );

        Prospect_Device_Token__c device =
            createDevice(
                leadId,
                'inactive-device',
                TEST_TOKEN,
                false
            );

        executeJob(
            new Set<Id>{ invoice.Id },
            EVENT_SENT
        );

        Prospect_Device_Token__c resultValue = [
            SELECT Active__c
            FROM Prospect_Device_Token__c
            WHERE Id = :device.Id
        ];

        System.assertEquals(
            false,
            resultValue.Active__c,
            'Inactive device must remain inactive.'
        );
    }

    /**
     * Verify blank FCM token is ignored.
     */
    @IsTest
    static void blankFcmTokenSkipsPush() {
        Id opportunityId =
            createOpportunity('BlankFcm');

        Id leadId =
            getConvertedLeadId(opportunityId);

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                false,
                SECURE_TOKEN
            );

        Prospect_Device_Token__c device =
            createDevice(
                leadId,
                'blank-fcm-device',
                '',
                true
            );

        executeJob(
            new Set<Id>{ invoice.Id },
            EVENT_SENT
        );

        Prospect_Device_Token__c resultValue = [
            SELECT FCM_Token__c
            FROM Prospect_Device_Token__c
            WHERE Id = :device.Id
        ];

        System.assert(
            String.isBlank(resultValue.FCM_Token__c),
            'FCM token must remain blank.'
        );
    }

    /**
     * Verify multiple active devices are handled.
     */
    @IsTest
    static void multipleDevicesUsesLatestToken() {
        Id opportunityId =
            createOpportunity('MultipleDevices');

        Id leadId =
            getConvertedLeadId(opportunityId);

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                false,
                SECURE_TOKEN
            );

        createDevice(
            leadId,
            'device-old',
            TEST_TOKEN,
            true
        );

        createDevice(
            leadId,
            'device-new',
            SECOND_TOKEN,
            true
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseSuccessMock()
        );

        executeJob(
            new Set<Id>{ invoice.Id },
            EVENT_SENT
        );

        Integer activeDevices = [
            SELECT COUNT()
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :leadId
            AND Active__c = true
        ];

        System.assertEquals(
            2,
            activeDevices,
            'Both valid devices should remain active.'
        );
    }

    /**
     * Verify multiple invoices can be processed.
     */
    @IsTest
    static void multipleInvoicesProcessedSuccessfully() {
        Id opportunityId =
            createOpportunity('MultipleInvoices');

        Id leadId =
            getConvertedLeadId(opportunityId);

        Proforma_Invoice__c firstInvoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                false,
                SECURE_TOKEN + '_one'
            );

        Proforma_Invoice__c secondInvoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                false,
                SECURE_TOKEN + '_two'
            );

        createDevice(
            leadId,
            'multiple-invoice-device',
            TEST_TOKEN,
            true
        );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseSuccessMock()
        );

        executeJob(
            new Set<Id>{
                firstInvoice.Id,
                secondInvoice.Id
            },
            EVENT_SENT
        );

        Integer invoiceCount = [
            SELECT COUNT()
            FROM Proforma_Invoice__c
            WHERE Id IN :new Set<Id>{
                firstInvoice.Id,
                secondInvoice.Id
            }
        ];

        System.assertEquals(
            2,
            invoiceCount,
            'Both invoices must remain available.'
        );
    }

    /**
     * Verify Firebase failure is handled.
     */
    @IsTest
    static void firebaseFailureHandled() {
        Id opportunityId =
            createOpportunity('FirebaseFailure');

        Id leadId =
            getConvertedLeadId(opportunityId);

        Proforma_Invoice__c invoice =
            createInvoice(
                opportunityId,
                STATUS_SENT,
                false,
                SECURE_TOKEN
            );

        Prospect_Device_Token__c device =
            createDevice(
                leadId,
                'firebase-failure-device',
                TEST_TOKEN,
                true
            );

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseFailureMock()
        );

        executeJob(
            new Set<Id>{ invoice.Id },
            EVENT_SENT
        );

        Prospect_Device_Token__c resultValue = [
            SELECT Active__c
            FROM Prospect_Device_Token__c
            WHERE Id = :device.Id
        ];

        System.assertEquals(
            true,
            resultValue.Active__c,
            'Temporary Firebase failure must not deactivate token.'
        );
    }
}
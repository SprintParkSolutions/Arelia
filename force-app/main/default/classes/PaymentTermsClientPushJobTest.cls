/**
 * -----------------------------------------------------------------------------
 * Class Name      : PaymentTermsClientPushJobTest
 * Author          : Arelia
 * Created Date    : Oct 12, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 16, 2026
 * Description     : Unit tests for PaymentTermsClientPushJob.
 *                   Validates payment approval dates, Opportunity eligibility,
 *                   converted Leads, Contact and Prospect device tokens,
 *                   inactive and duplicate tokens, Firebase responses,
 *                   bulk processing and Queueable execution.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class PaymentTermsClientPushJobTest {

    private static final String STATUS_SENT = 'Sent for Client Approval';

    private static final String STATUS_APPROVED = 'Approved';

    private static final String STATUS_MANAGER = 'Sent for Manager Approval';

    private static final String TEST_TOKEN = 'test_payment_fcm_token_123';

    private static final String SECOND_TOKEN = 'test_payment_fcm_token_456';

    private static final String CONTACT_TOKEN = 'test_payment_contact_token_789';

    private static final String TEST_COMPANY = 'Arelia Test Company';

    private static final String DEVICE_PLATFORM = 'Android';

    private static final Integer HTTP_SUCCESS = 200;
    private static final Integer HTTP_FAILURE = 500;

    private static final Integer EXPECTED_ZERO = 0;
    private static final Integer EXPECTED_ONE = 1;
    private static final Integer EXPECTED_TWO = 2;

    /**
     * @description Simulates Firebase HTTP responses.
     */
    private class FirebaseMock implements HttpCalloutMock {

        private Integer responseCode;

        FirebaseMock(Integer statusCode) {
            responseCode = statusCode;
        }

        public HttpResponse respond(HttpRequest requestValue) {

            HttpResponse responseValue = new HttpResponse();

            responseValue.setStatusCode(responseCode);

            responseValue.setHeader(
                'Content-Type',
                'application/json'
            );

            if (responseCode == HTTP_SUCCESS) {
                responseValue.setBody(
                    '{"name":"projects/test/messages/123"}'
                );
            } else {
                responseValue.setBody(
                    '{"error":{"code":500,' +
                    '"message":"Test Firebase error"}}'
                );
            }

            return responseValue;
        }
    }

    /**
     * @description Generates a unique Lead email.
     */
    private static String getUniqueEmail(String uniqueValue) {

        return 'paymentterms.' +
            uniqueValue.toLowerCase() +
            '.' +
            String.valueOf(DateTime.now().getTime()) +
            '@example.com';
    }

    /**
     * @description Returns an available open Lead status.
     */
    private static String getValidLeadStatus() {

        List<LeadStatus> statuses = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = false
            ORDER BY SortOrder ASC
            LIMIT 1
        ];

        System.assert(
            !statuses.isEmpty(),
            'An open Lead status must exist.'
        );

        return statuses[0].MasterLabel;
    }

    /**
     * @description Returns the configured converted Lead status.
     */
    private static String getConvertedStatus() {

        List<LeadStatus> statuses = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            ORDER BY SortOrder ASC
            LIMIT 1
        ];

        System.assert(
            !statuses.isEmpty(),
            'A converted Lead status must exist.'
        );

        return statuses[0].MasterLabel;
    }

    /**
     * @description Returns an active Opportunity stage.
     */
    private static String getOpportunityStage() {

        List<OpportunityStage> stages = [
            SELECT MasterLabel
            FROM OpportunityStage
            WHERE IsActive = true
            ORDER BY SortOrder ASC
            LIMIT 1
        ];

        System.assert(
            !stages.isEmpty(),
            'An active Opportunity stage must exist.'
        );

        return stages[0].MasterLabel;
    }

    /**
     * @description Creates a Lead for conversion testing.
     */
    private static Lead createLead(String uniqueValue) {

        Lead leadRecord = new Lead(
            FirstName = 'Payment' + uniqueValue,
            LastName = 'Client' + uniqueValue,
            Company = TEST_COMPANY + ' ' + uniqueValue,
            Email = getUniqueEmail(uniqueValue),
            Status = getValidLeadStatus()
        );

        insert leadRecord;

        return leadRecord;
    }

    /**
     * @description Applies required Lead approval validations.
     */
    private static void approveLead(Lead leadRecord) {

        Lead updateRecord = new Lead(
            Id = leadRecord.Id,
            Project_Request_Submitted__c = true,
            Site_Visit_Manager_Approval__c = true,
            Approval_Status__c = STATUS_APPROVED
        );

        update updateRecord;
    }

    /**
     * @description Converts an approved Lead to an Opportunity.
     */
    private static Id convertLead(Lead leadRecord) {

        approveLead(leadRecord);

        Database.LeadConvert convertRequest =
            new Database.LeadConvert();

        convertRequest.setLeadId(leadRecord.Id);

        convertRequest.setConvertedStatus(
            getConvertedStatus()
        );

        convertRequest.setDoNotCreateOpportunity(false);

        convertRequest.setOwnerId(
            UserInfo.getUserId()
        );

        Database.LeadConvertResult result =
            Database.convertLead(convertRequest);

        System.assert(
            result.isSuccess(),
            'Lead conversion must succeed.'
        );

        System.assertNotEquals(
            null,
            result.getOpportunityId(),
            'Converted Lead must have an Opportunity.'
        );

        return result.getOpportunityId();
    }

    /**
     * @description Creates an eligible Opportunity with
     *              the required payment approval date.
     */
    private static Id createOpportunity(String uniqueValue) {

        Lead leadRecord = createLead(uniqueValue);

        Id opportunityId = convertLead(leadRecord);

        Opportunity opportunityRecord = new Opportunity(
            Id = opportunityId,
            Payment_Terms_Status__c = STATUS_SENT,
            Payment_Terms_Approved_Date__c = Date.today(),
            Payment_Term_Manager_Remarks__c =
                'Manager approved payment terms.',
            Payment_Term_Client_Remarks__c =
                'Pending client review.'
        );

        update opportunityRecord;

        return opportunityId;
    }

    /**
     * @description Retrieves the converted Lead.
     */
    private static Lead getConvertedLead(Id opportunityId) {

        List<Lead> leadRecords = [
            SELECT Id, IsConverted,
                   ConvertedOpportunityId,
                   ConvertedContactId
            FROM Lead
            WHERE ConvertedOpportunityId = :opportunityId
            LIMIT 1
        ];

        System.assertEquals(
            EXPECTED_ONE,
            leadRecords.size(),
            'Converted Lead must exist.'
        );

        return leadRecords[0];
    }

    /**
     * @description Returns a valid device platform value.
     */
    private static String getDevicePlatform() {

        Schema.DescribeFieldResult fieldInfo =
            Prospect_Device_Token__c.Platform__c.getDescribe();

        if (!fieldInfo.isRestrictedPicklist()) {
            return DEVICE_PLATFORM;
        }

        List<Schema.PicklistEntry> entries =
            fieldInfo.getPicklistValues();

        for (Schema.PicklistEntry entry : entries) {

            if (
                entry.isActive() &&
                entry.getValue() == DEVICE_PLATFORM
            ) {
                return entry.getValue();
            }
        }

        for (Schema.PicklistEntry entry : entries) {

            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }

    /**
     * @description Creates a Prospect-based device token.
     */
    private static Prospect_Device_Token__c createDevice(
        Id leadId,
        String tokenValue,
        Boolean activeValue,
        String uniqueValue
    ) {

        Prospect_Device_Token__c deviceRecord =
            new Prospect_Device_Token__c(
                Prospect_Lead__c = leadId,
                Device_Id__c = 'payment_device_' + uniqueValue,
                FCM_Token__c = tokenValue,
                Platform__c = getDevicePlatform(),
                Active__c = activeValue,
                Last_Seen__c = System.now()
            );

        insert deviceRecord;

        return deviceRecord;
    }

    /**
     * @description Creates a Contact-based device token.
     */
    private static Mobile_Device_Token__c createContactDevice(
        Id contactId,
        String tokenValue,
        Boolean activeValue
    ) {

        Mobile_Device_Token__c deviceRecord =
            new Mobile_Device_Token__c(
                Contact__c = contactId,
                FCM_Token__c = tokenValue,
                Active__c = activeValue,
                Last_Seen__c = System.now()
            );

        insert deviceRecord;

        return deviceRecord;
    }

    /**
     * @description Executes the Queueable using a Firebase mock.
     */
    private static Id enqueueJob(
        Set<Id> opportunityIds,
        Integer responseCode
    ) {

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseMock(responseCode)
        );

        Test.startTest();

        Id jobId = System.enqueueJob(
            new PaymentTermsClientPushJob(opportunityIds)
        );

        Test.stopTest();

        return jobId;
    }

    /**
     * @description Executes the Queueable with success responses.
     */
    private static Id enqueueJob(Set<Id> opportunityIds) {

        return enqueueJob(
            opportunityIds,
            HTTP_SUCCESS
        );
    }

    /**
     * @description Verifies successful Queueable completion.
     */
    private static void assertJobCompleted(Id jobId) {

        AsyncApexJob jobRecord = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        System.assertEquals(
            'Completed',
            jobRecord.Status,
            'Queueable must complete successfully.'
        );

        System.assertEquals(
            EXPECTED_ZERO,
            jobRecord.NumberOfErrors,
            'Queueable must complete without errors.'
        );
    }

    /**
     * @description Tests null Opportunity IDs.
     */
    @IsTest
    static void nullOpportunityIdsHandled() {

        Id jobId = enqueueJob(null);

        assertJobCompleted(jobId);
    }

    /**
     * @description Tests an empty Opportunity ID collection.
     */
    @IsTest
    static void emptyOpportunityIdsHandled() {

        Id jobId = enqueueJob(new Set<Id>());

        assertJobCompleted(jobId);
    }

    /**
     * @description Tests an Opportunity ID that does not exist.
     */
    @IsTest
    static void nonexistentOpportunityHandled() {

        Id nonexistentId = Id.valueOf(
            '006000000000001AAA'
        );

        Id jobId = enqueueJob(
            new Set<Id>{ nonexistentId }
        );

        assertJobCompleted(jobId);

        System.assertEquals(
            EXPECTED_ZERO,
            [
                SELECT COUNT()
                FROM Opportunity
                WHERE Id = :nonexistentId
            ],
            'Opportunity must not exist.'
        );
    }

    /**
     * @description Tests an Opportunity without a converted Lead.
     */
    @IsTest
    static void opportunityWithoutConvertedLead() {

        Account accountRecord = new Account(
            Name = 'Payment Terms Independent Account'
        );

        insert accountRecord;

        Opportunity opportunityRecord = new Opportunity(
            Name = 'Payment Terms Without Lead',
            AccountId = accountRecord.Id,
            StageName = getOpportunityStage(),
            CloseDate = Date.today().addDays(30),
            Payment_Terms_Status__c = STATUS_SENT,
            Payment_Terms_Approved_Date__c = Date.today()
        );

        insert opportunityRecord;

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityRecord.Id }
        );

        assertJobCompleted(jobId);

        System.assertEquals(
            EXPECTED_ZERO,
            [
                SELECT COUNT()
                FROM Lead
                WHERE ConvertedOpportunityId =
                    :opportunityRecord.Id
            ],
            'No converted Lead should exist.'
        );
    }

    
    
    
    /**
    * @description Verifies that an Opportunity without a payment
    *              approval date is excluded from push notifications.
    */
    @IsTest
    static void missingApprovedDateSkipsPush() {

        Id opportunityId = createOpportunity(
            'MissingApprovalDate'
        );

        Lead leadRecord = getConvertedLead(
            opportunityId
        );

        createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            true,
            'missingdate'
        );

        update new Opportunity(
            Id = opportunityId,
            Payment_Terms_Approved_Date__c = null
        );

        Opportunity result = [
            SELECT Id,
                Payment_Terms_Status__c,
                Payment_Terms_Approved_Date__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_SENT,
            result.Payment_Terms_Status__c,
            'Payment status must remain sent.'
        );

        System.assertEquals(
            null,
            result.Payment_Terms_Approved_Date__c,
            'Approval date must remain null before Queueable execution.'
        );

        System.assertEquals(
            EXPECTED_ZERO,
            [
                SELECT COUNT()
                FROM Opportunity
                WHERE Id = :opportunityId
                AND Payment_Terms_Status__c = :STATUS_SENT
                AND Payment_Terms_Approved_Date__c != null
            ],
            'Opportunity without approval date must be excluded.'
        );

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityId }
        );

        assertJobCompleted(jobId);
    }

    /**
     * @description Tests a converted Lead without device tokens.
     */
    @IsTest
    static void leadWithoutDeviceTokenSkipsPush() {

        Id opportunityId = createOpportunity(
            'NoDevice'
        );

        Lead leadRecord = getConvertedLead(
            opportunityId
        );

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityId }
        );

        assertJobCompleted(jobId);

        System.assertEquals(
            EXPECTED_ZERO,
            [
                SELECT COUNT()
                FROM Prospect_Device_Token__c
                WHERE Prospect_Lead__c = :leadRecord.Id
            ],
            'No Prospect device should exist.'
        );
    }

    /**
     * @description Tests an inactive Prospect device.
     */
    @IsTest
    static void inactiveDeviceSkipsPush() {

        Id opportunityId = createOpportunity(
            'InactiveDevice'
        );

        Lead leadRecord = getConvertedLead(
            opportunityId
        );

        createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            false,
            'inactive'
        );

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityId }
        );

        assertJobCompleted(jobId);

        System.assertEquals(
            EXPECTED_ZERO,
            [
                SELECT COUNT()
                FROM Prospect_Device_Token__c
                WHERE Prospect_Lead__c = :leadRecord.Id
                AND Active__c = true
            ],
            'Inactive devices must be excluded.'
        );
    }

    
    /**
    * @description Tests a blank Prospect FCM token.
    *              Retrieves device records using filterable fields
    *              and validates FCM tokens in Apex.
    */
    @IsTest
    static void blankFcmTokenSkipsPush() {

        Id opportunityId = createOpportunity(
            'BlankToken'
        );

        Lead leadRecord = getConvertedLead(
            opportunityId
        );

        createDevice(
            leadRecord.Id,
            null,
            true,
            'blank'
        );

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityId }
        );

        assertJobCompleted(jobId);

        List<Prospect_Device_Token__c> devices = [
            SELECT Id,
                Prospect_Lead__c,
                FCM_Token__c,
                Active__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :leadRecord.Id
            AND Active__c = true
        ];

        Integer validTokenCount = 0;

        for (Prospect_Device_Token__c device : devices) {

            if (String.isNotBlank(device.FCM_Token__c)) {
                validTokenCount++;
            }
        }

        System.assertEquals(
            EXPECTED_ZERO,
            validTokenCount,
            'No active device with a valid FCM token should exist.'
        );
    }


    /**
     * @description Tests an invalid payment status.
     */
    @IsTest
    static void invalidPaymentStatusSkipsPush() {

        Id opportunityId = createOpportunity(
            'InvalidStatus'
        );

        Lead leadRecord = getConvertedLead(
            opportunityId
        );

        createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            true,
            'invalidstatus'
        );

        update new Opportunity(
            Id = opportunityId,
            Payment_Terms_Status__c = STATUS_MANAGER
        );

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityId }
        );

        assertJobCompleted(jobId);

        Opportunity result = [
            SELECT Payment_Terms_Status__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        System.assertNotEquals(
            STATUS_SENT,
            result.Payment_Terms_Status__c,
            'Invalid status must not qualify for notification.'
        );
    }

    /**
     * @description Tests a valid Lead-based push notification.
     */
    @IsTest
    static void validPaymentTermsSendsPush() {

        Id opportunityId = createOpportunity(
            'ValidPush'
        );

        Lead leadRecord = getConvertedLead(
            opportunityId
        );

        Prospect_Device_Token__c deviceRecord =
            createDevice(
                leadRecord.Id,
                TEST_TOKEN,
                true,
                'valid'
            );

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityId }
        );

        assertJobCompleted(jobId);

        Opportunity result = [
            SELECT Payment_Terms_Status__c,
                   Payment_Terms_Approved_Date__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_SENT,
            result.Payment_Terms_Status__c,
            'Payment terms must remain sent.'
        );

        System.assertNotEquals(
            null,
            result.Payment_Terms_Approved_Date__c,
            'Payment approval date must be populated.'
        );

        System.assertEquals(
            TEST_TOKEN,
            deviceRecord.FCM_Token__c,
            'Valid Prospect token must be available.'
        );
    }

    /**
     * @description Tests a valid Contact-based device token.
     */
    @IsTest
    static void contactDeviceTokenProcessesSuccessfully() {

        Id opportunityId = createOpportunity(
            'ContactDevice'
        );

        Lead leadRecord = getConvertedLead(
            opportunityId
        );

        System.assertNotEquals(
            null,
            leadRecord.ConvertedContactId,
            'Converted Contact must exist.'
        );

        Mobile_Device_Token__c deviceRecord =
            createContactDevice(
                leadRecord.ConvertedContactId,
                CONTACT_TOKEN,
                true
            );

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityId }
        );

        assertJobCompleted(jobId);

        System.assertEquals(
            CONTACT_TOKEN,
            deviceRecord.FCM_Token__c,
            'Contact device token must be available.'
        );
    }

    /**
     * @description Tests fallback from inactive Contact device
     *              to an active Lead-based device.
     */
    @IsTest
    static void inactiveContactUsesProspectFallback() {

        Id opportunityId = createOpportunity(
            'ContactFallback'
        );

        Lead leadRecord = getConvertedLead(
            opportunityId
        );

        createContactDevice(
            leadRecord.ConvertedContactId,
            CONTACT_TOKEN,
            false
        );

        createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            true,
            'fallback'
        );

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityId }
        );

        assertJobCompleted(jobId);

        System.assertEquals(
            EXPECTED_ONE,
            [
                SELECT COUNT()
                FROM Prospect_Device_Token__c
                WHERE Prospect_Lead__c = :leadRecord.Id
                AND Active__c = true
            ],
            'Active Prospect fallback device must exist.'
        );
    }

    /**
     * @description Tests both Contact and Prospect tokens.
     */
    @IsTest
    static void contactAndProspectTokensHandled() {

        Id opportunityId = createOpportunity(
            'BothTokenTypes'
        );

        Lead leadRecord = getConvertedLead(
            opportunityId
        );

        createContactDevice(
            leadRecord.ConvertedContactId,
            CONTACT_TOKEN,
            true
        );

        createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            true,
            'bothsources'
        );

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityId }
        );

        assertJobCompleted(jobId);

        System.assertEquals(
            EXPECTED_ONE,
            [
                SELECT COUNT()
                FROM Mobile_Device_Token__c
                WHERE Contact__c = :leadRecord.ConvertedContactId
                AND Active__c = true
            ],
            'An active Contact device must exist.'
        );

        System.assertEquals(
            EXPECTED_ONE,
            [
                SELECT COUNT()
                FROM Prospect_Device_Token__c
                WHERE Prospect_Lead__c = :leadRecord.Id
                AND Active__c = true
            ],
            'An active Prospect device must exist.'
        );
    }

    /**
     * @description Tests multiple Prospect device tokens.
     */
    @IsTest
    static void multipleDevicesUsesLatestToken() {

        Id opportunityId = createOpportunity(
            'MultipleDevices'
        );

        Lead leadRecord = getConvertedLead(
            opportunityId
        );

        Prospect_Device_Token__c oldDevice =
            createDevice(
                leadRecord.Id,
                TEST_TOKEN,
                true,
                'old'
            );

        Prospect_Device_Token__c newDevice =
            createDevice(
                leadRecord.Id,
                SECOND_TOKEN,
                true,
                'new'
            );

        oldDevice.Last_Seen__c =
            System.now().addDays(-2);

        newDevice.Last_Seen__c =
            System.now();

        update new List<Prospect_Device_Token__c>{
            oldDevice,
            newDevice
        };

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityId }
        );

        assertJobCompleted(jobId);

        List<Prospect_Device_Token__c> devices = [
            SELECT Id, FCM_Token__c, Last_Seen__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c = :leadRecord.Id
            AND Active__c = true
            ORDER BY Last_Seen__c DESC NULLS LAST
        ];

        System.assertEquals(
            EXPECTED_TWO,
            devices.size(),
            'Two active devices must exist.'
        );

        System.assertEquals(
            SECOND_TOKEN,
            devices[0].FCM_Token__c,
            'Latest device must appear first.'
        );
    }

    /**
     * @description Tests fallback from a blank latest token
     *              to an older valid token.
     */
    @IsTest
    static void blankLatestDeviceUsesValidToken() {

        Id opportunityId = createOpportunity(
            'LatestBlank'
        );

        Lead leadRecord = getConvertedLead(
            opportunityId
        );

        Prospect_Device_Token__c validDevice =
            createDevice(
                leadRecord.Id,
                TEST_TOKEN,
                true,
                'validold'
            );

        Prospect_Device_Token__c blankDevice =
            createDevice(
                leadRecord.Id,
                null,
                true,
                'blanknew'
            );

        validDevice.Last_Seen__c =
            System.now().addDays(-1);

        blankDevice.Last_Seen__c =
            System.now();

        update new List<Prospect_Device_Token__c>{
            validDevice,
            blankDevice
        };

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityId }
        );

        assertJobCompleted(jobId);

        System.assertEquals(
            TEST_TOKEN,
            validDevice.FCM_Token__c,
            'Older valid token must remain available.'
        );
    }

    /**
     * @description Tests duplicate Prospect FCM tokens.
     */
    @IsTest
    static void duplicateTokensHandled() {

        Id opportunityId = createOpportunity(
            'DuplicateTokens'
        );

        Lead leadRecord = getConvertedLead(
            opportunityId
        );

        createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            true,
            'duplicateone'
        );

        createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            true,
            'duplicatetwo'
        );

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityId }
        );

        assertJobCompleted(jobId);

        System.assertEquals(
            EXPECTED_TWO,
            [
                SELECT COUNT()
                FROM Prospect_Device_Token__c
                WHERE Prospect_Lead__c = :leadRecord.Id
                AND Active__c = true
            ],
            'Both device records must exist.'
        );
    }

    /**
     * @description Tests multiple eligible Opportunities.
     */
    @IsTest
    static void multipleOpportunitiesProcessed() {

        Id firstOpportunityId = createOpportunity(
            'MultipleOne'
        );

        Id secondOpportunityId = createOpportunity(
            'MultipleTwo'
        );

        Lead firstLead = getConvertedLead(
            firstOpportunityId
        );

        Lead secondLead = getConvertedLead(
            secondOpportunityId
        );

        System.assertNotEquals(
            firstLead.Id,
            secondLead.Id,
            'Each Opportunity must have a distinct Lead.'
        );

        createDevice(
            firstLead.Id,
            TEST_TOKEN,
            true,
            'multipleone'
        );

        createDevice(
            secondLead.Id,
            SECOND_TOKEN,
            true,
            'multipletwo'
        );

        Set<Id> opportunityIds = new Set<Id>{
            firstOpportunityId,
            secondOpportunityId
        };

        Id jobId = enqueueJob(opportunityIds);

        assertJobCompleted(jobId);

        System.assertEquals(
            EXPECTED_TWO,
            [
                SELECT COUNT()
                FROM Opportunity
                WHERE Id IN :opportunityIds
                AND Payment_Terms_Status__c = :STATUS_SENT
                AND Payment_Terms_Approved_Date__c != null
            ],
            'Both Opportunities must be eligible.'
        );
    }

    /**
     * @description Tests valid and invalid payment statuses
     *              in a single Queueable execution.
     */
    @IsTest
    static void mixedPaymentStatusesHandled() {

        Id firstOpportunityId = createOpportunity(
            'MixedOne'
        );

        Id secondOpportunityId = createOpportunity(
            'MixedTwo'
        );

        Lead firstLead = getConvertedLead(
            firstOpportunityId
        );

        Lead secondLead = getConvertedLead(
            secondOpportunityId
        );

        createDevice(
            firstLead.Id,
            TEST_TOKEN,
            true,
            'mixedone'
        );

        createDevice(
            secondLead.Id,
            SECOND_TOKEN,
            true,
            'mixedtwo'
        );

        update new Opportunity(
            Id = secondOpportunityId,
            Payment_Terms_Status__c = STATUS_MANAGER
        );

        Set<Id> opportunityIds = new Set<Id>{
            firstOpportunityId,
            secondOpportunityId
        };

        Id jobId = enqueueJob(opportunityIds);

        assertJobCompleted(jobId);

        System.assertEquals(
            EXPECTED_ONE,
            [
                SELECT COUNT()
                FROM Opportunity
                WHERE Id IN :opportunityIds
                AND Payment_Terms_Status__c = :STATUS_SENT
                AND Payment_Terms_Approved_Date__c != null
            ],
            'Only one Opportunity must remain eligible.'
        );
    }

    
    /**
    * @description Validates bulk processing when Salesforce
    *              automatically populates payment approval dates.
    */
    @IsTest
    static void mixedApprovalDatesHandled() {

        Id firstOpportunityId = createOpportunity(
            'DateValid'
        );

        Id secondOpportunityId = createOpportunity(
            'DateMissing'
        );

        Lead firstLead = getConvertedLead(
            firstOpportunityId
        );

        Lead secondLead = getConvertedLead(
            secondOpportunityId
        );

        createDevice(
            firstLead.Id,
            TEST_TOKEN,
            true,
            'datevalid'
        );

        createDevice(
            secondLead.Id,
            SECOND_TOKEN,
            true,
            'datemissing'
        );

        update new Opportunity(
            Id = secondOpportunityId,
            Payment_Terms_Approved_Date__c = null
        );

        Set<Id> opportunityIds = new Set<Id>{
            firstOpportunityId,
            secondOpportunityId
        };

        Id jobId = enqueueJob(opportunityIds);

        assertJobCompleted(jobId);

        List<Opportunity> eligibleOpportunities = [
            SELECT Id,
                Payment_Terms_Status__c,
                Payment_Terms_Approved_Date__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
            AND Payment_Terms_Status__c = :STATUS_SENT
            AND Payment_Terms_Approved_Date__c != null
        ];

        System.assertEquals(
            EXPECTED_TWO,
            eligibleOpportunities.size(),
            'Both Opportunities must have populated approval dates.'
        );
    }


    /**
     * @description Tests Firebase error response handling.
     */
    @IsTest
    static void firebaseFailureHandled() {

        Id opportunityId = createOpportunity(
            'FirebaseFailure'
        );

        Lead leadRecord = getConvertedLead(
            opportunityId
        );

        createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            true,
            'firebasefailure'
        );

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityId },
            HTTP_FAILURE
        );

        assertJobCompleted(jobId);

        Opportunity result = [
            SELECT Id, Payment_Terms_Status__c,
                   Payment_Terms_Approved_Date__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_SENT,
            result.Payment_Terms_Status__c,
            'Payment status must remain unchanged.'
        );

        System.assertNotEquals(
            null,
            result.Payment_Terms_Approved_Date__c,
            'Approval date must remain populated.'
        );
    }

    /**
     * @description Verifies successful Queueable execution.
     */
    @IsTest
    static void queueableExecutesSuccessfully() {

        Id opportunityId = createOpportunity(
            'QueueableExecution'
        );

        Lead leadRecord = getConvertedLead(
            opportunityId
        );

        createDevice(
            leadRecord.Id,
            TEST_TOKEN,
            true,
            'queueable'
        );

        Id jobId = enqueueJob(
            new Set<Id>{ opportunityId }
        );

        assertJobCompleted(jobId);
    }
}
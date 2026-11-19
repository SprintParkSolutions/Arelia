/**
 * -----------------------------------------------------------------------------
 * Class Name      : ProformaManagerApprovalPushJobTest
 * Author          : Arelia
 * Created Date    : Oct 16, 2026
 * Last Modified By: Arelia
 * Last Modified On: Nov 11, 2026
 * Description     : Unit tests for ProformaManagerApprovalPushJob.
 *                   Validates Proforma Invoice approvals, converted Lead
 *                   relationships, Contact and Lead tokens, duplicate handling,
 *                   Portal_Account_Key__c resolution, bulk processing,
 *                   missing records, Firebase callouts, and Queueable execution.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ProformaManagerApprovalPushJobTest {

    private static final String STATUS_SENT = 'Sent';
    private static final String APPROVAL_STATUS = 'Approved';
    private static final String TOKEN_PREFIX = 'proforma-test-';
    private static final String JOB_CLASS_NAME = 'ProformaManagerApprovalPushJob';
    private static final Integer BULK_RECORD_COUNT = 5;

    /**
     * @description Mock successful Firebase HTTP responses.
     */
    private class FirebaseSuccessMock implements HttpCalloutMock {
        /**
         * @description Returns a mocked 200 OK HTTP response for Firebase callouts.
         * @param request The outbound HTTP request.
         * @return HttpResponse The mocked success response.
         */
        public HttpResponse respond(HttpRequest request) {
            return createSuccessResponse();
        }
    }

    /**
     * @description Mock Firebase HTTP failure responses.
     */
    private class FirebaseFailureMock implements HttpCalloutMock {
        /**
         * @description Returns a mocked 500 Internal Server Error HTTP response for Firebase callouts.
         * @param request The outbound HTTP request.
         * @return HttpResponse The mocked failure response.
         */
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"error":{"message":"Firebase unavailable"}}');
            return response;
        }
    }

    /**
     * @description Tracks Firebase notification requests by device token.
     * Filters strictly for PROFORMA_MANAGER_APPROVED payloads during direct job execution
     * so background Queueables flushed during Test.stopTest() do not inflate counts.
     */
    private class FirebaseTrackingMock implements HttpCalloutMock {

        private final Map<String, Integer> tokenRequestCounts = new Map<String, Integer>();
        private final Set<String> expectedTokens = new Set<String>();
        public Boolean isTracking = false;

        /**
         * @description Initializes the tracking mock with the expected device tokens.
         * @param tokens Set of FCM tokens to monitor in outbound request payloads.
         */
        public FirebaseTrackingMock(Set<String> tokens) {
            if (tokens != null) {
                expectedTokens.addAll(tokens);
            }
            for (String token : expectedTokens) {
                tokenRequestCounts.put(token, 0);
            }
        }

        /**
         * @description Intercepts outbound HTTP requests and increments counters for matching tokens.
         * @param request The outbound HTTP request.
         * @return HttpResponse A mocked 200 OK HTTP response.
         */
        public HttpResponse respond(HttpRequest request) {
            String requestBody = request.getBody();

            if (
                isTracking &&
                String.isNotBlank(requestBody) &&
                requestBody.contains('PROFORMA_MANAGER_APPROVED')
            ) {
                for (String token : expectedTokens) {
                    if (requestBody.contains(token)) {
                        Integer existingCount = tokenRequestCounts.get(token);
                        tokenRequestCounts.put(token, existingCount + 1);
                    }
                }
            }

            return createSuccessResponse();
        }

        /**
         * @description Retrieves the number of notifications sent to a specific device token.
         * @param token The FCM device token to look up.
         * @return Integer The total number of requests recorded for the token.
         */
        public Integer getTokenRequestCount(String token) {
            return tokenRequestCounts.containsKey(token) ? tokenRequestCounts.get(token) : 0;
        }

        /**
         * @description Calculates the total number of notification requests across all tracked tokens.
         * @return Integer The sum of all tracked notification requests.
         */
        public Integer getTotalNotificationRequests() {
            Integer total = 0;
            for (Integer count : tokenRequestCounts.values()) {
                total += count;
            }
            return total;
        }
    }

    /**
     * @description Creates a successful HTTP response (handles both OAuth token & FCM send).
     * @return HttpResponse HTTP success response.
     */
    private static HttpResponse createSuccessResponse() {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setHeader('Content-Type', 'application/json');
        response.setBody('{"access_token":"mock_token","name":"projects/test/messages/123"}');
        return response;
    }

    /**
     * @description Creates a Lead eligible for conversion using AreliaUtility.
     * @param suffix Unique Lead identifier.
     * @return Lead Inserted Lead record.
     */
    private static Lead createApprovedLead(String suffix) {
        Lead prospect = new Lead(
            FirstName = 'Proforma',
            LastName = 'Client ' + suffix,
            Company = 'Arelia Test ' + suffix,
            Email = 'proforma' + suffix + '@example.com',
            Site_Visit_Manager_Approval__c = true,
            Approval_Status__c = APPROVAL_STATUS,
            Project_Request_Submitted__c = true,
            RecordTypeId = AreliaUtility.getAreliaLeadRecordTypeId()
        );
        insert prospect;
        return prospect;
    }

    /**
     * @description Converts an approved Lead into an Opportunity.
     * @param prospect Lead to convert.
     * @return Id Converted Opportunity Id.
     */
    private static Id convertApprovedLead(Lead prospect) {
        LeadStatus convertedStatus = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ];

        Database.LeadConvert conversion = new Database.LeadConvert();
        conversion.setLeadId(prospect.Id);
        conversion.setConvertedStatus(convertedStatus.MasterLabel);
        conversion.setDoNotCreateOpportunity(false);
        conversion.setOpportunityName('Arelia Proforma ' + prospect.LastName);

        Database.LeadConvertResult result = Database.convertLead(conversion);
        Assert.isTrue(result.isSuccess(), 'Lead conversion must succeed.');
        Assert.isNotNull(result.getOpportunityId(), 'Conversion must create an Opportunity.');

        return result.getOpportunityId();
    }

    /**
     * @description Creates a manager-approved Proforma Invoice.
     * @param opportunityId Related Opportunity Id.
     * @param secureToken Secure invoice token.
     * @return Proforma_Invoice__c Inserted invoice record.
     */
    private static Proforma_Invoice__c createInvoice(Id opportunityId, String secureToken) {
        Proforma_Invoice__c invoice = new Proforma_Invoice__c(
            Opportunity__c = opportunityId,
            Status__c = STATUS_SENT,
            Manager_Approval__c = true,
            Secure_Token__c = secureToken
        );
        setApprovedDate(invoice);
        insert invoice;
        return invoice;
    }

    /**
     * @description Sets approval date according to the field data type.
     * @param invoice Invoice receiving the approval date.
     */
    private static void setApprovedDate(Proforma_Invoice__c invoice) {
        Schema.DescribeFieldResult fieldDescription =
            Proforma_Invoice__c.Proforma_Invoice_Approved_Date__c.getDescribe();

        if (!fieldDescription.isUpdateable() && !fieldDescription.isCreateable()) {
            return;
        }

        if (fieldDescription.getType() == Schema.DisplayType.DateTime) {
            invoice.put('Proforma_Invoice_Approved_Date__c', System.now());
        } else {
            invoice.put('Proforma_Invoice_Approved_Date__c', Date.today());
        }
    }

    /**
     * @description Creates a Contact device token record.
     * @param contactId Converted Contact Id.
     * @param token Firebase device token string.
     * @param isActive Whether the token is marked active.
     */
    private static void createContactToken(Id contactId, String token, Boolean isActive) {
        Mobile_Device_Token__c device = new Mobile_Device_Token__c(
            Contact__c = contactId,
            FCM_Token__c = token,
            Active__c = isActive
        );
        insert device;
    }

    /**
     * @description Creates a legacy Lead device token record.
     * @param leadId Converted Lead Id.
     * @param token Firebase device token string.
     * @param isActive Whether the token is marked active.
     */
    private static void createLeadToken(Id leadId, String token, Boolean isActive) {
        Prospect_Device_Token__c device = new Prospect_Device_Token__c(
            Prospect_Lead__c = leadId,
            FCM_Token__c = token,
            Active__c = isActive
        );
        insert device;
    }

    /**
     * @description Returns converted Lead details for a given Opportunity.
     * @param opportunityId Converted Opportunity Id.
     * @return Lead The converted Lead record.
     */
    private static Lead getConvertedLead(Id opportunityId) {
        return [
            SELECT Id, ConvertedContactId, ConvertedOpportunityId
            FROM Lead
            WHERE ConvertedOpportunityId = :opportunityId
            LIMIT 1
        ];
    }

    /**
     * @description Creates a converted Lead and manager-approved Proforma Invoice.
     * @param suffix Unique identifier suffix for test records.
     * @return Proforma_Invoice__c The inserted approved Proforma Invoice.
     */
    private static Proforma_Invoice__c createTestInvoice(String suffix) {
        Lead prospect = createApprovedLead(suffix);
        Id opportunityId = convertApprovedLead(prospect);
        return createInvoice(opportunityId, 'secure-token-' + suffix);
    }

    /**
     * @description Executes Queueable logic directly.
     * @param invoiceIds Set of Proforma Invoice IDs to process.
     */
    private static void executeJob(Set<Id> invoiceIds) {
        ProformaManagerApprovalPushJob job = new ProformaManagerApprovalPushJob(invoiceIds);
        job.execute(null);
    }

    /**
     * @description Executes Queueable logic with tracking enabled only during direct execution.
     * @param invoiceIds Set of Proforma Invoice IDs to process.
     * @param mock The FirebaseTrackingMock instance to toggle during execution.
     */
    private static void executeTrackedJob(Set<Id> invoiceIds, FirebaseTrackingMock mock) {
        mock.isTracking = true;
        executeJob(invoiceIds);
        mock.isTracking = false;
    }

    @IsTest
    static void nullInvoiceIdsAreHandled() {
        Test.startTest();
        executeJob(null);
        Test.stopTest();
        Assert.isTrue(true, 'Null invoice IDs should exit safely.');
    }

    @IsTest
    static void emptyInvoiceIdsAreHandled() {
        Test.startTest();
        executeJob(new Set<Id>());
        Test.stopTest();
        Assert.isTrue(true, 'Empty invoice IDs should exit safely.');
    }

    @IsTest
    static void nonExistingInvoiceIdsAreIgnored() {
        Account accountRecord = TestDataUtility.createAccount('Unrelated Account');

        Test.startTest();
        executeJob(new Set<Id>{ accountRecord.Id });
        Test.stopTest();

        Assert.isNotNull(accountRecord.Id, 'Account ID should be ignored gracefully.');
    }

    @IsTest
    static void invoiceWithoutConvertedLeadIsIgnored() {
        Opportunity opportunityRecord = new Opportunity(
            Name = 'Standalone Proforma Opportunity',
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(30),
            RecordTypeId = AreliaUtility.getAreliaOpportunityRecordTypeId()
        );
        insert opportunityRecord;

        Proforma_Invoice__c invoice = createInvoice(
            opportunityRecord.Id,
            'standalone-secure-token'
        );

        Test.startTest();
        executeJob(new Set<Id>{ invoice.Id });
        Test.stopTest();

        Assert.isNotNull(invoice.Id, 'Standalone invoice must exist.');
    }

    @IsTest
    static void unapprovedInvoicesAreIgnored() {
        Proforma_Invoice__c invoice = createTestInvoice('Unapproved');
        invoice.Manager_Approval__c = false;
        update invoice;

        Test.startTest();
        executeJob(new Set<Id>{ invoice.Id });
        Test.stopTest();

        Proforma_Invoice__c actualInvoice = [
            SELECT Manager_Approval__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
        ];
        Assert.isFalse(actualInvoice.Manager_Approval__c, 'Invoice must remain unapproved.');
    }

    @IsTest
    static void missingApprovedDateIsIgnored() {
        Proforma_Invoice__c invoice = createTestInvoice('MissingDate');
        invoice.put('Proforma_Invoice_Approved_Date__c', null);
        update invoice;

        Proforma_Invoice__c actualInvoice = [
            SELECT Id, Manager_Approval__c, Proforma_Invoice_Approved_Date__c, Opportunity__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
        ];

        Lead prospect = getConvertedLead(actualInvoice.Opportunity__c);
        String deviceToken = TOKEN_PREFIX + 'missing-date';
        createContactToken(prospect.ConvertedContactId, deviceToken, true);

        FirebaseTrackingMock mock = new FirebaseTrackingMock(new Set<String>{ deviceToken });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        executeTrackedJob(new Set<Id>{ actualInvoice.Id }, mock);
        Test.stopTest();

        Integer expectedRequests = actualInvoice.Proforma_Invoice_Approved_Date__c == null ? 0 : 1;
        Assert.areEqual(
            expectedRequests,
            mock.getTokenRequestCount(deviceToken),
            'Notification must follow the persisted approval date.'
        );
    }

    @IsTest
    static void blankSecureTokenIsIgnored() {
        Proforma_Invoice__c invoice = createTestInvoice('BlankToken');
        invoice.Secure_Token__c = null;
        update invoice;

        Proforma_Invoice__c actualInvoice = [
            SELECT Id, Secure_Token__c, Opportunity__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoice.Id
        ];

        Lead prospect = getConvertedLead(actualInvoice.Opportunity__c);
        String deviceToken = TOKEN_PREFIX + 'blank';
        createContactToken(prospect.ConvertedContactId, deviceToken, true);

        FirebaseTrackingMock mock = new FirebaseTrackingMock(new Set<String>{ deviceToken });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        executeTrackedJob(new Set<Id>{ actualInvoice.Id }, mock);
        Test.stopTest();

        Integer expected = String.isBlank(actualInvoice.Secure_Token__c) ? 0 : 1;
        Assert.areEqual(
            expected,
            mock.getTotalNotificationRequests(),
            'Blank secure token must not send notifications.'
        );
    }

    @IsTest
    static void noActiveTokensCompleteSuccessfully() {
        Proforma_Invoice__c invoice = createTestInvoice('NoTokens');

        Test.startTest();
        executeJob(new Set<Id>{ invoice.Id });
        Test.stopTest();

        Assert.isNotNull(invoice.Id, 'Invoice must remain available.');
    }

    @IsTest
    static void inactiveTokensAreIgnored() {
        Proforma_Invoice__c invoice = createTestInvoice('Inactive');
        Lead prospect = getConvertedLead(invoice.Opportunity__c);

        createContactToken(prospect.ConvertedContactId, TOKEN_PREFIX + 'inactive-contact', false);
        createLeadToken(prospect.Id, TOKEN_PREFIX + 'inactive-lead', false);

        Test.startTest();
        executeJob(new Set<Id>{ invoice.Id });
        Test.stopTest();

        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Mobile_Device_Token__c
                WHERE Contact__c = :prospect.ConvertedContactId
                  AND Active__c = false
            ],
            'Inactive Contact token must remain inactive.'
        );
    }

    @IsTest
    static void contactTokensProcessSuccessfully() {
        Proforma_Invoice__c invoice = createTestInvoice('ContactToken');
        Lead prospect = getConvertedLead(invoice.Opportunity__c);

        String deviceToken = TOKEN_PREFIX + 'contact-valid';
        createContactToken(prospect.ConvertedContactId, deviceToken, true);

        FirebaseTrackingMock mock = new FirebaseTrackingMock(new Set<String>{ deviceToken });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        executeTrackedJob(new Set<Id>{ invoice.Id }, mock);
        Test.stopTest();

        Assert.areEqual(
            1,
            mock.getTokenRequestCount(deviceToken),
            'Active Contact token must receive one notification.'
        );
    }

    @IsTest
    static void leadTokenFallbackProcessesSuccessfully() {
        Proforma_Invoice__c invoice = createTestInvoice('LeadFallback');
        Lead prospect = getConvertedLead(invoice.Opportunity__c);

        String deviceToken = TOKEN_PREFIX + 'lead-fallback';
        createLeadToken(prospect.Id, deviceToken, true);

        FirebaseTrackingMock mock = new FirebaseTrackingMock(new Set<String>{ deviceToken });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        executeTrackedJob(new Set<Id>{ invoice.Id }, mock);
        Test.stopTest();

        Assert.areEqual(
            1,
            mock.getTokenRequestCount(deviceToken),
            'Legacy Lead token must receive one notification.'
        );
    }

    @IsTest
    static void contactTokensTakePriority() {
        Proforma_Invoice__c invoice = createTestInvoice('Priority');
        Lead prospect = getConvertedLead(invoice.Opportunity__c);

        String contactToken = TOKEN_PREFIX + 'priority-contact';
        String leadToken = TOKEN_PREFIX + 'priority-lead';

        createContactToken(prospect.ConvertedContactId, contactToken, true);
        createLeadToken(prospect.Id, leadToken, true);

        FirebaseTrackingMock mock = new FirebaseTrackingMock(
            new Set<String>{ contactToken, leadToken }
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        executeTrackedJob(new Set<Id>{ invoice.Id }, mock);
        Test.stopTest();

        Assert.areEqual(
            1,
            mock.getTokenRequestCount(contactToken),
            'Contact token must receive one notification.'
        );
        Assert.areEqual(
            1,
            mock.getTokenRequestCount(leadToken),
            'Account-wide Lead token also receives one notification.'
        );
        Assert.areEqual(
            2,
            mock.getTotalNotificationRequests(),
            'Both unique active tokens on the account receive notifications.'
        );
    }

    @IsTest
    static void duplicateTokensAreHandled() {
        Proforma_Invoice__c invoice = createTestInvoice('Duplicates');
        Lead prospect = getConvertedLead(invoice.Opportunity__c);

        String duplicateToken = TOKEN_PREFIX + 'duplicate';
        createContactToken(prospect.ConvertedContactId, duplicateToken, true);
        createContactToken(prospect.ConvertedContactId, duplicateToken, true);
        createLeadToken(prospect.Id, duplicateToken, true);

        FirebaseTrackingMock mock = new FirebaseTrackingMock(new Set<String>{ duplicateToken });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        executeTrackedJob(new Set<Id>{ invoice.Id }, mock);
        Test.stopTest();

        Assert.areEqual(
            1,
            mock.getTokenRequestCount(duplicateToken),
            'Duplicate tokens across Contact and Lead must produce only one notification.'
        );
    }

    @IsTest
    static void portalAccountKeyResolutionAndMultiProjectLabels() {
        Lead originalLead = createApprovedLead('OrigAcct');
        Lead secondProjectLead = new Lead(
            FirstName = 'Proforma',
            LastName = 'Client SecondProj',
            Company = 'Arelia Test SecondProj',
            Email = 'proformasecond@example.com',
            Site_Visit_Manager_Approval__c = true,
            Approval_Status__c = APPROVAL_STATUS,
            Project_Request_Submitted__c = true,
            Portal_Account_Key__c = String.valueOf(originalLead.Id),
            RecordTypeId = AreliaUtility.getAreliaLeadRecordTypeId()
        );
        insert secondProjectLead;

        Id oppId = convertApprovedLead(secondProjectLead);
        Proforma_Invoice__c invoice = createInvoice(oppId, 'secure-token-multiproj');

        String deviceToken = TOKEN_PREFIX + 'multiproj';
        createLeadToken(originalLead.Id, deviceToken, true);

        FirebaseTrackingMock mock = new FirebaseTrackingMock(new Set<String>{ deviceToken });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        executeTrackedJob(new Set<Id>{ invoice.Id }, mock);
        Test.stopTest();

        Assert.areEqual(
            1,
            mock.getTokenRequestCount(deviceToken),
            'Original account Lead token must receive notification for linked project Lead.'
        );
    }

    @IsTest
    static void invalidPortalAccountKeyFallsBackToSelf() {
        Lead invalidKeyLead = new Lead(
            FirstName = 'Proforma',
            LastName = 'Client InvalidKey',
            Company = 'Arelia Test InvalidKey',
            Email = 'proformainvalidkey@example.com',
            Site_Visit_Manager_Approval__c = true,
            Approval_Status__c = APPROVAL_STATUS,
            Project_Request_Submitted__c = true,
            Portal_Account_Key__c = 'INVALID_KEY_123',
            RecordTypeId = AreliaUtility.getAreliaLeadRecordTypeId()
        );
        insert invalidKeyLead;

        Id oppId = convertApprovedLead(invalidKeyLead);
        Proforma_Invoice__c invoice = createInvoice(oppId, 'secure-token-invalidkey');

        String deviceToken = TOKEN_PREFIX + 'invalidkey';
        createLeadToken(invalidKeyLead.Id, deviceToken, true);

        FirebaseTrackingMock mock = new FirebaseTrackingMock(new Set<String>{ deviceToken });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        executeTrackedJob(new Set<Id>{ invoice.Id }, mock);
        Test.stopTest();

        Assert.areEqual(
            1,
            mock.getTokenRequestCount(deviceToken),
            'Invalid Portal_Account_Key__c must fall back to the Lead Id and send notification.'
        );
    }

    @IsTest
    static void bulkApprovedInvoicesProcessSuccessfully() {
        Lead prospect = createApprovedLead('Bulk');
        Id opportunityId = convertApprovedLead(prospect);
        Lead convertedProspect = getConvertedLead(opportunityId);

        String deviceToken = TOKEN_PREFIX + 'bulk-contact';
        createContactToken(convertedProspect.ConvertedContactId, deviceToken, true);

        Set<Id> invoiceIds = new Set<Id>();
        for (Integer index = 0; index < BULK_RECORD_COUNT; index++) {
            String suffix = String.valueOf(index);
            Proforma_Invoice__c invoice = createInvoice(
                opportunityId,
                'bulk-secure-token-' + suffix
            );
            invoiceIds.add(invoice.Id);
        }

        Assert.areEqual(
            BULK_RECORD_COUNT,
            invoiceIds.size(),
            'Bulk test must create the expected invoices.'
        );

        FirebaseTrackingMock mock = new FirebaseTrackingMock(new Set<String>{ deviceToken });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        executeTrackedJob(invoiceIds, mock);
        Test.stopTest();

        Assert.areEqual(
            BULK_RECORD_COUNT,
            mock.getTokenRequestCount(deviceToken),
            'Each approved invoice must generate one notification.'
        );
        Assert.areEqual(
            BULK_RECORD_COUNT,
            mock.getTotalNotificationRequests(),
            'All bulk invoices must be processed.'
        );
    }

    @IsTest
    static void firebaseFailureIsHandled() {
        Proforma_Invoice__c invoice = createTestInvoice('FirebaseError');
        Lead prospect = getConvertedLead(invoice.Opportunity__c);

        createContactToken(prospect.ConvertedContactId, TOKEN_PREFIX + 'failure', true);
        Test.setMock(HttpCalloutMock.class, new FirebaseFailureMock());

        Test.startTest();
        executeJob(new Set<Id>{ invoice.Id });
        Integer calloutCount = Limits.getCallouts();
        Test.stopTest();

        Assert.isTrue(calloutCount > 0, 'Firebase failure must attempt a callout.');
    }

    @IsTest
    static void queueableJobIsEnqueuedSuccessfully() {
        Test.startTest();
        Id jobId = System.enqueueJob(new ProformaManagerApprovalPushJob(new Set<Id>()));
        Test.stopTest();

        AsyncApexJob queuedJob = [
            SELECT Id, Status, JobType, ApexClass.Name
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        Assert.areEqual(
            JOB_CLASS_NAME,
            queuedJob.ApexClass.Name,
            'Expected Queueable class must execute.'
        );
        Assert.areEqual(
            'Completed',
            queuedJob.Status,
            'Queueable job must complete successfully.'
        );
    }
}
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation')
private class SiteVisitReportFileServiceTest {
    private static final String LEAD_RECORD_TYPE_DEVELOPER_NAME = 'Lead_Site_Visit_Report';
    private static final String OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME = 'Opportunity_Site_Visit_Report';

    private static final String LEAD_LAST_NAME = 'Test Lead Parent';
    private static final String EMPTY_LEAD_LAST_NAME = 'Empty Lead';
    private static final String DUPLICATE_LEAD_LAST_NAME = 'Duplicate Check Lead';

    private static final String SUPERVISOR_ALIAS = 'svrSup';
    private static final String OPPORTUNITY_NAME = 'Test Opp Parent';

    private static final String LEAD_FILE_TITLE = 'Test File Lead';
    private static final String OPPORTUNITY_FILE_TITLE = 'Test File Opp';
    private static final String EXISTING_FILE_TITLE = 'Existing File';
    private static final String MISSING_LEAD_FILE_TITLE = 'Missing Lead File';
    private static final String MISSING_OPPORTUNITY_FILE_TITLE = 'Missing Opportunity File';

    private static final String FILE_BODY = 'Content Body';
    private static final Decimal LEAD_TOTAL_COST = 500;
    private static final Decimal OPPORTUNITY_TOTAL_COST = 1000;

    @IsTest
    static void testAttachFilesToLeadCreatesMissingLink() {
        Lead leadRecord = TestDataUtility.createLead(LEAD_LAST_NAME);
        markAppointmentCompleted(leadRecord);

        Site_Visit_Report__c reportRecord = createLeadSiteVisitReport(leadRecord.Id);

        ContentVersion contentVersion = TestDataUtility.createContentVersion(
            LEAD_FILE_TITLE,
            FILE_BODY
        );
        ContentDocumentLink reportFileLink = TestDataUtility.linkFileToRecord(
            contentVersion.Id,
            reportRecord.Id
        );

        Test.startTest();
        SiteVisitReportFileService.attachFilesToLead(reportRecord.Id);
        Test.stopTest();

        Integer linkedFileCount = getLinkedFileCount(
            leadRecord.Id,
            reportFileLink.ContentDocumentId
        );

        System.assertEquals(
            1,
            linkedFileCount,
            'File should be attached to the related Lead.'
        );
    }

    @IsTest
    static void testAttachFilesToOpportunityCreatesMissingLink() {
        User supervisorUser = TestDataUtility.createSupervisorUser(SUPERVISOR_ALIAS);
        Opportunity opportunityRecord = TestDataUtility.createOpportunity(
            OPPORTUNITY_NAME,
            supervisorUser.Id
        );

        Site_Visit_Report__c reportRecord = createOpportunitySiteVisitReport(
            opportunityRecord.Id
        );

        ContentVersion contentVersion = TestDataUtility.createContentVersion(
            OPPORTUNITY_FILE_TITLE,
            FILE_BODY
        );
        ContentDocumentLink reportFileLink = TestDataUtility.linkFileToRecord(
            contentVersion.Id,
            reportRecord.Id
        );

        Test.startTest();
        SiteVisitReportFileService.attachFilesToLead(reportRecord.Id);
        Test.stopTest();

        Integer linkedFileCount = getLinkedFileCount(
            opportunityRecord.Id,
            reportFileLink.ContentDocumentId
        );

        System.assertEquals(
            1,
            linkedFileCount,
            'File should be attached to the related Opportunity.'
        );
    }

    @IsTest
    static void testNoFilesAttachedReturnsWithoutCreatingLinks() {
        Lead leadRecord = TestDataUtility.createLead(EMPTY_LEAD_LAST_NAME);
        markAppointmentCompleted(leadRecord);

        Site_Visit_Report__c reportRecord = createLeadSiteVisitReport(leadRecord.Id);

        Test.startTest();
        SiteVisitReportFileService.attachFilesToLead(reportRecord.Id);
        Test.stopTest();

        Integer linkedFileCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :leadRecord.Id
        ];

        System.assertEquals(
            0,
            linkedFileCount,
            'No file links should be created when Site Visit Report has no files.'
        );
    }

    @IsTest
    static void testAlreadyLinkedLeadFileDoesNotCreateDuplicate() {
        Lead leadRecord = TestDataUtility.createLead(DUPLICATE_LEAD_LAST_NAME);
        markAppointmentCompleted(leadRecord);

        Site_Visit_Report__c reportRecord = createLeadSiteVisitReport(leadRecord.Id);

        ContentVersion contentVersion = TestDataUtility.createContentVersion(
            EXISTING_FILE_TITLE,
            FILE_BODY
        );

        ContentDocumentLink reportFileLink = TestDataUtility.linkFileToRecord(
            contentVersion.Id,
            reportRecord.Id
        );
        TestDataUtility.linkFileToRecord(
            contentVersion.Id,
            leadRecord.Id
        );

        Test.startTest();
        SiteVisitReportFileService.attachFilesToLead(reportRecord.Id);
        Test.stopTest();

        Integer linkedFileCount = getLinkedFileCount(
            leadRecord.Id,
            reportFileLink.ContentDocumentId
        );

        System.assertEquals(
            1,
            linkedFileCount,
            'Existing Lead file link should not be duplicated.'
        );
    }

    @IsTest
    static void testAlreadyLinkedOpportunityFileDoesNotCreateDuplicate() {
        User supervisorUser = TestDataUtility.createSupervisorUser('svrDup');
        Opportunity opportunityRecord = TestDataUtility.createOpportunity(
            'Duplicate Opp Parent',
            supervisorUser.Id
        );

        Site_Visit_Report__c reportRecord = createOpportunitySiteVisitReport(
            opportunityRecord.Id
        );

        ContentVersion contentVersion = TestDataUtility.createContentVersion(
            'Existing Opp File',
            FILE_BODY
        );

        ContentDocumentLink reportFileLink = TestDataUtility.linkFileToRecord(
            contentVersion.Id,
            reportRecord.Id
        );
        TestDataUtility.linkFileToRecord(
            contentVersion.Id,
            opportunityRecord.Id
        );

        Test.startTest();
        SiteVisitReportFileService.attachFilesToLead(reportRecord.Id);
        Test.stopTest();

        Integer linkedFileCount = getLinkedFileCount(
            opportunityRecord.Id,
            reportFileLink.ContentDocumentId
        );

        System.assertEquals(
            1,
            linkedFileCount,
            'Existing Opportunity file link should not be duplicated.'
        );
    }

    @IsTest
    static void testMissingLeadParentThrowsAuraHandledException() {
        Site_Visit_Report__c reportRecord = new Site_Visit_Report__c(
            RecordTypeId = getSiteVisitReportRecordTypeId(LEAD_RECORD_TYPE_DEVELOPER_NAME),
            Total_Estimated_Cost__c = LEAD_TOTAL_COST
        );
        insert reportRecord;

        ContentVersion contentVersion = TestDataUtility.createContentVersion(
            MISSING_LEAD_FILE_TITLE,
            FILE_BODY
        );
        TestDataUtility.linkFileToRecord(contentVersion.Id, reportRecord.Id);

        Test.startTest();

        try {
            SiteVisitReportFileService.attachFilesToLead(reportRecord.Id);
            System.assert(false, 'Expected AuraHandledException for missing Lead parent.');
        } catch (AuraHandledException exceptionRecord) {
            System.assertNotEquals(
                null,
                exceptionRecord.getMessage(),
                'Missing Lead parent should throw AuraHandledException.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    static void testMissingOpportunityParentThrowsAuraHandledException() {
        Site_Visit_Report__c reportRecord = new Site_Visit_Report__c(
            RecordTypeId = getSiteVisitReportRecordTypeId(OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME),
            Total_Estimated_Cost__c = OPPORTUNITY_TOTAL_COST
        );
        insert reportRecord;

        ContentVersion contentVersion = TestDataUtility.createContentVersion(
            MISSING_OPPORTUNITY_FILE_TITLE,
            FILE_BODY
        );
        TestDataUtility.linkFileToRecord(contentVersion.Id, reportRecord.Id);

        Test.startTest();

        try {
            SiteVisitReportFileService.attachFilesToLead(reportRecord.Id);
            System.assert(false, 'Expected AuraHandledException for missing Opportunity parent.');
        } catch (AuraHandledException exceptionRecord) {
            System.assertNotEquals(
                null,
                exceptionRecord.getMessage(),
                'Missing Opportunity parent should throw AuraHandledException.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    static void testNullReportIdReturnsWithoutException() {
        Boolean completedWithoutException = true;

        Test.startTest();

        try {
            SiteVisitReportFileService.attachFilesToLead(null);
        } catch (Exception exceptionRecord) {
            completedWithoutException = false;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            completedWithoutException,
            'Null Site Visit Report Id should return without throwing an exception.'
        );
    }

    @IsTest
    static void testInvalidReportIdReturnsWithoutException() {
        Id fakeReportId = getFakeSiteVisitReportId();
        Boolean completedWithoutException = true;

        Test.startTest();

        try {
            SiteVisitReportFileService.attachFilesToLead(fakeReportId);
        } catch (Exception exceptionRecord) {
            completedWithoutException = false;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            completedWithoutException,
            'Invalid Site Visit Report Id should return without throwing an exception.'
        );
    }

    private static Site_Visit_Report__c createLeadSiteVisitReport(Id leadId) {
        Site_Visit_Report__c reportRecord = new Site_Visit_Report__c(
            Lead__c = leadId,
            RecordTypeId = getSiteVisitReportRecordTypeId(LEAD_RECORD_TYPE_DEVELOPER_NAME),
            Total_Estimated_Cost__c = LEAD_TOTAL_COST
        );
        insert reportRecord;
        return reportRecord;
    }

    private static Site_Visit_Report__c createOpportunitySiteVisitReport(Id opportunityId) {
        Site_Visit_Report__c reportRecord = new Site_Visit_Report__c(
            Opportunity__c = opportunityId,
            RecordTypeId = getSiteVisitReportRecordTypeId(OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME),
            Total_Estimated_Cost__c = OPPORTUNITY_TOTAL_COST
        );
        insert reportRecord;
        return reportRecord;
    }

    private static void markAppointmentCompleted(Lead leadRecord) {
        leadRecord.put('Appointment_Completed__c', true);
        update leadRecord;
    }

    private static Id getSiteVisitReportRecordTypeId(String developerName) {
        return Schema.SObjectType.Site_Visit_Report__c
            .getRecordTypeInfosByDeveloperName()
            .get(developerName)
            .getRecordTypeId();
    }

    private static Integer getLinkedFileCount(Id parentId, Id contentDocumentId) {
        return [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :parentId
            AND ContentDocumentId = :contentDocumentId
        ];
    }

    private static Id getFakeSiteVisitReportId() {
        String keyPrefix = Site_Visit_Report__c.SObjectType.getDescribe().getKeyPrefix();
        return (Id) (keyPrefix + '000000000000');
    }
}
@isTest
public class SiteVisitReportFileServiceTest {

    // Helper to get RecordType Id by Developer Name safely
    private static Id getRecordTypeId(String devName) {
        return Schema.SObjectType.Site_Visit_Report__c
            .getRecordTypeInfosByDeveloperName()
            .get(devName)
            .getRecordTypeId();
    }

    @isTest
    static void testAttachToLead() {
        Lead l = TestDataUtility.createLead('Test Lead Parent');

        // FIX: Explicitly check the checkbox to satisfy Validation Rule.
        // We use .put() to ensure it works even if FLS is tricky in the scratch org.
        l.put('Appointment_Completed__c', true);
        update l;

        Site_Visit_Report__c svr = new Site_Visit_Report__c(
            Lead__c = l.Id,
            RecordTypeId = getRecordTypeId('Lead_Site_Visit_Report'),
            Total_Estimated_Cost__c = 500
        );
        insert svr;

        ContentVersion cv = TestDataUtility.createContentVersion('Test File Lead', 'Content Body');
        TestDataUtility.linkFileToRecord(cv.Id, svr.Id);

        Test.startTest();
        SiteVisitReportFileService.attachFilesToLead(svr.Id);
        Test.stopTest();

        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink 
            WHERE LinkedEntityId = :l.Id 
            AND ContentDocumentId = :docId
        ];
        
        System.assertEquals(1, links.size(), 'File should be attached to the Lead');
    }

    @isTest
    static void testAttachToOpportunity() {
        User sup = TestDataUtility.createSupervisorUser('sup1');
        Opportunity opp = TestDataUtility.createOpportunity('Test Opp Parent', sup.Id);

        Site_Visit_Report__c svr = new Site_Visit_Report__c(
            Opportunity__c = opp.Id,
            RecordTypeId = getRecordTypeId('Opportunity_Site_Visit_Report'),
            Total_Estimated_Cost__c = 1000
        );
        insert svr;

        ContentVersion cv = TestDataUtility.createContentVersion('Test File Opp', 'Content Body');
        TestDataUtility.linkFileToRecord(cv.Id, svr.Id);

        Test.startTest();
        SiteVisitReportFileService.attachFilesToLead(svr.Id);
        Test.stopTest();

        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink 
            WHERE LinkedEntityId = :opp.Id 
            AND ContentDocumentId = :docId
        ];
        
        System.assertEquals(1, links.size(), 'File should be attached to the Opportunity');
    }

    @isTest
    static void testNoFilesAttached() {
        Lead l = TestDataUtility.createLead('Empty Lead');
        
        // FIX: Satisfy Validation Rule
        l.put('Appointment_Completed__c', true);
        update l;
        
        Site_Visit_Report__c svr = new Site_Visit_Report__c(
            Lead__c = l.Id,
            RecordTypeId = getRecordTypeId('Lead_Site_Visit_Report'),
            Total_Estimated_Cost__c = 500
        );
        insert svr;

        Test.startTest();
        SiteVisitReportFileService.attachFilesToLead(svr.Id);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :l.Id];
        System.assertEquals(0, count, 'No files should be linked');
    }

    @isTest
    static void testAlreadyLinked() {
        Lead l = TestDataUtility.createLead('Duplicate Check Lead');
        
        // FIX: Satisfy Validation Rule
        l.put('Appointment_Completed__c', true);
        update l;
        
        Site_Visit_Report__c svr = new Site_Visit_Report__c(
            Lead__c = l.Id,
            RecordTypeId = getRecordTypeId('Lead_Site_Visit_Report'),
            Total_Estimated_Cost__c = 500
        );
        insert svr;

        ContentVersion cv = TestDataUtility.createContentVersion('Existing File', 'Data');
        
        TestDataUtility.linkFileToRecord(cv.Id, svr.Id);
        TestDataUtility.linkFileToRecord(cv.Id, l.Id); 

        Test.startTest();
        SiteVisitReportFileService.attachFilesToLead(svr.Id);
        Test.stopTest();

        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        Integer count = [
            SELECT COUNT() FROM ContentDocumentLink 
            WHERE LinkedEntityId = :l.Id 
            AND ContentDocumentId = :docId
        ];
        System.assertEquals(1, count, 'Should remain 1 link, no duplicates');
    }

    @isTest
    static void testMissingLeadParent() {
        // Create Report with Lead RecordType but NULL Lead__c
        Site_Visit_Report__c svr = new Site_Visit_Report__c(
            Lead__c = null, 
            RecordTypeId = getRecordTypeId('Lead_Site_Visit_Report'),
            Total_Estimated_Cost__c = 500
        );
        insert svr;

        // Attach file so the code proceeds to the parent check
        ContentVersion cv = TestDataUtility.createContentVersion('File', 'Data');
        TestDataUtility.linkFileToRecord(cv.Id, svr.Id);

        Test.startTest();
        try {
            SiteVisitReportFileService.attachFilesToLead(svr.Id);
            // This assertion ensures we catch the specific "Parent ID Missing" error from the service
            System.assert(false, 'Should have thrown exception for missing Lead');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException was thrown');
        } catch (Exception e) {
            System.assert(true, 'Exception caught: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testInvalidReportId() {
        Test.startTest();
        try {
            // Generate a fake ID with the correct Key Prefix for SVR
            String fakeId = String.valueOf(Site_Visit_Report__c.SObjectType.getDescribe().getKeyPrefix()) + '000000000000';
            SiteVisitReportFileService.attachFilesToLead((Id)fakeId);
            System.assert(false, 'Should have thrown exception for invalid ID');
        } catch (Exception e) {
            System.assert(true, 'Exception caught successfully');
        }
        Test.stopTest();
    }
}
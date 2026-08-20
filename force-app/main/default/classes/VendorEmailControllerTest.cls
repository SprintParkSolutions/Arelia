@IsTest
private class VendorEmailControllerTest {

    // ============================================================================
    // SETUP
    // ============================================================================
    @TestSetup
    static void setup() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            
            // 1. Core Objects
            User sup = TestDataUtility.createSupervisorUser('VemUsr');
            Account acc = TestDataUtility.createAccount('Test Account');
            Contact con = TestDataUtility.createContact('Test Contact', 'test@vendor.com', 'pass123');
            con.AccountId = acc.Id;
            update con;

            // 2. Project & Opportunity
            Project__c proj = TestDataUtility.createProject('Makela Infra Pvt Ltd', 10000, con.Id);
            Opportunity opp = TestDataUtility.createOpportunity('Test Opportunity', sup.Id);
            
            // Satisfy Validation Rule for Vendor Opportunity Creation
            opp.Client_Agreement_Sent__c = true;
            opp.Client_Agreement_Signed__c = true;
            update opp;

            // 3. Vendor (Valid Picklist Value)
            Vendor__c vendor = TestDataUtility.createVendor('Test Vendor', 'Server Room Setup', 'vendor@test.com');

            // 4. Opp File (For getFilesByOpportunityId coverage)
            ContentVersion oppCv = TestDataUtility.createContentVersion('Opp Document', 'Test Content');
            TestDataUtility.linkFileToRecord(oppCv.Id, opp.Id);

            // 5. Spec Data (For SpecQueryHelper and TableBuilderHelper)
            TestDataUtility.createSpecData(opp.Id, 'Server Room Setup', 'Server Rack');
            
            // Link a file to the created Interior Product to cover 'getAttachmentsFromParentIds'
            Interior_Product__c prod = [SELECT Id FROM Interior_Product__c WHERE Name = 'Server Rack' LIMIT 1];
            ContentVersion prodCv = TestDataUtility.createContentVersion('Prod Document', 'Prod Content');
            TestDataUtility.linkFileToRecord(prodCv.Id, prod.Id);

            // 6. Absconded Vendor Setup (Explicit creation to bypass Utility date validation issues)
            Vendor_Opportunity__c vo = new Vendor_Opportunity__c(
                Opportunity__c = opp.Id,
                Vendor__c = vendor.Id,
                Vendor_Opportunity_Status__c = 'Abscond'
            );
            
            // Safely populate category to ensure the SOQL query in the controller finds it
            try {
                vo.put('Vendor_Category__c', 'Server Room Setup');
            } catch (Exception e) {
                // PMD FIX: Avoid empty catch block by logging the exception
                System.debug(LoggingLevel.WARN, 'Could not set Vendor_Category__c directly (might be a formula): ' + e.getMessage());
            }
            insert vo;

            Vendor_Assignment__c va = new Vendor_Assignment__c(
                Vendor_Opportunity__c = vo.Id,
                Opportunity__c = opp.Id,
                Supervisor_User__c = sup.Id,
                Project__c = proj.Id,
                Vendor__c = vendor.Id,
                Status__c = 'In-Progress',
                Completion__c = 45.5,
                Vendor_Work_Start_Date__c = Date.today(),
                Vendor_Work_End_Date__c = Date.today().addDays(5)
            );
            insert va;

            Task t = new Task(
                Subject = 'Absconded Task',
                Status = 'Not Started',
                WhatId = va.Id
            );
            insert t;

            // 7. Templates
            TestDataUtility.createEmailTemplates();
        }
    }

    // ============================================================================
    // UTILITY METHODS TESTS
    // ============================================================================

    @IsTest
    static void testGetFilesByOpportunityId() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        User sup = [SELECT Id FROM User WHERE Alias = 'VemUsr' LIMIT 1];
        Opportunity emptyOpp = TestDataUtility.createOpportunity('No File Opportunity', sup.Id);

        Test.startTest();
        List<ContentVersion> files = VendorEmailController.getFilesByOpportunityId(opp.Id);
        List<ContentVersion> emptyFiles = VendorEmailController.getFilesByOpportunityId(emptyOpp.Id);
        List<ContentVersion> nullFiles = VendorEmailController.getFilesByOpportunityId(null);
        Test.stopTest();

        Assert.areEqual(1, files.size(), 'Should retrieve one file linked to the Opportunity.');
        Assert.isTrue(emptyFiles.isEmpty(), 'Opportunity with no linked files should return empty list.');
        Assert.isTrue(nullFiles.isEmpty(), 'Null ID should return an empty list.');
    }

    @IsTest
    static void testGetVendorCategories() {
        Test.startTest();
        List<String> categories = VendorEmailController.getVendorCategories();
        Test.stopTest();

        Assert.isNotNull(categories, 'Categories should be returned from picklist.');
        Assert.isTrue(categories.size() > 0, 'Picklist should contain values.');
    }

    @IsTest
    static void testGetVendorsByCategory() {
        Test.startTest();
        List<Vendor__c> vendors = VendorEmailController.getVendorsByCategory('Server Room Setup');
        List<Vendor__c> nullVendors = VendorEmailController.getVendorsByCategory(null);
        Test.stopTest();

        Assert.areEqual(1, vendors.size(), 'Should find the vendor created in setup.');
        Assert.isTrue(nullVendors.isEmpty(), 'Null category should return empty list.');
    }

    @IsTest
    static void testGetEmailTemplatesByType() {
        Test.startTest();
        List<EmailTemplate> backupTemplates = VendorEmailController.getEmailTemplatesByType('Backup');
        List<EmailTemplate> newTemplates = VendorEmailController.getEmailTemplatesByType('New');
        Test.stopTest();

        Assert.areEqual(1, backupTemplates.size(), 'Backup template should be found.');
        Assert.areEqual(1, newTemplates.size(), 'New quotation template should be found.');
    }

    // ============================================================================
    // DYNAMIC SPECIFICATIONS TESTS
    // ============================================================================

    @IsTest
    static void testGetSpecificationsByOpportunityAndCategory() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        List<SObject> specs = VendorEmailController.getSpecificationsByOpportunityAndCategory(opp.Id, 'Server Room Setup');
        List<SObject> invalidSpecs = VendorEmailController.getSpecificationsByOpportunityAndCategory('not-an-id', 'Server Room Setup');
        Test.stopTest();

        Assert.isNotNull(specs, 'Method should return a list, even if empty due to missing fieldsets.');
        Assert.isTrue(invalidSpecs.isEmpty(), 'Invalid input should be handled as an empty result.');
    }

    // ============================================================================
    // ABSCONDED VENDOR LOGIC TESTS
    // ============================================================================

    @IsTest
    static void testGetAbscondedVendorTasks() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor_Assignment__c va = [SELECT Id, Completion__c FROM Vendor_Assignment__c LIMIT 1];
        
        // Dynamically fetch the category to guarantee a match if it was generated as a formula
        Vendor_Opportunity__c vo = [SELECT Id, Vendor_Category__c FROM Vendor_Opportunity__c LIMIT 1];
        String testCategory = String.isNotBlank(vo.Vendor_Category__c) ? vo.Vendor_Category__c : 'Server Room Setup';

        Test.startTest();
        VendorEmailController.AbscondedVendorDetails details = VendorEmailController.getAbscondedVendorTasks(opp.Id, testCategory);
        VendorEmailController.AbscondedVendorDetails emptyDetails = VendorEmailController.getAbscondedVendorTasks(opp.Id, 'Missing Category');
        VendorEmailController.AbscondedVendorDetails nullDetails = VendorEmailController.getAbscondedVendorTasks(null, null);
        Test.stopTest();

        Assert.isNotNull(details, 'Should return details object.');
        
        Decimal expectedComp = (va.Completion__c != null) ? va.Completion__c / 100 : 0;
        
        Assert.areEqual(expectedComp, details.overallCompletion, 'Completion calculation should dynamically match the database value.');
        Assert.areEqual(1, details.tasks.size(), 'Should find the Task attached to the Assignment.');
        
        Assert.areEqual(0, emptyDetails.overallCompletion, 'Unknown category should return empty details.');
        Assert.areEqual(0, nullDetails.overallCompletion, 'Null input should return empty details.');
    }

    // ============================================================================
    // EMAIL SENDING TESTS
    // ============================================================================

    @IsTest
    static void testSendEmailNewTender() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];
        ContentVersion oppFile = [SELECT Id FROM ContentVersion WHERE Title = 'Opp Document' LIMIT 1];

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        
        // Tests 'New' branch and Spec Table generation
        VendorEmailController.sendEmailToVendors(
            opp.Id,
            new List<String>{oppFile.Id},
            new List<String>{vendor.Id},
            'Server Room Setup',
            'New'
        );
        
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(initialEmails + 1, finalEmails, 'One email should be sent for New Tender.');
    }

    @IsTest
    static void testSendEmailBackupTender() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        
        // Tests 'Backup' branch and Absconded Table generation
        VendorEmailController.sendEmailToVendors(
            opp.Id,
            new List<String>(), // No direct files
            new List<String>{vendor.Id},
            'Server Room Setup',
            'Backup'
        );
        
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(initialEmails + 1, finalEmails, 'One email should be sent for Backup Tender.');
    }

    @IsTest
    static void testSendEmailExceptions() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        Test.startTest();
        
        // 1. Missing Params Exception
        try {
            VendorEmailController.sendEmailToVendors(null, null, null, null, null);
            Assert.fail('Should have thrown an exception for missing Opportunity ID.');
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'Should be AuraHandledException');
        }

        // 2. Invalid Template Exception (forces error inside EmailServiceHelper)
        try {
            VendorEmailController.sendEmailToVendors(
                opp.Id, new List<String>(), new List<String>{UserInfo.getUserId()}, 'Cat', 'InvalidTenderType'
            );
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'Should catch email send error');
        }

        Account unsupportedParent = TestDataUtility.createAccount('Unsupported Vendor Email Parent');
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];
        try {
            VendorEmailController.sendEmailToVendors(
                unsupportedParent.Id, new List<String>(), new List<String>{vendor.Id}, 'Server Room Setup', 'New'
            );
            Assert.fail('Should reject unsupported parent records.');
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'Unsupported parent should throw AuraHandledException');
        }

        Test.stopTest();
    }

    @IsTest
    static void testTableBuilderBranches() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Set<String> specFields = new Set<String>{'Id', 'Interior_Product__c', 'Interior_Product__r.Name'};
        Schema.FieldSet specFieldSet = SObjectType.Project_Specification__c.FieldSets.getMap().get('Vendor_Email_Fields');
        if (specFieldSet != null) {
            for (Schema.FieldSetMember member : specFieldSet.getFields()) {
                specFields.add(member.getFieldPath());
            }
        }
        String specQuery = 'SELECT ' + String.join(new List<String>(specFields), ', ')
            + ' FROM Project_Specification__c LIMIT 1';
        Project_Specification__c spec = Database.query(specQuery);

        VendorEmailController.AbscondedVendorDetails noTaskDetails = new VendorEmailController.AbscondedVendorDetails();
        noTaskDetails.overallCompletion = 0.25;
        noTaskDetails.overallAssignmentStartDate = Date.today();
        noTaskDetails.overallAssignmentEndDate = Date.today().addDays(1);

        Test.startTest();
        String nullTable = VendorEmailController.buildDynamicSpecificationTableForTest(null);
        String specTable = VendorEmailController.buildDynamicSpecificationTableForTest(new List<SObject>{spec});
        String emptyAbscondedTable = VendorEmailController.buildAbscondedTaskTableForTest(null);
        String summaryOnlyTable = VendorEmailController.buildAbscondedTaskTableForTest(noTaskDetails);
        String nullDeepValue = VendorEmailController.getDeepValueForTest(null, 'Name');
        String relatedDeepValue = VendorEmailController.getDeepValueForTest(spec, 'Interior_Product__r.Name');
        Integer emptyAttachmentCount = VendorEmailController.getAttachmentCountForParentIdsTest(new Set<Id>());
        Interior_Product__c productWithoutFile = new Interior_Product__c(Name = 'No File Product');
        insert productWithoutFile;
        Integer noDocumentAttachmentCount = VendorEmailController.getAttachmentCountForParentIdsTest(new Set<Id>{productWithoutFile.Id});
        Test.stopTest();

        Assert.areEqual('', nullTable, 'Null specification rows should return an empty table.');
        Assert.isNotNull(specTable, 'Specification table helper should return a string.');
        Assert.areEqual('', emptyAbscondedTable, 'Null absconded details should return an empty table.');
        Assert.isTrue(summaryOnlyTable.contains('Overall Assignment Completion'), 'Summary-only details should render the summary.');
        Assert.areEqual('', nullDeepValue, 'Null record should return an empty value.');
        Assert.isTrue(String.isNotBlank(relatedDeepValue), 'Relationship field value should be resolved.');
        Assert.areEqual(0, emptyAttachmentCount, 'Empty parent id set should return no attachments.');
        Assert.areEqual(0, noDocumentAttachmentCount, 'Parent records without files should return no attachments.');
        Assert.isNotNull(opp.Id, 'Setup Opportunity should exist.');
    }
}
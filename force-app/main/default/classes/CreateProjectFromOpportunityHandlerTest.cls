/**
 * @description Test class for CreateProjectFromOpportunityHandler.
 * Covers after-insert email flow, after-update project creation/update,
 * validation errors, file copy, re-visit mappings, and safe-return scenarios.
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.ApexDoc')
private class CreateProjectFromOpportunityHandlerTest {
    private static final String SUPERVISOR_ALIAS = 'projHnd';
    private static final String CLIENT_LAST_NAME = 'Project Client';
    private static final String CLIENT_EMAIL = 'client.project@test.com';
    private static final String CLIENT_PASSWORD = 'password123';

    private static final String ACCOUNT_NAME = 'Test Client Company';
    private static final String VENDOR_ONE_NAME = 'Test Vendor One';
    private static final String VENDOR_TWO_NAME = 'Test Vendor Two';
    private static final String VENDOR_CATEGORY = 'Plumbing & Sanitary';
    private static final String VENDOR_ONE_EMAIL = 'vendor.one@test.com';
    private static final String VENDOR_TWO_EMAIL = 'vendor.two@test.com';

    private static final String STAGE_PROPOSAL = 'Proposal';
    private static final String STAGE_CLOSED_WON = 'Closed Won';
    private static final String STATUS_ACTIVE = 'Active';

    private static final String FILE_TITLE = 'Spec Sheet';
    private static final String FILE_BODY = 'File Content';

    private static final Decimal BASE_BUDGET = 50000;
    private static final Decimal UPDATED_BUDGET = 99999;
    private static final Decimal REVISIT_BUDGET = 5000;

    @TestSetup
    static void setupTestData() {
        User supervisorUser = TestDataUtility.createSupervisorUser(SUPERVISOR_ALIAS);

        Account accountRecord = TestDataUtility.createAccount(ACCOUNT_NAME);

        Contact clientContact = TestDataUtility.createContact(
            CLIENT_LAST_NAME,
            CLIENT_EMAIL,
            CLIENT_PASSWORD
        );
        clientContact.AccountId = accountRecord.Id;
        update clientContact;

        TestDataUtility.createVendor(
            VENDOR_ONE_NAME,
            VENDOR_CATEGORY,
            VENDOR_ONE_EMAIL
        );

        TestDataUtility.createVendor(
            VENDOR_TWO_NAME,
            VENDOR_CATEGORY,
            VENDOR_TWO_EMAIL
        );

        Assert.isNotNull(
            supervisorUser.Id,
            'Supervisor user should be created by TestDataUtility.'
        );
    }

    @IsTest
    static void testHandleAfterInsertWithEmptyListReturnsSafely() {
        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterInsert(new List<Opportunity>());
        Test.stopTest();

        Assert.areEqual(
            0,
            getTotalProjectCount(),
            'Empty after-insert input should return safely without creating Project records.'
        );
    }

    @IsTest
    static void testHandleAfterInsertWithNullListReturnsSafely() {
        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterInsert(null);
        Test.stopTest();

        Assert.areEqual(
            0,
            getTotalProjectCount(),
            'Null after-insert input should return safely without creating Project records.'
        );
    }

    @IsTest
    static void testHandleAfterInsertReturnsWhenTemplateIsMissing() {
        Opportunity opportunityRecord = createBaseOpportunity('Email Missing Template Opp');

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterInsert(
            new List<Opportunity>{ opportunityRecord }
        );
        Test.stopTest();

        Assert.areEqual(
            0,
            getProjectCountForOpportunity(opportunityRecord.Id),
            'After-insert email path should not create Project records.'
        );
    }

    @IsTest
    static void testHandleAfterInsertWithTemplateRunsEmailLogicSafely() {
        Opportunity opportunityRecord = createBaseOpportunity('Email Template Insert Opp');
        createArchitectApprovalTemplateSafely();

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterInsert(
            new List<Opportunity>{ opportunityRecord }
        );
        Test.stopTest();

        Assert.areEqual(
            0,
            getProjectCountForOpportunity(opportunityRecord.Id),
            'After-insert email logic should execute safely without creating Project records.'
        );
    }

    @IsTest
    static void testHandleAfterInsertSkipsOpportunityWithoutRecordType() {
        Opportunity opportunityRecord = createBaseOpportunity('No Record Type Insert Opp');
        opportunityRecord.RecordTypeId = null;

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterInsert(
            new List<Opportunity>{ opportunityRecord }
        );
        Test.stopTest();

        Assert.areEqual(
            0,
            getProjectCountForOpportunity(opportunityRecord.Id),
            'Opportunity without Arelia RecordTypeId should be skipped without creating Project records.'
        );
    }

    @IsTest
    static void testHandleAfterUpdateWithEmptyListReturnsSafely() {
        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterUpdate(
            new List<Opportunity>(),
            new Map<Id, Opportunity>()
        );
        Test.stopTest();

        Assert.areEqual(
            0,
            getTotalProjectCount(),
            'Empty after-update input should return safely without creating Project records.'
        );
    }

    @IsTest
    static void testHandleAfterUpdateWithNullListReturnsSafely() {
        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterUpdate(
            null,
            new Map<Id, Opportunity>()
        );
        Test.stopTest();

        Assert.areEqual(
            0,
            getTotalProjectCount(),
            'Null after-update input should return safely without creating Project records.'
        );
    }

    @IsTest
    static void testPrimaryContactAddedAfterUpdateInvokesEmailPathOnly() {
        Opportunity oldOpportunity = createBaseOpportunity('Primary Contact Added Opp');
        oldOpportunity.Primary_Contact__c = null;

        Opportunity newOpportunity = oldOpportunity.clone(true, true, true, true);
        newOpportunity.Primary_Contact__c = getClientContact().Id;

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterUpdate(
            new List<Opportunity>{ newOpportunity },
            new Map<Id, Opportunity>{ oldOpportunity.Id => oldOpportunity }
        );
        Test.stopTest();

        Assert.areEqual(
            0,
            getProjectCountForOpportunity(oldOpportunity.Id),
            'Adding Primary Contact without Closed Won transition should not create Project.'
        );
    }

    @IsTest
    static void testHandleAfterUpdateCreatesProjectAndCopiesFiles() {
        Opportunity oldOpportunity = createValidOpportunityForProject('Create Project Success Opp');
        createSignedVendorOpportunity(oldOpportunity.Id, getVendorOne().Id);

        ContentVersion contentVersion = TestDataUtility.createContentVersion(
            FILE_TITLE,
            FILE_BODY
        );
        TestDataUtility.linkFileToRecord(contentVersion.Id, oldOpportunity.Id);

        Opportunity newOpportunity = oldOpportunity.clone(true, true, true, true);
        newOpportunity.StageName = STAGE_CLOSED_WON;

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterUpdate(
            new List<Opportunity>{ newOpportunity },
            new Map<Id, Opportunity>{ oldOpportunity.Id => oldOpportunity }
        );
        Test.stopTest();

        Project__c projectRecord = getProjectForOpportunity(oldOpportunity.Id);
        Integer copiedFileCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :projectRecord.Id
        ];

        Assert.isNotNull(
            projectRecord.Id,
            'A Project should be created when Opportunity moves to Closed Won and gates pass.'
        );
        Assert.areEqual(
            BASE_BUDGET,
            projectRecord.Budget__c,
            'Project Budget__c should be copied from Opportunity.'
        );
        Assert.areEqual(
            oldOpportunity.Supervisor_User__c,
            projectRecord.Supervisor_User__c,
            'Project supervisor should be copied from Opportunity.'
        );
        Assert.areEqual(
            1,
            copiedFileCount,
            'Opportunity file should be copied to the newly created Project.'
        );
    }

    @IsTest
    static void testHandleAfterUpdateCreatesProjectWithoutFiles() {
        Opportunity oldOpportunity = createValidOpportunityForProject('Create Project No File Opp');
        createSignedVendorOpportunity(oldOpportunity.Id, getVendorOne().Id);

        Opportunity newOpportunity = oldOpportunity.clone(true, true, true, true);
        newOpportunity.StageName = STAGE_CLOSED_WON;

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterUpdate(
            new List<Opportunity>{ newOpportunity },
            new Map<Id, Opportunity>{ oldOpportunity.Id => oldOpportunity }
        );
        Test.stopTest();

        Project__c projectRecord = getProjectForOpportunity(oldOpportunity.Id);
        Integer copiedFileCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :projectRecord.Id
        ];

        Assert.isNotNull(
            projectRecord.Id,
            'Project should still be created when Opportunity has no files.'
        );
        Assert.areEqual(
            0,
            copiedFileCount,
            'No files should be copied when Opportunity has no ContentDocumentLink records.'
        );
    }

    @IsTest
    static void testHandleAfterUpdateUpdatesExistingProject() {
        Opportunity oldOpportunity = createValidOpportunityForProject('Update Project Success Opp');
        createSignedVendorOpportunity(oldOpportunity.Id, getVendorOne().Id);

        Project__c existingProject = TestDataUtility.createProject(
            'Existing Project',
            1000,
            getClientContact().Id
        );
        existingProject.Project_Name__c = oldOpportunity.Id;
        existingProject.Supervisor_User__c = getProjectOwnerUserId();
        update existingProject;

        Opportunity newOpportunity = oldOpportunity.clone(true, true, true, true);
        newOpportunity.StageName = STAGE_CLOSED_WON;
        newOpportunity.Budget__c = UPDATED_BUDGET;

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterUpdate(
            new List<Opportunity>{ newOpportunity },
            new Map<Id, Opportunity>{ oldOpportunity.Id => oldOpportunity }
        );
        Test.stopTest();

        Project__c updatedProject = [
            SELECT Id, Budget__c
            FROM Project__c
            WHERE Id = :existingProject.Id
            LIMIT 1
        ];

        Assert.areEqual(
            UPDATED_BUDGET,
            updatedProject.Budget__c,
            'Existing Project should be updated from the Closed Won Opportunity.'
        );
    }

    @IsTest
    static void testRevisitLogicMapsRevisitBudgetAndDuration() {
        Opportunity oldOpportunity = createValidOpportunityForProject('Revisit Mapping Opp');
        createSignedVendorOpportunity(oldOpportunity.Id, getVendorOne().Id);

        Opportunity newOpportunity = oldOpportunity.clone(true, true, true, true);
        newOpportunity.StageName = STAGE_CLOSED_WON;
        newOpportunity.Appointment_Status__c = 'Re-Visit';
        newOpportunity.Re_Visit_Appointmnet_Confirmation__c = true;
        newOpportunity.Re_Visit_Site_Supervisor_Estimate_Budget__c = REVISIT_BUDGET;
        newOpportunity.ReVisit_Site_Estimated_Completion_Months__c = '2 Months';

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterUpdate(
            new List<Opportunity>{ newOpportunity },
            new Map<Id, Opportunity>{ oldOpportunity.Id => oldOpportunity }
        );
        Test.stopTest();

        Project__c projectRecord = [
            SELECT Id, Supervisor_Estimated_Budget__c, Estimated_Project_Duration__c
            FROM Project__c
            WHERE Project_Name__c = :oldOpportunity.Id
            LIMIT 1
        ];

        Assert.areEqual(
            REVISIT_BUDGET,
            projectRecord.Supervisor_Estimated_Budget__c,
            'Re-Visit budget should be mapped to Project Supervisor_Estimated_Budget__c.'
        );
        Assert.areEqual(
            '2 Months',
            projectRecord.Estimated_Project_Duration__c,
            'Re-Visit duration should be mapped to Project Estimated_Project_Duration__c.'
        );
    }

    @IsTest
    static void testValidationFailsWhenClientAgreementMissing() {
        Opportunity oldOpportunity = createBaseOpportunity('Missing Client Agreement Opp');
        oldOpportunity.StageName = STAGE_PROPOSAL;
        oldOpportunity.Client_Agreement_Sent__c = true;
        oldOpportunity.Client_Agreement_Signed__c = false;
        oldOpportunity.All_Vendors_Agreement_Completed__c = true;
        update oldOpportunity;

        Opportunity newOpportunity = oldOpportunity.clone(true, true, true, true);
        newOpportunity.StageName = STAGE_CLOSED_WON;

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterUpdate(
            new List<Opportunity>{ newOpportunity },
            new Map<Id, Opportunity>{ oldOpportunity.Id => oldOpportunity }
        );
        Test.stopTest();

        Assert.isTrue(
            newOpportunity.hasErrors(),
            'Opportunity should have validation error when Client Agreement is not signed.'
        );
        Assert.isTrue(
            newOpportunity.getErrors()[0].getMessage().contains('Client Agreement'),
            'Error should mention Client Agreement.'
        );
    }

    @IsTest
    static void testValidationFailsWhenAllVendorsFlagMissing() {
        Opportunity oldOpportunity = createBaseOpportunity('Missing All Vendors Flag Opp');
        oldOpportunity.StageName = STAGE_PROPOSAL;
        oldOpportunity.Client_Agreement_Sent__c = true;
        oldOpportunity.Client_Agreement_Signed__c = true;
        oldOpportunity.All_Vendors_Agreement_Completed__c = false;
        update oldOpportunity;

        Opportunity newOpportunity = oldOpportunity.clone(true, true, true, true);
        newOpportunity.StageName = STAGE_CLOSED_WON;

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterUpdate(
            new List<Opportunity>{ newOpportunity },
            new Map<Id, Opportunity>{ oldOpportunity.Id => oldOpportunity }
        );
        Test.stopTest();

        Assert.isTrue(
            newOpportunity.hasErrors(),
            'Opportunity should have validation error when all vendors flag is not completed.'
        );
        Assert.isTrue(
            newOpportunity.getErrors()[0].getMessage().contains('All Vendors Agreement not completed'),
            'Error should mention all vendors agreement completion.'
        );
    }

    @IsTest
    static void testValidationFailsWhenNoVendorOpportunityExists() {
        Opportunity oldOpportunity = createBaseOpportunity('No Vendor Opportunity Opp');
        oldOpportunity.StageName = STAGE_PROPOSAL;
        oldOpportunity.Client_Agreement_Sent__c = true;
        oldOpportunity.Client_Agreement_Signed__c = true;
        oldOpportunity.All_Vendors_Agreement_Completed__c = true;
        update oldOpportunity;

        Opportunity newOpportunity = oldOpportunity.clone(true, true, true, true);
        newOpportunity.StageName = STAGE_CLOSED_WON;

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterUpdate(
            new List<Opportunity>{ newOpportunity },
            new Map<Id, Opportunity>{ oldOpportunity.Id => oldOpportunity }
        );
        Test.stopTest();

        Assert.isTrue(
            newOpportunity.hasErrors(),
            'Opportunity should have validation error when no Vendor Opportunity exists.'
        );
        Assert.isTrue(
            newOpportunity.getErrors()[0].getMessage().contains('No Vendor_Opportunity__c'),
            'Error should mention missing Vendor Opportunity records.'
        );
    }

    @IsTest
    static void testValidationFailsWhenVendorAgreementNotSigned() {
        Opportunity oldOpportunity = createBaseOpportunity('Unsigned Vendor Agreement Opp');
        oldOpportunity.StageName = STAGE_PROPOSAL;
        oldOpportunity.Client_Agreement_Sent__c = true;
        oldOpportunity.Client_Agreement_Signed__c = true;
        oldOpportunity.All_Vendors_Agreement_Completed__c = true;
        update oldOpportunity;

        Vendor_Opportunity__c vendorOpportunity = TestDataUtility.createVendorOpportunity(
            oldOpportunity.Id,
            getVendorOne().Id,
            STATUS_ACTIVE
        );
        vendorOpportunity.Vendor_Agreement_Sent__c = true;
        vendorOpportunity.Vendor_Agreement_Signed__c = false;
        update vendorOpportunity;

        Opportunity newOpportunity = oldOpportunity.clone(true, true, true, true);
        newOpportunity.StageName = STAGE_CLOSED_WON;

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterUpdate(
            new List<Opportunity>{ newOpportunity },
            new Map<Id, Opportunity>{ oldOpportunity.Id => oldOpportunity }
        );
        Test.stopTest();

        Assert.isTrue(
            newOpportunity.hasErrors(),
            'Opportunity should have validation error when vendor agreement is not signed.'
        );
        Assert.isTrue(
            newOpportunity.getErrors()[0].getMessage().contains('have not signed'),
            'Error should mention unsigned vendor agreement.'
        );
    }

    @IsTest
    static void testMultipleVendorLinksPassValidation() {
        Opportunity oldOpportunity = createValidOpportunityForProject('Multiple Vendor Success Opp');

        createSignedVendorOpportunity(oldOpportunity.Id, getVendorOne().Id);
        createSignedVendorOpportunity(oldOpportunity.Id, getVendorTwo().Id);

        Opportunity newOpportunity = oldOpportunity.clone(true, true, true, true);
        newOpportunity.StageName = STAGE_CLOSED_WON;

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterUpdate(
            new List<Opportunity>{ newOpportunity },
            new Map<Id, Opportunity>{ oldOpportunity.Id => oldOpportunity }
        );
        Test.stopTest();

        Assert.areEqual(
            1,
            getProjectCountForOpportunity(oldOpportunity.Id),
            'Project should be created when multiple vendor agreements are signed.'
        );
    }

    @IsTest
    static void testIgnoreWhenStageDoesNotMoveToClosedWon() {
        Opportunity oldOpportunity = createBaseOpportunity('Ignore Non Closed Won Opp');
        oldOpportunity.StageName = STAGE_PROPOSAL;
        update oldOpportunity;

        Opportunity newOpportunity = oldOpportunity.clone(true, true, true, true);
        newOpportunity.StageName = 'Prospecting';

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterUpdate(
            new List<Opportunity>{ newOpportunity },
            new Map<Id, Opportunity>{ oldOpportunity.Id => oldOpportunity }
        );
        Test.stopTest();

        Assert.areEqual(
            0,
            getProjectCountForOpportunity(oldOpportunity.Id),
            'No Project should be created when Opportunity does not move to Closed Won.'
        );
    }

    @IsTest
    static void testIgnoreWhenOpportunityWasAlreadyClosedWon() {
        Opportunity oldOpportunity = createValidOpportunityForProject('Already Closed Won Opp');
        createSignedVendorOpportunity(oldOpportunity.Id, getVendorOne().Id);

        oldOpportunity.StageName = STAGE_CLOSED_WON;

        Opportunity newOpportunity = oldOpportunity.clone(true, true, true, true);
        newOpportunity.StageName = STAGE_CLOSED_WON;

        Test.startTest();
        CreateProjectFromOpportunityHandler.handleAfterUpdate(
            new List<Opportunity>{ newOpportunity },
            new Map<Id, Opportunity>{ oldOpportunity.Id => oldOpportunity }
        );
        Test.stopTest();

        Assert.areEqual(
            0,
            getProjectCountForOpportunity(oldOpportunity.Id),
            'No Project should be created when Opportunity was already Closed Won.'
        );
    }

    private static void createArchitectApprovalTemplateSafely() {
        String templateDeveloperName = Label.Arelia_Living_Architect_3D_Design_Approval_Email;

        if (String.isBlank(templateDeveloperName)) {
            return;
        }

        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataUtility.createSpecificEmailTemplate(
                templateDeveloperName,
                'Architect 3D Design Approval',
                'Architecture Design Approval'
            );
        }
    }

    private static Opportunity createBaseOpportunity(String opportunityName) {
        Opportunity opportunityRecord = TestDataUtility.createOpportunity(
            opportunityName,
            getProjectOwnerUserId()
        );

        opportunityRecord.AccountId = getClientAccount().Id;
        opportunityRecord.Primary_Contact__c = getClientContact().Id;
        opportunityRecord.Supervisor_User__c = getProjectOwnerUserId();
        opportunityRecord.StageName = STAGE_PROPOSAL;
        opportunityRecord.Email__c = CLIENT_EMAIL;
        opportunityRecord.Budget__c = BASE_BUDGET;
        opportunityRecord.Project_Description__c = 'Project description';
        opportunityRecord.Supervisor_Estimated_Budget__c = BASE_BUDGET;
        opportunityRecord.Project_Estimated_Completion_Months__c = '3 Months';
        opportunityRecord.Project_Scope__c = 'Dining Hall';
        opportunityRecord.Type_of_Project__c = 'Home';
        update opportunityRecord;

        return opportunityRecord;
    }

    private static Opportunity createValidOpportunityForProject(String opportunityName) {
        Opportunity opportunityRecord = createBaseOpportunity(opportunityName);

        opportunityRecord.Client_Agreement_Sent__c = true;
        opportunityRecord.Client_Agreement_Signed__c = true;
        opportunityRecord.All_Vendors_Agreement_Completed__c = true;
        update opportunityRecord;

        return opportunityRecord;
    }

    private static Vendor_Opportunity__c createSignedVendorOpportunity(
        Id opportunityId,
        Id vendorId
    ) {
        Vendor_Opportunity__c vendorOpportunity = TestDataUtility.createVendorOpportunity(
            opportunityId,
            vendorId,
            STATUS_ACTIVE
        );
        vendorOpportunity.Vendor_Agreement_Sent__c = true;
        vendorOpportunity.Vendor_Agreement_Signed__c = true;
        update vendorOpportunity;

        return vendorOpportunity;
    }

    private static Id getProjectOwnerUserId() {
        return UserInfo.getUserId();
    }

    private static Account getClientAccount() {
        return [
            SELECT Id
            FROM Account
            WHERE Name = :ACCOUNT_NAME
            LIMIT 1
        ];
    }

    private static Contact getClientContact() {
        return [
            SELECT Id, Email
            FROM Contact
            WHERE Email = :CLIENT_EMAIL
            LIMIT 1
        ];
    }

    private static Vendor__c getVendorOne() {
        return [
            SELECT Id, Name
            FROM Vendor__c
            WHERE Name = :VENDOR_ONE_NAME
            LIMIT 1
        ];
    }

    private static Vendor__c getVendorTwo() {
        return [
            SELECT Id, Name
            FROM Vendor__c
            WHERE Name = :VENDOR_TWO_NAME
            LIMIT 1
        ];
    }

    private static Project__c getProjectForOpportunity(Id opportunityId) {
        return [
            SELECT Id, Budget__c, Supervisor_User__c
            FROM Project__c
            WHERE Project_Name__c = :opportunityId
            LIMIT 1
        ];
    }

    private static Integer getProjectCountForOpportunity(Id opportunityId) {
        return [
            SELECT COUNT()
            FROM Project__c
            WHERE Project_Name__c = :opportunityId
        ];
    }

    private static Integer getTotalProjectCount() {
        return [
            SELECT COUNT()
            FROM Project__c
        ];
    }
}
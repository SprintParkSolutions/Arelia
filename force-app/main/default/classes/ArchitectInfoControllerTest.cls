/**
 * @description Tests architect information updates and email validation.
 */
@IsTest
private class ArchitectInfoControllerTest {
    @TestSetup
    static void setupData() {
        User supervisor = TestDataUtility.createSupervisorUser('archsup');
        Opportunity opportunityRecord = TestDataUtility.createOpportunity('Architect Info Opp', supervisor.Id);
    }

    private static User createArchitectTestUser(String alias) {
        Profile testProfile = [SELECT Id FROM Profile
                        WHERE Name = 'System Administrator'LIMIT 1];

        User testUser = new User(
            Alias = alias,
            Email = alias + '@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Architect',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = testProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = alias + DateTime.now().getTime() + '@testorg.com'
        );
        insert testUser;

        PermissionSet architectPermissionSet = [
            SELECT Id FROM PermissionSet WHERE Name = 'Arelia_Admin_Permission_set' LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = testUser.Id,
            PermissionSetId = architectPermissionSet.Id
        );

        return testUser;
    }

    @IsTest
    static void updateAndSendEmailUpdatesOpportunity() {
        TestDataUtility.createSpecificEmailTemplate(
            'Architect_Opportunity_Mail',
            'Architect Opportunity Mail',
            'Architect details for {!Opportunity.Name}',
            '<html><body>Architect opportunity {!Opportunity.Name}</body></html>'
        );
        Opportunity opportunityRecord = [SELECT Id FROM Opportunity LIMIT 1];
        User architectUser = createArchitectTestUser('archok');

        Test.startTest();
        System.runAs(architectUser) {
            ArchitectInfoController.updateAndSendEmail(
                opportunityRecord.Id,
                'Asha Architect',
                'architect@example.com',
                '9999999999'
            );
        }
        Test.stopTest();

        Opportunity updatedOpportunity = [SELECT Architect_Name__c, Architect_Email__c, Architect_Contact__c
            FROM Opportunity WHERE Id = :opportunityRecord.Id];
        Assert.areEqual('Asha Architect', updatedOpportunity.Architect_Name__c, 'Architect name should be saved.');
        Assert.areEqual('architect@example.com', updatedOpportunity.Architect_Email__c, 'Architect email should be saved.');
        Assert.areEqual('9999999999', updatedOpportunity.Architect_Contact__c, 'Architect phone should be saved.');
    }

    @IsTest
    static void updateAndSendEmailRequiresRecordAndEmail() {
        Test.startTest();
        Boolean caughtMissingRecord = false;
        try {
            ArchitectInfoController.updateAndSendEmail(null, 'Architect', 'architect@example.com', '9999999999');
        } catch (AuraHandledException ex) {
            caughtMissingRecord = true;
            Assert.isNotNull(ex.getMessage(), 'Exception should include a validation message.');
        }

        Boolean caughtMissingEmail = false;
        try {
            Opportunity opportunityRecord = [SELECT Id FROM Opportunity LIMIT 1];
            ArchitectInfoController.updateAndSendEmail(opportunityRecord.Id, 'Architect', null, '9999999999');
        } catch (AuraHandledException ex) {
            caughtMissingEmail = true;
            Assert.isNotNull(ex.getMessage(), 'Exception should include a validation message.');
        }

        Boolean caughtBlankEmail = false;
        try {
            Opportunity opportunityRecord = [SELECT Id FROM Opportunity LIMIT 1];
            ArchitectInfoController.updateAndSendEmail(opportunityRecord.Id, 'Architect', '   ', '9999999999');
        } catch (AuraHandledException ex) {
            caughtBlankEmail = true;
            Assert.isNotNull(ex.getMessage(), 'Exception should include a validation message.');
        }
        Test.stopTest();

        Assert.isTrue(caughtMissingRecord, 'Missing Opportunity Id should throw an AuraHandledException.');
        Assert.isTrue(caughtMissingEmail, 'Missing architect email should throw an AuraHandledException.');
        Assert.isTrue(caughtBlankEmail, 'Blank architect email should throw an AuraHandledException.');
    }

    @IsTest
    static void updateAndSendEmailRejectsUnsupportedOpportunityRecordType() {
        TestDataUtility.createSpecificEmailTemplate(
            'Architect_Opportunity_Mail',
            'Architect Opportunity Mail',
            'Architect details',
            '<html><body>Architect details</body></html>'
        );
        Id unsupportedRecordId = UserInfo.getUserId();

        Test.startTest();
        Boolean caughtUnsupportedType = false;
        try {
            ArchitectInfoController.updateAndSendEmail(
                unsupportedRecordId,
                'Blocked Architect',
                'blocked@example.com',
                '7777777777'
            );
        } catch (AuraHandledException ex) {
            caughtUnsupportedType = true;
            Assert.isNotNull(ex.getMessage(), 'Exception should include the unsupported type message.');
        }
        Test.stopTest();

        Assert.isTrue(caughtUnsupportedType, 'Non-Arelia Opportunity should be rejected.');
    }

    @IsTest
    static void updateAndSendEmailThrowsWhenTemplateIsMissing() {
        ArchitectInfoController.templateDeveloperName = 'Missing_Architect_Template_For_Test';
        Opportunity opportunityRecord = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        Boolean caughtMissingTemplate = false;
        try {
            ArchitectInfoController.updateAndSendEmail(
                opportunityRecord.Id,
                'Missing Template Architect',
                'missing-template@example.com',
                '6666666666'
            );
        } catch (AuraHandledException ex) {
            caughtMissingTemplate = true;
            Assert.isNotNull(ex.getMessage(), 'Exception should include the missing template message.');
        }
        Test.stopTest();

        Assert.isTrue(caughtMissingTemplate, 'Missing architect email template should throw an AuraHandledException.');
    }

    @IsTest
    static void updateAndSendEmailRollsBackWhenEmailCannotBeSent() {
        TestDataUtility.createSpecificEmailTemplate(
            'Architect_Opportunity_Mail',
            'Architect Opportunity Mail',
            'Architect details for {!Opportunity.Name}',
            '<html><body>Architect opportunity {!Opportunity.Name}</body></html>'
        );
        Opportunity opportunityRecord = [SELECT Id, Architect_Name__c, Architect_Email__c, Architect_Contact__c
                        FROM Opportunity LIMIT 1];
        User architectUser = createArchitectTestUser('archrb');

        Test.startTest();
        Boolean caughtEmailFailure = false;
        try {
            System.runAs(architectUser) {
                ArchitectInfoController.updateAndSendEmail(
                    opportunityRecord.Id,
                    'Rollback Architect',
                    'invalid-email-address',
                    '5555555555'
                );
            }
        } catch (AuraHandledException ex) {
            caughtEmailFailure = true;
            Assert.isNotNull(ex.getMessage(), 'Exception should include the email failure message.');
        }
        Test.stopTest();

        Opportunity rolledBackOpportunity = [SELECT Architect_Name__c, Architect_Email__c, Architect_Contact__c
            FROM Opportunity WHERE Id = :opportunityRecord.Id];
        Assert.isTrue(caughtEmailFailure, 'Invalid architect email should fail and surface an AuraHandledException.');
        Assert.areEqual(opportunityRecord.Architect_Name__c, rolledBackOpportunity.Architect_Name__c, 'Architect name should roll back.');
        Assert.areEqual(opportunityRecord.Architect_Email__c, rolledBackOpportunity.Architect_Email__c, 'Architect email should roll back.');
        Assert.areEqual(opportunityRecord.Architect_Contact__c, rolledBackOpportunity.Architect_Contact__c, 'Architect phone should roll back.');
    }
}
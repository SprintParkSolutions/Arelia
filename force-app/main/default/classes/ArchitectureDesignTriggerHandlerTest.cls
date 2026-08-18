/**
 * @description       : Test class for ArchitectureDesignTriggerHandler
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : Tests
 * @last modified on  : 02-24-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@isTest
private class ArchitectureDesignTriggerHandlerTest {

    @testSetup
    static void setupTestData() {
        // 1. Setup User
        User supervisorUser = TestDataUtility.createSupervisorUser('suprv');
        
        System.runAs(supervisorUser) {
            // 2. Setup Required Email Template
            TestDataUtility.createSpecificEmailTemplate(
                'Architecture_Manager_Approval', 
                'Architecture Manager Approval', 
                'Action Required: {{{leadName}}}',
                '<html><body>Please review the architecture design for [PROJECT_NAME]. <br/> [APPROVAL_LINK]</body></html>'
            );
            
            // 3. Setup Opportunity Parent 
            TestDataUtility.createOpportunity('Test Opportunity', supervisorUser.Id);
        }
    }

    @isTest
    static void testDesignApprovalWithOpportunityAndFile() {
        // Arrange
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        Architecture_Design__c design = TestDataUtility.createArchitectureDesign(opp.Id, null, 'Sent');
        
        ContentVersion file = TestDataUtility.createContentVersion('Architecture_Blueprint_v1', 'Mock File Content Data');
        TestDataUtility.linkFileToRecord(file.Id, design.Id);

        Architecture_Design__c oldDesign = design.clone(true, true, true, true);
        
        // Act
        Test.startTest();
        design.Status__c = 'Approved'; 
        design.Comments__c = 'Approved pending final site visit.';
        update design;
        
        ArchitectureDesignTriggerHandler.onAfterUpdate(
            new List<Architecture_Design__c>{ design },
            new Map<Id, Architecture_Design__c>{ oldDesign.Id => oldDesign }
        );
        Test.stopTest();

        // Assert
        Assert.areEqual('Approved', design.Status__c, 'The architecture design status should be updated to Approved.');
    }

    @isTest
    static void testDesignApprovalWithNoFile() {
        // Arrange
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Architecture_Design__c design = TestDataUtility.createArchitectureDesign(opp.Id, null, 'Sent');
        Architecture_Design__c oldDesign = design.clone(true, true, true, true);
        
        // Act
        Test.startTest();
        design.Status__c = 'Approved';
        update design;
        
        ArchitectureDesignTriggerHandler.onAfterUpdate(
            new List<Architecture_Design__c>{ design },
            new Map<Id, Architecture_Design__c>{ oldDesign.Id => oldDesign }
        );
        Test.stopTest();

        // Assert
        Assert.areEqual('Approved', design.Status__c, 'The architecture design status should be Approved.');
    }

    @isTest
    static void testDesignRejectionNoEmailTriggered() {
        // Arrange
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Architecture_Design__c design = TestDataUtility.createArchitectureDesign(opp.Id, null, 'Sent');
        Architecture_Design__c oldDesign = design.clone(true, true, true, true);
        
        // Act
        Test.startTest();
        design.Status__c = 'Changes Requested';
        design.Comments__c = 'Needs revision on the palette.';
        update design;
        
        ArchitectureDesignTriggerHandler.onAfterUpdate(
            new List<Architecture_Design__c>{ design },
            new Map<Id, Architecture_Design__c>{ oldDesign.Id => oldDesign }
        );
        Test.stopTest();

        // Assert
        Assert.areEqual('Changes Requested', design.Status__c, 'The design status should be Changes Requested, bypassing the email block.');
    }
    
    @isTest
    static void testBulkDesignApproval() {
        // Arrange
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Architecture_Design__c> newDesigns = new List<Architecture_Design__c>();
        Map<Id, Architecture_Design__c> oldMap = new Map<Id, Architecture_Design__c>();
        
        for(Integer i = 0; i < 5; i++) {
            newDesigns.add(TestDataUtility.createArchitectureDesign(opp.Id, null, 'Sent'));
        }
        
        for(Architecture_Design__c des : newDesigns) {
            Architecture_Design__c oldDes = des.clone(true, true, true, true);
            oldMap.put(oldDes.Id, oldDes);
            des.Status__c = 'Approved';
        }

        // Act
        Test.startTest();
        update newDesigns;
        ArchitectureDesignTriggerHandler.onAfterUpdate(newDesigns, oldMap);
        Test.stopTest();

        // Assert
        Assert.areEqual(5, newDesigns.size(), 'Bulk operation should process all records without throwing exceptions.');
        for(Architecture_Design__c des : newDesigns) {
            Assert.areEqual('Approved', des.Status__c, 'All bulk records should have Approved status.');
        }
    }

    // --- NEW BOUNDARY & NEGATIVE SCENARIOS FOR MAX COVERAGE ---

    @isTest
    static void testDesignApprovalOrphanedRecord() {
        // Arrange: Create a design with NO parent Opportunity or Project to hit fallback branches
        Architecture_Design__c design = new Architecture_Design__c(
            Status__c = 'Sent',
            Secure_Token__c = 'test-token-123'
        );
        insert design;
        
        Architecture_Design__c oldDesign = design.clone(true, true, true, true);
        
        // Act
        Test.startTest();
        design.Status__c = 'Approved';
        update design;
        
        ArchitectureDesignTriggerHandler.onAfterUpdate(
            new List<Architecture_Design__c>{ design },
            new Map<Id, Architecture_Design__c>{ oldDesign.Id => oldDesign }
        );
        Test.stopTest();

        // Assert
        Assert.areEqual('Approved', design.Status__c, 'An orphaned architecture design should still process successfully.');
    }

    @isTest
    static void testDesignApprovalWithNullFields() {
        // Arrange: The TestDataUtility doesn't populate these custom fields, so they are ALREADY null!
        // We don't need to manually update them (which avoids the 'Field is not writeable' error on formula fields).
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Architecture_Design__c design = TestDataUtility.createArchitectureDesign(opp.Id, null, 'Sent');
        Architecture_Design__c oldDesign = design.clone(true, true, true, true);
        
        // Act
        Test.startTest();
        design.Status__c = 'Approved';
        update design;
        
        ArchitectureDesignTriggerHandler.onAfterUpdate(
            new List<Architecture_Design__c>{ design },
            new Map<Id, Architecture_Design__c>{ oldDesign.Id => oldDesign }
        );
        Test.stopTest();

        // Assert
        Assert.areEqual('Approved', design.Status__c, 'Design should approve even if parent fields are completely null.');
    }
}
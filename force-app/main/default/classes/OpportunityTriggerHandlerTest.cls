@IsTest
public class OpportunityTriggerHandlerTest {

    /**
     * Utility method to create an Opportunity
     */
    private static Opportunity createOpportunity(String stage, Decimal budget) {
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = stage,
            CloseDate = Date.today().addDays(30),
            Negotiation_Review_Budget__c = budget,
            // Initialize flags to false/null to test distinct transitions
            All_Vendors_Agreement_Completed__c = false
        );
        insert opp;
        return opp;
    }

    /**
     * Utility method to create a Project linked to Opportunity
     */
    private static Project__c createProject(Id oppId) {
        Project__c project = new Project__c(
            Project_Name__c = oppId,
            Status__c = 'Initiated',
            Supervisor_Estimated_Budget__c = null
        );
        insert project;
        return project;
    }

    /**
     * POSITIVE TEST
     * Opportunity moved to Resumed stage with budget → Project updated
     */
    @IsTest
    static void testQualifiedOpportunityUpdatesProject() {

        // Create Opportunity (initially NOT Resumed)
        Opportunity opp = createOpportunity('Prospecting', null);

        // Create related Project
        Project__c project = createProject(opp.Id);

        // Update Opportunity to qualified state
        opp.StageName = 'Resumed';
        opp.Negotiation_Review_Budget__c = 50000;
        
        // FIX: Satisfy Validation Rule ("Stage cannot be set to 'Resumed' until...")
        opp.All_Vendors_Agreement_Completed__c = true; 

        Test.startTest();
        update opp;
        Test.stopTest();

        // Fetch updated Project
        Project__c updatedProject = [
            SELECT Status__c, Supervisor_Estimated_Budget__c
            FROM Project__c
            WHERE Id = :project.Id
        ];

        // Assertions
        System.assertEquals(
            'In Progress',
            updatedProject.Status__c,
            'Project status should be updated'
        );

        System.assertEquals(
            50000,
            updatedProject.Supervisor_Estimated_Budget__c,
            'Budget should sync from Opportunity'
        );
    }

    /**
     * NEGATIVE TEST
     * Opportunity not Resumed → Project should NOT update
     */
    @IsTest
    static void testNonQualifiedOpportunityDoesNotUpdateProject() {

        Opportunity opp = createOpportunity('Prospecting', 25000);
        Project__c project = createProject(opp.Id);

        // Update Opportunity without meeting criteria
        opp.Name = 'Updated Name Only';
        // Note: We do NOT set Stage to Resumed or flags here, so it stays in Prospecting

        Test.startTest();
        update opp;
        Test.stopTest();

        Project__c unchangedProject = [
            SELECT Status__c, Supervisor_Estimated_Budget__c
            FROM Project__c
            WHERE Id = :project.Id
        ];

        System.assertEquals(
            'Initiated',
            unchangedProject.Status__c,
            'Project status should remain unchanged'
        );

        System.assertEquals(
            null,
            unchangedProject.Supervisor_Estimated_Budget__c,
            'Budget should not update'
        );
    }

    /**
     * BULK TEST
     * Multiple Opportunities updated at once
     */
    @IsTest
    static void testBulkOpportunityUpdates() {

        List<Opportunity> opps = new List<Opportunity>();
        List<Project__c> projects = new List<Project__c>();

        for (Integer i = 0; i < 5; i++) {
            Opportunity opp = new Opportunity(
                Name = 'Bulk Opp ' + i,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(10),
                Negotiation_Review_Budget__c = null,
                All_Vendors_Agreement_Completed__c = false
            );
            opps.add(opp);
        }
        insert opps;

        for (Opportunity opp : opps) {
            projects.add(createProject(opp.Id));
        }

        // Qualify all opportunities
        for (Opportunity opp : opps) {
            opp.StageName = 'Resumed';
            opp.Negotiation_Review_Budget__c = 10000;
            // FIX: Satisfy Validation Rule for Bulk update
            opp.All_Vendors_Agreement_Completed__c = true;
        }

        Test.startTest();
        update opps;
        Test.stopTest();

        // Verify all projects updated
        List<Project__c> updatedProjects = [
            SELECT Status__c, Supervisor_Estimated_Budget__c
            FROM Project__c
        ];

        for (Project__c proj : updatedProjects) {
            System.assertEquals(
                'In Progress',
                proj.Status__c,
                'Project status should be updated to In Progress for all bulk Opportunities'
            );
            System.assertEquals(
                10000,
                proj.Supervisor_Estimated_Budget__c,
                'Project budget should be updated to match Opportunity budget for all bulk Opportunities'
            );
        }
    }
}
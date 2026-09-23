/**
 * @description
 * Tests OpportunityTriggerHandler project synchronization functionality.
 */
@IsTest
private class OpportunityTriggerHandlerTest {

    private static final String STAGE_PROSPECTING = 'Prospecting';
    private static final String STAGE_RESUMED = 'Resumed';
    private static final String STATUS_INITIATED = 'Initiated';
    private static final String STATUS_IN_PROGRESS = 'In Progress';

    private static final Decimal QUALIFIED_BUDGET = 50000;
    private static final Decimal NON_QUALIFIED_BUDGET = 25000;
    private static final Decimal BULK_BUDGET = 10000;
    private static final Integer BULK_RECORD_COUNT = 5;

    /**
     * Creates an Arelia Opportunity using TestDataUtility and places it
     * in the required initial state.
     *
     * @param opportunityName Opportunity name.
     * @param stageName Initial Opportunity stage.
     * @param negotiationBudget Initial negotiation budget.
     * @return Created Opportunity.
     */
    private static Opportunity createOpportunity(
        String opportunityName,
        String stageName,
        Decimal negotiationBudget
    ) {
        Opportunity opportunityRecord = TestDataUtility.createOpportunity(
            opportunityName,
            UserInfo.getUserId()
        );

        opportunityRecord.StageName = stageName;
        opportunityRecord.Negotiation_Review_Budget__c = negotiationBudget;
        opportunityRecord.All_Vendors_Agreement_Completed__c = false;

        update opportunityRecord;

        return opportunityRecord;
    }

    /**
     * Creates an Arelia Project linked to the supplied Opportunity.
     *
     * The TestDataUtility project method is not used because it does not
     * populate Project_Name__c and initializes Status__c as In Progress.
     *
     * @param opportunityId Related Opportunity Id.
     * @return Created Project.
     */
    private static Project__c createProject(Id opportunityId) {
        Project__c projectRecord = new Project__c(
            Name = 'Test Project ' + String.valueOf(opportunityId),
            Project_Name__c = opportunityId,
            Status__c = STATUS_INITIATED,
            Supervisor_Estimated_Budget__c = null,
            RecordTypeId = AreliaUtility.getAreliaProjectRecordTypeId()
        );

        insert projectRecord;

        return projectRecord;
    }

    /**
     * Verifies that moving an Arelia Opportunity to Resumed with a budget
     * updates its related Arelia Project.
     */
    @IsTest
    private static void testQualifiedOpportunityUpdatesProject() {
        Opportunity opportunityRecord = createOpportunity(
            'Qualified Test Opportunity',
            STAGE_PROSPECTING,
            null
        );

        Project__c projectRecord = createProject(opportunityRecord.Id);

        opportunityRecord.StageName = STAGE_RESUMED;
        opportunityRecord.Negotiation_Review_Budget__c = QUALIFIED_BUDGET;
        opportunityRecord.All_Vendors_Agreement_Completed__c = true;

        Test.startTest();
        update opportunityRecord;
        Test.stopTest();

        Project__c updatedProject = [
            SELECT Status__c, Supervisor_Estimated_Budget__c
            FROM Project__c
            WHERE Id = :projectRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_IN_PROGRESS,
            updatedProject.Status__c,
            'The related Arelia Project status should be updated.'
        );

        System.assertEquals(
            QUALIFIED_BUDGET,
            updatedProject.Supervisor_Estimated_Budget__c,
            'The Opportunity budget should be copied to the related Project.'
        );
    }

    /**
     * Verifies that updating an Opportunity without moving it to Resumed
     * does not update its related Project.
     */
    @IsTest
    private static void testNonQualifiedOpportunityDoesNotUpdateProject() {
        Opportunity opportunityRecord = createOpportunity(
            'Non-Qualified Test Opportunity',
            STAGE_PROSPECTING,
            NON_QUALIFIED_BUDGET
        );

        Project__c projectRecord = createProject(opportunityRecord.Id);

        opportunityRecord.Name = 'Updated Non-Qualified Opportunity';

        Test.startTest();
        update opportunityRecord;
        Test.stopTest();

        Project__c unchangedProject = [
            SELECT Status__c, Supervisor_Estimated_Budget__c
            FROM Project__c
            WHERE Id = :projectRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_INITIATED,
            unchangedProject.Status__c,
            'The Project status should remain unchanged.'
        );

        System.assertEquals(
            null,
            unchangedProject.Supervisor_Estimated_Budget__c,
            'The Project budget should remain unchanged.'
        );
    }

    /**
     * Verifies bulk processing of multiple qualified Arelia Opportunities
     * and their related Arelia Projects.
     */
    @IsTest
    private static void testBulkOpportunityUpdates() {
        Id opportunityRecordTypeId =
            AreliaUtility.getAreliaOpportunityRecordTypeId();

        List<Opportunity> opportunityRecords = new List<Opportunity>();

        for (Integer indexValue = 0;
            indexValue < BULK_RECORD_COUNT;
            indexValue++
        ) {
            opportunityRecords.add(
                new Opportunity(
                    Name = 'Bulk Opportunity ' + indexValue,
                    StageName = STAGE_PROSPECTING,
                    CloseDate = Date.today().addDays(30),
                    Negotiation_Review_Budget__c = null,
                    All_Vendors_Agreement_Completed__c = false,
                    RecordTypeId = opportunityRecordTypeId
                )
            );
        }

        insert opportunityRecords;

        List<Project__c> projectRecords = new List<Project__c>();

        for (Opportunity opportunityRecord : opportunityRecords) {
            projectRecords.add(
                new Project__c(
                    Name = 'Bulk Project ' + opportunityRecord.Id,
                    Project_Name__c = opportunityRecord.Id,
                    Status__c = STATUS_INITIATED,
                    Supervisor_Estimated_Budget__c = null,
                    RecordTypeId =
                        AreliaUtility.getAreliaProjectRecordTypeId()
                )
            );
        }

        insert projectRecords;

        Set<Id> projectIds = new Map<Id, Project__c>(
            projectRecords
        ).keySet();

        for (Opportunity opportunityRecord : opportunityRecords) {
            opportunityRecord.StageName = STAGE_RESUMED;
            opportunityRecord.Negotiation_Review_Budget__c = BULK_BUDGET;
            opportunityRecord.All_Vendors_Agreement_Completed__c = true;
        }

        Test.startTest();
        update opportunityRecords;
        Test.stopTest();

        List<Project__c> updatedProjects = [
            SELECT
                Status__c,
                Supervisor_Estimated_Budget__c,
                Project_Name__c
            FROM Project__c
            WHERE Id IN :projectIds
        ];

        System.assertEquals(
            BULK_RECORD_COUNT,
            updatedProjects.size(),
            'Every test Project should be returned for verification.'
        );

        for (Project__c projectRecord : updatedProjects) {
            System.assertEquals(
                STATUS_IN_PROGRESS,
                projectRecord.Status__c,
                'Every related Arelia Project should be moved to In Progress.'
            );

            System.assertEquals(
                BULK_BUDGET,
                projectRecord.Supervisor_Estimated_Budget__c,
                'Every Project should receive its Opportunity budget.'
            );
        }
    }

    /**
     * Verifies that an Arelia Opportunity already in Resumed stage does not
     * cause another Project update when neither stage nor budget changes.
     */
    @IsTest
    private static void testUnchangedQualifiedValuesDoNotUpdateProject() {
        Opportunity opportunityRecord = createOpportunity(
            'Unchanged Qualified Opportunity',
            STAGE_PROSPECTING,
            null
        );

        Project__c projectRecord = createProject(opportunityRecord.Id);

        opportunityRecord.StageName = STAGE_RESUMED;
        opportunityRecord.Negotiation_Review_Budget__c = QUALIFIED_BUDGET;
        opportunityRecord.All_Vendors_Agreement_Completed__c = true;
        update opportunityRecord;

        Project__c projectAfterQualifiedUpdate = [
            SELECT Status__c, Supervisor_Estimated_Budget__c
            FROM Project__c
            WHERE Id = :projectRecord.Id
            LIMIT 1
        ];

        projectAfterQualifiedUpdate.Status__c = STATUS_INITIATED;
        projectAfterQualifiedUpdate.Supervisor_Estimated_Budget__c = null;
        update projectAfterQualifiedUpdate;

        opportunityRecord.Name = 'Name Changed Only';

        Test.startTest();
        update opportunityRecord;
        Test.stopTest();

        Project__c unchangedProject = [
            SELECT Status__c, Supervisor_Estimated_Budget__c
            FROM Project__c
            WHERE Id = :projectRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_INITIATED,
            unchangedProject.Status__c,
            'The Project should not update when stage and budget are unchanged.'
        );

        System.assertEquals(
            null,
            unchangedProject.Supervisor_Estimated_Budget__c,
            'The Project budget should not update when qualifying values are unchanged.'
        );
    }
}
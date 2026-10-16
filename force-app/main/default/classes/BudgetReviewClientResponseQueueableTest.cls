/**
 * -----------------------------------------------------------------------------
 * Class Name      : BudgetReviewClientResponseQueueableTest
 * Author          : Arelia
 * Created Date    : Oct 7, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 7, 2026
 * Description     : Test class for BudgetReviewClientResponseQueueable.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class BudgetReviewClientResponseQueueableTest {

    private static final String STATUS_FIELD =
        'Description';

    private static final String REMARKS_FIELD =
        'NextStep';

    private static final String STATUS_VALUE =
        'Client Approved';

    private static final String COMMENTS =
        'Client approved the budget.';

    private static final String ORIGINAL_DESCRIPTION =
        'Pending Client Response';

    private static final String ORIGINAL_NEXT_STEP =
        'Awaiting client review';

    /**
     * Creates common Opportunity test data.
     */
    @TestSetup
    static void setupData() {

        Opportunity opportunity = new Opportunity(
            Name = 'Budget Review Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Description = ORIGINAL_DESCRIPTION,
            NextStep = ORIGINAL_NEXT_STEP
        );

        insert opportunity;
    }

    /**
     * Verifies that status and client remarks are updated successfully.
     */
    @IsTest
    static void validRequestUpdatesStatusAndRemarks() {

        Opportunity opportunity = getTestOpportunity();

        Test.startTest();

        System.enqueueJob(
            new BudgetReviewClientResponseQueueable(
                opportunity.Id,
                STATUS_FIELD,
                REMARKS_FIELD,
                STATUS_VALUE,
                COMMENTS
            )
        );

        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT Description,
                   NextStep
            FROM Opportunity
            WHERE Id = :opportunity.Id
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_VALUE,
            updatedOpportunity.Description,
            'The configured status field should be updated.'
        );

        System.assertEquals(
            COMMENTS,
            updatedOpportunity.NextStep,
            'The configured client remarks field should be updated.'
        );
    }

    /**
     * Verifies that leading and trailing spaces are removed
     * from client comments.
     */
    @IsTest
    static void commentsAreTrimmedBeforeUpdate() {

        Opportunity opportunity = getTestOpportunity();

        String commentsWithSpaces =
            '   Client requested revised pricing.   ';

        String expectedComments =
            'Client requested revised pricing.';

        Test.startTest();

        System.enqueueJob(
            new BudgetReviewClientResponseQueueable(
                opportunity.Id,
                STATUS_FIELD,
                REMARKS_FIELD,
                'Changes Requested',
                commentsWithSpaces
            )
        );

        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT Description,
                   NextStep
            FROM Opportunity
            WHERE Id = :opportunity.Id
            LIMIT 1
        ];

        System.assertEquals(
            'Changes Requested',
            updatedOpportunity.Description,
            'The status value should be updated.'
        );

        System.assertEquals(
            expectedComments,
            updatedOpportunity.NextStep,
            'Client remarks should be trimmed before being saved.'
        );
    }

    /**
     * Verifies that remarks remain unchanged when comments are blank.
     */
    @IsTest
    static void blankCommentsDoNotUpdateRemarks() {

        Opportunity opportunity = getTestOpportunity();

        Test.startTest();

        System.enqueueJob(
            new BudgetReviewClientResponseQueueable(
                opportunity.Id,
                STATUS_FIELD,
                REMARKS_FIELD,
                STATUS_VALUE,
                '   '
            )
        );

        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT Description,
                   NextStep
            FROM Opportunity
            WHERE Id = :opportunity.Id
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_VALUE,
            updatedOpportunity.Description,
            'The status should still be updated.'
        );

        System.assertEquals(
            ORIGINAL_NEXT_STEP,
            updatedOpportunity.NextStep,
            'Remarks should remain unchanged for blank comments.'
        );
    }

    /**
     * Verifies that execution stops when Opportunity Id is null.
     */
    @IsTest
    static void nullOpportunityIdReturnsWithoutUpdate() {

        Opportunity opportunity = getTestOpportunity();

        Test.startTest();

        BudgetReviewClientResponseQueueable queueable =
            new BudgetReviewClientResponseQueueable(
                null,
                STATUS_FIELD,
                REMARKS_FIELD,
                STATUS_VALUE,
                COMMENTS
            );

        queueable.execute(null);

        Test.stopTest();

        Opportunity unchangedOpportunity = [
            SELECT Description,
                   NextStep
            FROM Opportunity
            WHERE Id = :opportunity.Id
            LIMIT 1
        ];

        System.assertEquals(
            ORIGINAL_DESCRIPTION,
            unchangedOpportunity.Description,
            'Description should remain unchanged.'
        );

        System.assertEquals(
            ORIGINAL_NEXT_STEP,
            unchangedOpportunity.NextStep,
            'NextStep should remain unchanged.'
        );
    }

    /**
     * Verifies that execution stops when the status field API name is blank.
     */
    @IsTest
    static void blankStatusFieldReturnsWithoutUpdate() {

        Opportunity opportunity = getTestOpportunity();

        Test.startTest();

        BudgetReviewClientResponseQueueable queueable =
            new BudgetReviewClientResponseQueueable(
                opportunity.Id,
                '   ',
                REMARKS_FIELD,
                STATUS_VALUE,
                COMMENTS
            );

        queueable.execute(null);

        Test.stopTest();

        Opportunity unchangedOpportunity = [
            SELECT Description,
                   NextStep
            FROM Opportunity
            WHERE Id = :opportunity.Id
            LIMIT 1
        ];

        System.assertEquals(
            ORIGINAL_DESCRIPTION,
            unchangedOpportunity.Description,
            'Description should remain unchanged.'
        );

        System.assertEquals(
            ORIGINAL_NEXT_STEP,
            unchangedOpportunity.NextStep,
            'NextStep should remain unchanged.'
        );
    }

    /**
     * Verifies that execution stops when the status value is blank.
     */
    @IsTest
    static void blankStatusValueReturnsWithoutUpdate() {

        Opportunity opportunity = getTestOpportunity();

        Test.startTest();

        BudgetReviewClientResponseQueueable queueable =
            new BudgetReviewClientResponseQueueable(
                opportunity.Id,
                STATUS_FIELD,
                REMARKS_FIELD,
                '   ',
                COMMENTS
            );

        queueable.execute(null);

        Test.stopTest();

        Opportunity unchangedOpportunity = [
            SELECT Description,
                   NextStep
            FROM Opportunity
            WHERE Id = :opportunity.Id
            LIMIT 1
        ];

        System.assertEquals(
            ORIGINAL_DESCRIPTION,
            unchangedOpportunity.Description,
            'Description should remain unchanged.'
        );

        System.assertEquals(
            ORIGINAL_NEXT_STEP,
            unchangedOpportunity.NextStep,
            'NextStep should remain unchanged.'
        );
    }

    /**
     * Verifies that execution exits safely when the Opportunity
     * does not exist.
     */
    @IsTest
    static void missingOpportunityReturnsWithoutError() {

        Id missingOpportunityId =
            createMissingOpportunityId();

        Test.startTest();

        BudgetReviewClientResponseQueueable queueable =
            new BudgetReviewClientResponseQueueable(
                missingOpportunityId,
                STATUS_FIELD,
                REMARKS_FIELD,
                STATUS_VALUE,
                COMMENTS
            );

        queueable.execute(null);

        Test.stopTest();

        Integer recordCount = [
            SELECT COUNT()
            FROM Opportunity
            WHERE Id = :missingOpportunityId
        ];

        System.assertEquals(
            0,
            recordCount,
            'The test Opportunity should not exist.'
        );
    }

    /**
     * Returns the Opportunity created by @TestSetup.
     */
    private static Opportunity getTestOpportunity() {

        return [
            SELECT Id,
                   Description,
                   NextStep
            FROM Opportunity
            WHERE Name = 'Budget Review Test Opportunity'
            LIMIT 1
        ];
    }

    /**
     * Creates a valid Opportunity Id whose record does not exist.
     */
    private static Id createMissingOpportunityId() {

        Opportunity temporaryOpportunity = new Opportunity(
            Name = 'Temporary Budget Review Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );

        insert temporaryOpportunity;

        Id opportunityId =
            temporaryOpportunity.Id;

        delete temporaryOpportunity;

        return opportunityId;
    }
}
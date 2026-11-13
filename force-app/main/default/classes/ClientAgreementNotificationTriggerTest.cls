/**
 * -----------------------------------------------------------------------------
 * Class Name      : ClientAgreementNotificationTriggerTest
 * Author          : Arelia
 * Created Date    : Oct 13, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 13, 2026
 * Description     : Unit tests for ClientAgreementNotificationTrigger.
 *                   Validates client agreement sent transitions,
 *                   Queueable notification creation, unchanged
 *                   checkbox values, and bulk Opportunity updates.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ClientAgreementNotificationTriggerTest {

    private static final String STAGE_QUALIFICATION =
        'Qualification';

    private static final String JOB_CLASS_NAME =
        'ClientAgreementPushJob';

    private static final Integer BULK_RECORD_COUNT = 5;

    /**
     * Creates an Opportunity with required fields.
     * @param opportunityName Name of the Opportunity.
     * @param agreementSent Initial agreement sent status.
     * @return Inserted Opportunity record.
     */
    private static Opportunity createOpportunity(
        String opportunityName,
        Boolean agreementSent
    ) {
        Opportunity opportunityRecord = new Opportunity(
            Name = opportunityName,
            StageName = STAGE_QUALIFICATION,
            CloseDate = Date.today().addDays(30),
            Client_Agreement_Sent__c = agreementSent
        );

        insert opportunityRecord;

        return opportunityRecord;
    }

    /**
     * Returns the number of Queueable jobs created
     * during the current test transaction.
     *
     * @return Queueable job count.
     */
    private static Integer getQueueableJobCount() {
        List<AsyncApexJob> jobs = [
            SELECT Id
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
            AND ApexClass.Name = :JOB_CLASS_NAME
        ];

        return jobs.size();
    }

    /**
     * Verifies that changing the agreement sent
     * checkbox from false to true enqueues a
     * notification Queueable job.
     */
    @IsTest
    static void agreementSentEnqueuesNotification() {

        Opportunity opportunityRecord = createOpportunity(
            'Agreement Sent Test',
            false
        );

        Integer jobsBefore = getQueueableJobCount();

        Test.startTest();

        opportunityRecord.Client_Agreement_Sent__c = true;
        update opportunityRecord;

        Integer jobsAfter = getQueueableJobCount();

        System.Assert.areEqual(
            1,
            jobsAfter - jobsBefore,
            'Sending the client agreement should enqueue ' +
            'one notification job.'
        );

        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT Client_Agreement_Sent__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];

        System.Assert.isTrue(
            updatedOpportunity.Client_Agreement_Sent__c,
            'Client Agreement Sent should be true.'
        );
    }

    /**
     * Verifies that changing the checkbox
     * from true to false does not enqueue
     * a notification.
     */
    @IsTest
    static void agreementResetDoesNotEnqueue() {

        Opportunity opportunityRecord = createOpportunity(
            'Agreement Reset Test',
            true
        );

        Integer jobsBefore = getQueueableJobCount();

        Test.startTest();

        opportunityRecord.Client_Agreement_Sent__c = false;
        update opportunityRecord;

        Integer jobsAfter = getQueueableJobCount();

        System.Assert.areEqual(
            0,
            jobsAfter - jobsBefore,
            'Resetting the agreement checkbox should ' +
            'not enqueue a notification.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that updating an Opportunity
     * without changing the agreement sent
     * checkbox does not enqueue a notification.
     */
    @IsTest
    static void unchangedAgreementDoesNotEnqueue() {

        Opportunity opportunityRecord = createOpportunity(
            'Unchanged Agreement Test',
            false
        );

        Integer jobsBefore = getQueueableJobCount();

        Test.startTest();

        opportunityRecord.Name =
            'Updated Agreement Test';

        update opportunityRecord;

        Integer jobsAfter = getQueueableJobCount();

        System.Assert.areEqual(
            0,
            jobsAfter - jobsBefore,
            'An unchanged agreement status should ' +
            'not enqueue a notification.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that an already sent agreement
     * does not generate another notification
     * when unrelated fields are updated.
     */
    @IsTest
    static void alreadySentDoesNotEnqueueAgain() {

        Opportunity opportunityRecord = createOpportunity(
            'Already Sent Test',
            true
        );

        Integer jobsBefore = getQueueableJobCount();

        Test.startTest();

        opportunityRecord.Name =
            'Already Sent Updated';

        update opportunityRecord;

        Integer jobsAfter = getQueueableJobCount();

        System.Assert.areEqual(
            0,
            jobsAfter - jobsBefore,
            'An already sent agreement should not ' +
            'enqueue another notification.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that sending client agreements
     * for multiple Opportunities in one update
     * enqueues only one Queueable job.
     */
    @IsTest
    static void bulkAgreementsEnqueueOneJob() {

        List<Opportunity> opportunities =
            new List<Opportunity>();

        for (
            Integer index = 0;
            index < BULK_RECORD_COUNT;
            index++
        ) {
            opportunities.add(
                new Opportunity(
                    Name = 'Bulk Agreement ' + index,
                    StageName = STAGE_QUALIFICATION,
                    CloseDate = Date.today().addDays(30),
                    Client_Agreement_Sent__c = false
                )
            );
        }

        insert opportunities;

        for (Opportunity opportunityRecord : opportunities) {
            opportunityRecord.Client_Agreement_Sent__c = true;
        }

        Integer jobsBefore = getQueueableJobCount();

        Test.startTest();

        update opportunities;

        Integer jobsAfter = getQueueableJobCount();

        System.Assert.areEqual(
            1,
            jobsAfter - jobsBefore,
            'Bulk agreement updates should enqueue ' +
            'only one Queueable job.'
        );

        Test.stopTest();

        Integer sentCount = [
            SELECT COUNT()
            FROM Opportunity
            WHERE Id IN :opportunities
            AND Client_Agreement_Sent__c = true
        ];

        System.Assert.areEqual(
            BULK_RECORD_COUNT,
            sentCount,
            'All Opportunities should have ' +
            'Client Agreement Sent set to true.'
        );
    }

    /**
     * Verifies that only newly sent agreements
     * trigger the notification when bulk updates
     * contain mixed agreement statuses.
     */
    @IsTest
    static void mixedAgreementUpdatesEnqueueOneJob() {

        Opportunity firstOpportunity = createOpportunity(
            'Mixed Agreement One',
            false
        );

        Opportunity secondOpportunity = createOpportunity(
            'Mixed Agreement Two',
            true
        );

        Opportunity thirdOpportunity = createOpportunity(
            'Mixed Agreement Three',
            false
        );

        firstOpportunity.Client_Agreement_Sent__c = true;

        secondOpportunity.Name =
            'Mixed Agreement Two Updated';

        thirdOpportunity.Name =
            'Mixed Agreement Three Updated';

        List<Opportunity> opportunities =
            new List<Opportunity>{
                firstOpportunity,
                secondOpportunity,
                thirdOpportunity
            };

        Integer jobsBefore = getQueueableJobCount();

        Test.startTest();

        update opportunities;

        Integer jobsAfter = getQueueableJobCount();

        System.Assert.areEqual(
            1,
            jobsAfter - jobsBefore,
            'Only newly sent agreements should ' +
            'trigger the notification Queueable.'
        );

        Test.stopTest();
    }
}
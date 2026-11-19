/**
 * -----------------------------------------------------------------------------
 * Class Name      : LeadSupervisorNotificationTriggerTest
 * Author          : Arelia
 * Created Date    : Oct 12, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 12, 2026
 * Description     : Unit tests for LeadSupervisorNotificationTrigger.
 *                   Validates supervisor assignment changes, queueable notification execution, unchanged assignments, null values,
 *                   and bulk Lead updates.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class LeadSupervisorNotificationTriggerTest {

    private static final String STATUS_OPEN = 'Open';

    private static final String STATUS_APPROVED = 'Approved';

    private static final String QUEUEABLE_CLASS_NAME =
        'LeadSupervisorAssignedPushJob';

    private static final String JOB_TYPE_QUEUEABLE =
        'Queueable';

    private static final Integer BULK_RECORD_COUNT = 5;

    /**
     * Creates an approved Lead to satisfy supervisor
     * assignment validation rules.
     */
    private static Lead createApprovedLead(
        String suffix
    ) {
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Supervisor ' + suffix,
            Company = 'Arelia Test ' + suffix,
            Status = STATUS_OPEN,
            Project_Request_Submitted__c = true,
            Approval_Status__c = STATUS_APPROVED
        );

        insert testLead;

        return testLead;
    }

    /**
     * Creates approved Leads for bulk testing.
     */
    private static List<Lead> createApprovedLeads(
        Integer recordCount
    ) {
        List<Lead> testLeads = new List<Lead>();

        for (
            Integer index = 0;
            index < recordCount;
            index++
        ) {
            testLeads.add(
                new Lead(
                    FirstName = 'Bulk',
                    LastName = 'Supervisor ' + index,
                    Company = 'Arelia Bulk ' + index,
                    Status = STATUS_OPEN,
                    Project_Request_Submitted__c = true,
                    Approval_Status__c = STATUS_APPROVED
                )
            );
        }

        insert testLeads;

        return testLeads;
    }

    /**
     * Returns the number of Queueable jobs
     * belonging specifically to the supervisor
     * assigned notification class.
     *
     * This excludes Queueable jobs created by
     * unrelated Lead automation.
     */
    private static Integer getSupervisorQueueableCount() {

        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = :JOB_TYPE_QUEUEABLE
            AND ApexClass.Name = :QUEUEABLE_CLASS_NAME
        ];
    }

    /**
     * Verifies that assigning a supervisor
     * enqueues the notification Queueable.
     */
    @IsTest
    static void supervisorAssignmentEnqueuesNotification() {

        Lead testLead = createApprovedLead(
            'Assignment'
        );

        testLead.Supervisor_User__c =
            UserInfo.getUserId();

        Test.startTest();

        Integer jobsBefore =
            getSupervisorQueueableCount();

        update testLead;

        Integer jobsAfter =
            getSupervisorQueueableCount();

        System.assertEquals(
            1,
            jobsAfter - jobsBefore,
            'Supervisor assignment should enqueue ' +
            'one LeadSupervisorAssignedPushJob.'
        );

        Test.stopTest();

        Lead updatedLead = [
            SELECT
                Id,
                Supervisor_User__c
            FROM Lead
            WHERE Id = :testLead.Id
            LIMIT 1
        ];

        System.assertEquals(
            UserInfo.getUserId(),
            updatedLead.Supervisor_User__c,
            'Supervisor should be assigned successfully.'
        );
    }

    /**
     * Verifies that updating unrelated Lead fields
     * does not enqueue a supervisor notification.
     */
    @IsTest
    static void unrelatedFieldUpdateDoesNotEnqueue() {

        Lead testLead = createApprovedLead(
            'Unrelated'
        );

        testLead.Description =
            'Updated Lead description';

        Test.startTest();

        Integer jobsBefore =
            getSupervisorQueueableCount();

        update testLead;

        Integer jobsAfter =
            getSupervisorQueueableCount();

        System.assertEquals(
            0,
            jobsAfter - jobsBefore,
            'Unrelated field updates must not enqueue ' +
            'a supervisor notification.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that an unchanged supervisor
     * does not enqueue another notification.
     */
    @IsTest
    static void unchangedSupervisorDoesNotEnqueue() {

        Lead testLead = createApprovedLead(
            'Unchanged'
        );

        testLead.Supervisor_User__c =
            UserInfo.getUserId();

        update testLead;

        Lead existingLead = [
            SELECT
                Id,
                Supervisor_User__c,
                Description
            FROM Lead
            WHERE Id = :testLead.Id
            LIMIT 1
        ];

        existingLead.Description =
            'Supervisor remains unchanged';

        Test.startTest();

        Integer jobsBefore =
            getSupervisorQueueableCount();

        update existingLead;

        Integer jobsAfter =
            getSupervisorQueueableCount();

        System.assertEquals(
            0,
            jobsAfter - jobsBefore,
            'Unchanged supervisor must not enqueue ' +
            'another notification.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that removing a supervisor
     * does not enqueue a notification.
     */
    @IsTest
    static void supervisorRemovalDoesNotEnqueue() {

        Lead testLead = createApprovedLead(
            'Removal'
        );

        testLead.Supervisor_User__c =
            UserInfo.getUserId();

        update testLead;

        testLead.Supervisor_User__c = null;

        Test.startTest();

        Integer jobsBefore =
            getSupervisorQueueableCount();

        update testLead;

        Integer jobsAfter =
            getSupervisorQueueableCount();

        System.assertEquals(
            0,
            jobsAfter - jobsBefore,
            'Supervisor removal must not enqueue ' +
            'a supervisor notification.'
        );

        Test.stopTest();

        Lead updatedLead = [
            SELECT
                Id,
                Supervisor_User__c
            FROM Lead
            WHERE Id = :testLead.Id
            LIMIT 1
        ];

        System.assertEquals(
            null,
            updatedLead.Supervisor_User__c,
            'Supervisor should be removed successfully.'
        );
    }

    /**
     * Verifies that multiple supervisor assignments
     * enqueue only one supervisor notification
     * Queueable for the entire batch.
     */
    @IsTest
    static void bulkSupervisorAssignmentsEnqueueOneJob() {

        List<Lead> testLeads =
            createApprovedLeads(
                BULK_RECORD_COUNT
            );

        for (Lead testLead : testLeads) {
            testLead.Supervisor_User__c =
                UserInfo.getUserId();
        }

        Test.startTest();

        Integer jobsBefore =
            getSupervisorQueueableCount();

        update testLeads;

        Integer jobsAfter =
            getSupervisorQueueableCount();

        System.assertEquals(
            1,
            jobsAfter - jobsBefore,
            'Bulk supervisor assignments should ' +
            'enqueue one supervisor notification Queueable.'
        );

        Test.stopTest();

        Set<Id> leadIds = new Map<Id, Lead>(
            testLeads
        ).keySet();

        List<Lead> updatedLeads = [
            SELECT
                Id,
                Supervisor_User__c
            FROM Lead
            WHERE Id IN :leadIds
        ];

        System.assertEquals(
            BULK_RECORD_COUNT,
            updatedLeads.size(),
            'All bulk Leads should be updated.'
        );

        for (Lead updatedLead : updatedLeads) {

            System.assertEquals(
                UserInfo.getUserId(),
                updatedLead.Supervisor_User__c,
                'Each Lead must have the assigned supervisor.'
            );
        }
    }

    /**
     * Verifies that inserting a Lead without
     * a supervisor does not enqueue the
     * supervisor notification Queueable.
     */
    @IsTest
    static void leadInsertDoesNotEnqueueNotification() {

        Test.startTest();

        Integer jobsBefore =
            getSupervisorQueueableCount();

        Lead testLead = createApprovedLead(
            'InsertOnly'
        );

        Integer jobsAfter =
            getSupervisorQueueableCount();

        System.assertEquals(
            0,
            jobsAfter - jobsBefore,
            'Lead insertion must not enqueue ' +
            'a supervisor notification.'
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            testLead.Id,
            'Lead should be created successfully.'
        );
    }
}
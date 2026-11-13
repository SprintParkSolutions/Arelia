/**
 * -----------------------------------------------------------------------------
 * Class Name      : LeadSiteVisitNotificationTriggerTest
 * Author          : Arelia
 * Created Date    : Oct 12, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 12, 2026
 * Description     : Unit tests for LeadSiteVisitNotificationTrigger.
 *                   Validates appointment date and time changes,
 *                   valid appointments, null values, unchanged
 *                   appointments, Queueable notification creation,
 *                   and bulk Lead updates.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class LeadSiteVisitNotificationTriggerTest {

    private static final Integer BULK_RECORD_COUNT = 5;

    private static final Integer APPOINTMENT_OFFSET_DAYS = 5;

    /**
     * Returns a valid appointment time slot
     * from the configured Lead picklist.
     */
    private static String getValidTimeSlot() {

        Schema.DescribeFieldResult fieldDescription =
            Lead.Appointment_Time_Slots__c.getDescribe();

        for (
            Schema.PicklistEntry entry :
            fieldDescription.getPicklistValues()
        ) {
            if (
                entry.isActive() &&
                String.isNotBlank(entry.getValue())
            ) {
                return entry.getValue();
            }
        }

        System.assert(
            false,
            'An active appointment time slot is required.'
        );

        return null;
    }

    /**
     * Returns an available Lead status.
     */
    private static String getLeadStatus() {

        List<LeadStatus> statuses = [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = false
            ORDER BY SortOrder
            LIMIT 1
        ];

        System.assert(
            !statuses.isEmpty(),
            'An unconverted Lead status is required.'
        );

        return statuses[0].MasterLabel;
    }

    /**
     * Creates a Lead without an appointment.
     */
    private static Lead createLead() {

        Lead testLead = new Lead(
            FirstName = 'Site Visit',
            LastName = 'Notification Test',
            Company = 'Arelia Test Company',
            Status = getLeadStatus()
        );

        insert testLead;

        return testLead;
    }

    /**
     * Returns the number of Queueable jobs
     * enqueued in the current transaction.
     */
    private static Integer getQueueableCount() {

        return Limits.getQueueableJobs();
    }

    /**
     * Verifies that setting a valid appointment
     * date and time enqueues a notification.
     */
    @IsTest
    static void validAppointmentEnqueuesNotification() {

        Lead testLead = createLead();

        testLead.Appointment_Date__c =
            Date.today().addDays(
                APPOINTMENT_OFFSET_DAYS
            );

        testLead.Appointment_Time_Slots__c =
            getValidTimeSlot();

        Test.startTest();

        Integer jobsBefore = getQueueableCount();

        update testLead;

        Integer jobsAfter = getQueueableCount();

        System.assert(
            jobsAfter > jobsBefore,
            'A valid appointment should enqueue a notification.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that changing only the appointment
     * date enqueues a notification.
     */
    @IsTest
    static void appointmentDateChangeEnqueuesNotification() {

        Lead testLead = createLead();

        testLead.Appointment_Date__c =
            Date.today().addDays(5);

        testLead.Appointment_Time_Slots__c =
            getValidTimeSlot();

        update testLead;

        Test.startTest();

        Integer jobsBefore = getQueueableCount();

        testLead.Appointment_Date__c =
            Date.today().addDays(7);

        update testLead;

        Integer jobsAfter = getQueueableCount();

        System.assert(
            jobsAfter > jobsBefore,
            'Changing the appointment date should enqueue a job.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that adding an appointment time
     * to an existing date enqueues a notification.
     */
    @IsTest
    static void appointmentTimeChangeEnqueuesNotification() {

        Lead testLead = createLead();

        testLead.Appointment_Date__c =
            Date.today().addDays(5);

        update testLead;

        Test.startTest();

        Integer jobsBefore = getQueueableCount();

        testLead.Appointment_Time_Slots__c =
            getValidTimeSlot();

        update testLead;

        Integer jobsAfter = getQueueableCount();

        System.assert(
            jobsAfter > jobsBefore,
            'Changing the time slot should enqueue a job.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that changing both appointment
     * fields enqueues a notification.
     */
    @IsTest
    static void bothAppointmentFieldsChanged() {

        Lead testLead = createLead();

        testLead.Appointment_Date__c =
            Date.today().addDays(6);

        testLead.Appointment_Time_Slots__c =
            getValidTimeSlot();

        Test.startTest();

        Integer jobsBefore = getQueueableCount();

        update testLead;

        Integer jobsAfter = getQueueableCount();

        System.assert(
            jobsAfter > jobsBefore,
            'Changing both appointment fields should enqueue a job.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that unchanged appointment
     * values do not enqueue notifications.
     */
    @IsTest
    static void unchangedAppointmentDoesNotEnqueue() {

        Lead testLead = createLead();

        testLead.Appointment_Date__c =
            Date.today().addDays(5);

        testLead.Appointment_Time_Slots__c =
            getValidTimeSlot();

        update testLead;

        Test.startTest();

        Integer jobsBefore = getQueueableCount();

        testLead.Description =
            'Appointment details remain unchanged.';

        update testLead;

        Integer jobsAfter = getQueueableCount();

        System.assertEquals(
            jobsBefore,
            jobsAfter,
            'Unchanged appointment fields should not enqueue jobs.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that an appointment date without
     * a time slot does not enqueue a notification.
     */
    @IsTest
    static void missingTimeSlotDoesNotEnqueue() {

        Lead testLead = createLead();

        Test.startTest();

        Integer jobsBefore = getQueueableCount();

        testLead.Appointment_Date__c =
            Date.today().addDays(5);

        update testLead;

        Integer jobsAfter = getQueueableCount();

        System.assertEquals(
            jobsBefore,
            jobsAfter,
            'A missing time slot should prevent notification.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that an appointment time without
     * a date does not enqueue a notification.
     */
    @IsTest
    static void missingAppointmentDateDoesNotEnqueue() {

        Lead testLead = createLead();

        Test.startTest();

        Integer jobsBefore = getQueueableCount();

        testLead.Appointment_Time_Slots__c =
            getValidTimeSlot();

        update testLead;

        Integer jobsAfter = getQueueableCount();

        System.assertEquals(
            jobsBefore,
            jobsAfter,
            'A missing appointment date should prevent notification.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that unrelated Lead updates
     * do not enqueue appointment notifications.
     */
    @IsTest
    static void unrelatedLeadUpdateDoesNotEnqueue() {

        Lead testLead = createLead();

        Test.startTest();

        Integer jobsBefore = getQueueableCount();

        testLead.Description =
            'Updated unrelated Lead information.';

        update testLead;

        Integer jobsAfter = getQueueableCount();

        System.assertEquals(
            jobsBefore,
            jobsAfter,
            'An unrelated update should not enqueue a job.'
        );

        Test.stopTest();
    }

    /**
     * Verifies bulk appointment scheduling.
     */
    @IsTest
    static void bulkAppointmentsEnqueueOneJob() {

        List<Lead> leads = new List<Lead>();

        String leadStatus = getLeadStatus();

        for (
            Integer index = 0;
            index < BULK_RECORD_COUNT;
            index++
        ) {
            leads.add(
                new Lead(
                    FirstName = 'Bulk Site Visit',
                    LastName = 'Test ' + index,
                    Company = 'Arelia Bulk ' + index,
                    Status = leadStatus
                )
            );
        }

        insert leads;

        String validTimeSlot = getValidTimeSlot();

        for (Lead testLead : leads) {

            testLead.Appointment_Date__c =
                Date.today().addDays(
                    APPOINTMENT_OFFSET_DAYS
                );

            testLead.Appointment_Time_Slots__c =
                validTimeSlot;
        }

        Test.startTest();

        Integer jobsBefore = getQueueableCount();

        update leads;

        Integer jobsAfter = getQueueableCount();

        System.assert(
            jobsAfter > jobsBefore,
            'Bulk scheduling should enqueue notifications.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that mixed valid and invalid
     * appointments are handled in bulk.
     */
    @IsTest
    static void mixedAppointmentsHandledCorrectly() {

        Lead validLead = createLead();

        Lead invalidLead = createLead();

        validLead.Appointment_Date__c =
            Date.today().addDays(5);

        validLead.Appointment_Time_Slots__c =
            getValidTimeSlot();

        invalidLead.Appointment_Date__c =
            Date.today().addDays(5);

        List<Lead> leads = new List<Lead>{
            validLead,
            invalidLead
        };

        Test.startTest();

        Integer jobsBefore = getQueueableCount();

        update leads;

        Integer jobsAfter = getQueueableCount();

        System.assert(
            jobsAfter > jobsBefore,
            'Valid appointments should trigger bulk notification.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that removing an appointment
     * date does not enqueue a notification.
     */
    @IsTest
    static void clearedAppointmentDateDoesNotEnqueue() {

        Lead testLead = createLead();

        testLead.Appointment_Date__c =
            Date.today().addDays(5);

        testLead.Appointment_Time_Slots__c =
            getValidTimeSlot();

        update testLead;

        Test.startTest();

        Integer jobsBefore = getQueueableCount();

        testLead.Appointment_Date__c = null;

        update testLead;

        Integer jobsAfter = getQueueableCount();

        System.assertEquals(
            jobsBefore,
            jobsAfter,
            'Clearing the appointment date should not enqueue.'
        );

        Test.stopTest();
    }

    /**
     * Verifies that removing an appointment
     * time slot does not enqueue a notification.
     */
    @IsTest
    static void clearedTimeSlotDoesNotEnqueue() {

        Lead testLead = createLead();

        testLead.Appointment_Date__c =
            Date.today().addDays(5);

        testLead.Appointment_Time_Slots__c =
            getValidTimeSlot();

        update testLead;

        Test.startTest();

        Integer jobsBefore = getQueueableCount();

        testLead.Appointment_Time_Slots__c = null;

        update testLead;

        Integer jobsAfter = getQueueableCount();

        System.assertEquals(
            jobsBefore,
            jobsAfter,
            'Clearing the time slot should not enqueue.'
        );

        Test.stopTest();
    }
}
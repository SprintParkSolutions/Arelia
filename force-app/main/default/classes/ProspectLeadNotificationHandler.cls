/**
 * Handles Prospect Lead push-notification detection.
 *
 * Notifications:
 * 1. Supervisor assigned or changed.
 * 2. Appointment Confirmed Date changed.
 * 3. Appointment Confirmed Time Slot changed.
 *
 * Static Sets prevent duplicate Queueable jobs when the Lead
 * is updated multiple times within the same transaction.
 */
public without sharing class ProspectLeadNotificationHandler {

    private static final String NOTIFICATION_SUPERVISOR_ASSIGNED =
        'SUPERVISOR_ASSIGNED';

    private static final String NOTIFICATION_SITE_VISIT_SCHEDULED =
        'SITE_VISIT_SCHEDULED';

    /*
     * Prevent duplicate notifications during recursive updates
     * in the same Salesforce transaction.
     */
    private static Set<Id> supervisorNotificationsQueued =
        new Set<Id>();

    private static Set<Id> siteVisitNotificationsQueued =
        new Set<Id>();

    /**
     * Detects Supervisor assignment and confirmed
     * appointment Date/Time Slot changes.
     *
     * @param newLeadList Updated Lead records.
     * @param oldLeadMap Previous Lead values.
     */
    public static void handleAfterUpdate(
        List<Lead> newLeadList,
        Map<Id, Lead> oldLeadMap
    ) {
        if (
            newLeadList == null ||
            newLeadList.isEmpty() ||
            oldLeadMap == null ||
            oldLeadMap.isEmpty()
        ) {
            return;
        }

        Set<Id> supervisorAssignedLeadIds =
            new Set<Id>();

        Set<Id> siteVisitScheduledLeadIds =
            new Set<Id>();

        for (Lead newLead : newLeadList) {
            Lead oldLead =
                oldLeadMap.get(newLead.Id);

            if (oldLead == null) {
                continue;
            }

            /*
             * Supervisor notification:
             *
             * Send when Supervisor is assigned for the first time
             * or changed to another Supervisor.
             */
            Boolean supervisorAssigned =
                newLead.Supervisor_User__c != null &&
                newLead.Supervisor_User__c !=
                    oldLead.Supervisor_User__c;

            if (
                supervisorAssigned &&
                !supervisorNotificationsQueued.contains(
                    newLead.Id
                )
            ) {
                supervisorAssignedLeadIds.add(
                    newLead.Id
                );
            }

            /*
             * Both confirmed appointment values must exist.
             *
             * Appointment_Date__c:
             * Appointment Confirmed Date
             *
             * Appointment_Time_Slots__c:
             * Appointment Confirmed Time Slot
             */
            Boolean hasConfirmedAppointment =
                newLead.Appointment_Date__c != null &&
                String.isNotBlank(
                    newLead.Appointment_Time_Slots__c
                );

            /*
             * Detect Appointment Confirmed Date change.
             *
             * Examples:
             * null -> 8/11/2026
             * 8/11/2026 -> 8/12/2026
             */
            Boolean confirmedDateChanged =
                newLead.Appointment_Date__c !=
                    oldLead.Appointment_Date__c;

            /*
             * Detect Appointment Confirmed Time Slot change.
             *
             * Examples:
             * null -> 9AM-10AM
             * 9AM-10AM -> 10AM-11AM
             */
            Boolean confirmedTimeSlotChanged =
                newLead.Appointment_Time_Slots__c !=
                    oldLead.Appointment_Time_Slots__c;

            /*
             * Send site-visit notification only when:
             *
             * 1. Both confirmed appointment fields have values.
             * 2. Confirmed Date or Confirmed Time Slot changed.
             *
             * Appointment_Status__c and
             * Appointment_Sent_date__c are intentionally ignored.
             */
            Boolean siteVisitScheduled =
                hasConfirmedAppointment &&
                (
                    confirmedDateChanged ||
                    confirmedTimeSlotChanged
                );

            if (
                siteVisitScheduled &&
                !siteVisitNotificationsQueued.contains(
                    newLead.Id
                )
            ) {
                siteVisitScheduledLeadIds.add(
                    newLead.Id
                );
            }
        }

        enqueueSupervisorNotifications(
            supervisorAssignedLeadIds
        );

        enqueueSiteVisitNotifications(
            siteVisitScheduledLeadIds
        );
    }

    /**
     * Queues Supervisor-assignment notifications.
     *
     * @param leadIds Lead record IDs.
     */
    private static void enqueueSupervisorNotifications(
        Set<Id> leadIds
    ) {
        if (
            leadIds == null ||
            leadIds.isEmpty()
        ) {
            return;
        }

        Set<Id> unprocessedLeadIds =
            new Set<Id>(leadIds);

        unprocessedLeadIds.removeAll(
            supervisorNotificationsQueued
        );

        if (unprocessedLeadIds.isEmpty()) {
            return;
        }

        supervisorNotificationsQueued.addAll(
            unprocessedLeadIds
        );

        System.enqueueJob(
            new ProspectPushNotificationQueueable(
                unprocessedLeadIds,
                NOTIFICATION_SUPERVISOR_ASSIGNED
            )
        );
    }

    /**
     * Queues site-visit notifications.
     *
     * @param leadIds Lead record IDs.
     */
    private static void enqueueSiteVisitNotifications(
        Set<Id> leadIds
    ) {
        if (
            leadIds == null ||
            leadIds.isEmpty()
        ) {
            return;
        }

        Set<Id> unprocessedLeadIds =
            new Set<Id>(leadIds);

        unprocessedLeadIds.removeAll(
            siteVisitNotificationsQueued
        );

        if (unprocessedLeadIds.isEmpty()) {
            return;
        }

        siteVisitNotificationsQueued.addAll(
            unprocessedLeadIds
        );

        System.enqueueJob(
            new ProspectPushNotificationQueueable(
                unprocessedLeadIds,
                NOTIFICATION_SITE_VISIT_SCHEDULED
            )
        );
    }
}
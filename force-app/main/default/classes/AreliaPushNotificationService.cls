public with sharing class AreliaPushNotificationService {

    public static void sendToContactAsync(
        Id contactId,
        String title,
        String messageBody,
        String notificationType,
        String recordId
    ) {
        System.enqueueJob(
            new SendPushJob(
                contactId,
                title,
                messageBody,
                notificationType,
                recordId
            )
        );
    }

    public class SendPushJob implements Queueable, Database.AllowsCallouts {

        private Id contactId;
        private String title;
        private String messageBody;
        private String notificationType;
        private String recordId;

        public SendPushJob(
            Id contactId,
            String title,
            String messageBody,
            String notificationType,
            String recordId
        ) {
            this.contactId = contactId;
            this.title = title;
            this.messageBody = messageBody;
            this.notificationType = notificationType;
            this.recordId = recordId;
        }

        public void execute(QueueableContext context) {
            if (contactId == null) {
                System.debug('Contact Id is null. Push and history skipped.');
                return;
            }

            String safeTitle = getSafeText(title, 'Arelia Update');
            String safeMessageBody = getSafeText(
                messageBody,
                'You have a new update.'
            );
            String safeNotificationType = getSafeText(
                notificationType,
                'GENERAL'
            );
            String safeRecordId = String.isBlank(recordId) ? '' : recordId;

            List<Mobile_Device_Token__c> tokenRecords = [
                SELECT Id,
                       FCM_Token__c,
                       Contact__c,
                       Platform__c,
                       Active__c,
                       Last_Seen__c
                FROM Mobile_Device_Token__c
                WHERE Contact__c = :contactId
                AND Active__c = true
                ORDER BY Last_Seen__c DESC
                LIMIT 1
            ];

            if (tokenRecords.isEmpty()) {
                System.debug(
                    'No active mobile device token found for Contact: ' +
                    contactId
                );

                saveNotificationHistory(
                    contactId,
                    safeTitle,
                    safeMessageBody,
                    safeNotificationType,
                    safeRecordId
                );

                return;
            }

            Mobile_Device_Token__c tokenRecord = tokenRecords[0];

            if (String.isBlank(tokenRecord.FCM_Token__c)) {
                System.debug(
                    'Latest token record has empty FCM token. Push skipped.'
                );

                saveNotificationHistory(
                    contactId,
                    safeTitle,
                    safeMessageBody,
                    safeNotificationType,
                    safeRecordId
                );

                return;
            }

            Map<String, String> dataPayload = new Map<String, String>{
                'type' => safeNotificationType,
                'recordId' => safeRecordId,
                'contactId' => String.valueOf(contactId)
            };

            try {
                FirebasePushService.sendPushToToken(
                    tokenRecord.FCM_Token__c,
                    safeTitle,
                    safeMessageBody,
                    dataPayload
                );

                System.debug(
                    'Push sent to latest token record: ' + tokenRecord.Id
                );
            } catch (Exception ex) {
                System.debug(
                    'Firebase push failed for Contact ' +
                    contactId +
                    '. Error: ' +
                    ex.getMessage()
                );
            }

            Id notificationHistoryId = saveNotificationHistory(
                contactId,
                safeTitle,
                safeMessageBody,
                safeNotificationType,
                safeRecordId
            );

            System.debug(
                'Notification history saved with Id: ' +
                notificationHistoryId
            );
        }
    }

    private static String getSafeText(String value, String defaultValue) {
        return String.isBlank(value) ? defaultValue : value;
    }

    private static Id saveNotificationHistory(
        Id contactId,
        String title,
        String messageBody,
        String notificationType,
        String recordId
    ) {
        if (contactId == null) {
            System.debug('Notification history skipped. Contact Id is null.');
            return null;
        }

        try {
            Mobile_Notification__c notificationRec =
                new Mobile_Notification__c();

            notificationRec.Contact__c = contactId;
            notificationRec.Title__c = title;
            notificationRec.Message__c = messageBody;
            notificationRec.Notification_Type__c = notificationType;
            notificationRec.Related_Record_Id__c = recordId;
            notificationRec.Read__c = false;
            notificationRec.Sent_On__c = System.now();

            Database.SaveResult saveResult =
                Database.insert(notificationRec, false);

            if (saveResult.isSuccess()) {
                return notificationRec.Id;
            }

            if (!saveResult.getErrors().isEmpty()) {
                System.debug(
                    'Notification history save failed: ' +
                    saveResult.getErrors()[0].getMessage()
                );
            }

            return null;
        } catch (Exception ex) {
            System.debug(
                'Notification history exception: ' + ex.getMessage()
            );
            return null;
        }
    }
}
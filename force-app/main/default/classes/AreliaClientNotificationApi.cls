@RestResource(urlMapping='/mobile/notifications/*')
global without sharing class AreliaClientNotificationApi {

    global class NotificationItem {
        public String id;
        public String title;
        public String message;
        public String notificationType;
        public String recordId;
        public Boolean read;
        public String sentOn;
    }

    global class NotificationListResponse {
        public Boolean success;
        public Integer unreadCount;
        public List<NotificationItem> notifications;
        public String message;
    }

    global class ActionResponse {
        public Boolean success;
        public String message;
    }

    @HttpGet
    global static void getNotifications() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        String contactIdParam = RestContext.request.params.get('contactId');

        System.debug('NOTIFICATION API CONTACT ID PARAM: ' + contactIdParam);

        if (String.isBlank(contactIdParam)) {
            response.statusCode = 400;
            response.responseBody = Blob.valueOf(
                JSON.serialize(buildErrorResponse('Contact Id is required.'))
            );
            return;
        }

        Id contactId;

        try {
            contactId = Id.valueOf(contactIdParam);
        } catch (Exception ex) {
            response.statusCode = 400;
            response.responseBody = Blob.valueOf(
                JSON.serialize(buildErrorResponse('Invalid Contact Id.'))
            );
            return;
        }

        List<Mobile_Notification__c> notificationRecords = [
            SELECT Id,
                   Contact__c,
                   Title__c,
                   Message__c,
                   Notification_Type__c,
                   Related_Record_Id__c,
                   Read__c,
                   Sent_On__c,
                   CreatedDate
            FROM Mobile_Notification__c
            WHERE Contact__c = :contactId
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];

        System.debug(
            'NOTIFICATION API RECORD COUNT: ' + notificationRecords.size()
        );

        Integer unreadCount = [
            SELECT COUNT()
            FROM Mobile_Notification__c
            WHERE Contact__c = :contactId
            AND Read__c = false
        ];

        List<NotificationItem> items = new List<NotificationItem>();

        for (Mobile_Notification__c notificationRec : notificationRecords) {
            NotificationItem item = new NotificationItem();

            item.id = String.valueOf(notificationRec.Id);
            item.title = notificationRec.Title__c;
            item.message = notificationRec.Message__c;
            item.notificationType = notificationRec.Notification_Type__c;
            item.recordId = notificationRec.Related_Record_Id__c;
            item.read = notificationRec.Read__c;

            DateTime displayDate = notificationRec.Sent_On__c != null
                ? notificationRec.Sent_On__c
                : notificationRec.CreatedDate;

            item.sentOn = displayDate.format('dd MMM yyyy, hh:mm a');

            items.add(item);
        }

        NotificationListResponse successResponse = new NotificationListResponse();
        successResponse.success = true;
        successResponse.unreadCount = unreadCount;
        successResponse.notifications = items;
        successResponse.message = 'Notifications loaded successfully.';

        response.statusCode = 200;
        response.responseBody = Blob.valueOf(JSON.serialize(successResponse));
    }

    @HttpPost
    global static void markNotificationAsRead() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        String requestBody = RestContext.request.requestBody == null
            ? ''
            : RestContext.request.requestBody.toString();

        if (String.isBlank(requestBody)) {
            response.statusCode = 400;
            response.responseBody = Blob.valueOf(
                JSON.serialize(
                    buildActionResponse(false, 'Request body is required.')
                )
            );
            return;
        }

        Map<String, Object> requestMap;

        try {
            requestMap = (Map<String, Object>) JSON.deserializeUntyped(
                requestBody
            );
        } catch (Exception ex) {
            response.statusCode = 400;
            response.responseBody = Blob.valueOf(
                JSON.serialize(
                    buildActionResponse(false, 'Invalid request body.')
                )
            );
            return;
        }

        String notificationId = requestMap.containsKey('notificationId')
            ? String.valueOf(requestMap.get('notificationId'))
            : '';

        if (String.isBlank(notificationId)) {
            response.statusCode = 400;
            response.responseBody = Blob.valueOf(
                JSON.serialize(
                    buildActionResponse(false, 'Notification Id is required.')
                )
            );
            return;
        }

        List<Mobile_Notification__c> notificationRecords = [
            SELECT Id, Read__c
            FROM Mobile_Notification__c
            WHERE Id = :notificationId
            LIMIT 1
        ];

        if (notificationRecords.isEmpty()) {
            response.statusCode = 404;
            response.responseBody = Blob.valueOf(
                JSON.serialize(
                    buildActionResponse(false, 'Notification not found.')
                )
            );
            return;
        }

        Mobile_Notification__c notificationRec = notificationRecords[0];
        notificationRec.Read__c = true;

        Database.SaveResult saveResult = Database.update(notificationRec, false);

        if (!saveResult.isSuccess()) {
            response.statusCode = 500;
            response.responseBody = Blob.valueOf(
                JSON.serialize(
                    buildActionResponse(false, 'Unable to mark notification as read.')
                )
            );
            return;
        }

        response.statusCode = 200;
        response.responseBody = Blob.valueOf(
            JSON.serialize(
                buildActionResponse(true, 'Notification marked as read.')
            )
        );
    }

    private static NotificationListResponse buildErrorResponse(String message) {
        NotificationListResponse errorResponse = new NotificationListResponse();
        errorResponse.success = false;
        errorResponse.unreadCount = 0;
        errorResponse.notifications = new List<NotificationItem>();
        errorResponse.message = message;
        return errorResponse;
    }

    private static ActionResponse buildActionResponse(
        Boolean success,
        String message
    ) {
        ActionResponse actionResponse = new ActionResponse();
        actionResponse.success = success;
        actionResponse.message = message;
        return actionResponse;
    }
}
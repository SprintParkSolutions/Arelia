@IsTest
private class AreliaClientNotificationApiTest {

    @IsTest
    static void getNotificationsSuccessTest() {
        Contact contactRec = createContact();

        List<Mobile_Notification__c> notificationRecords =
            new List<Mobile_Notification__c>{
                createNotification(
                    contactRec.Id,
                    'Project Task Status Updated',
                    'Your project task has been updated.',
                    'TASK_STATUS_UPDATE',
                    'a010000000000001',
                    false
                ),
                createNotification(
                    contactRec.Id,
                    'New Document Uploaded',
                    'A new document has been uploaded.',
                    'FILE_UPLOAD',
                    '069000000000001',
                    true
                )
            };

        insert notificationRecords;

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/mobile/notifications';
        request.httpMethod = 'GET';
        request.params.put('contactId', String.valueOf(contactRec.Id));

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        AreliaClientNotificationApi.getNotifications();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'GET should return 200.'
        );

        Map<String, Object> responseMap =
            (Map<String, Object>) JSON.deserializeUntyped(
                RestContext.response.responseBody.toString()
            );

        System.assertEquals(
            true,
            responseMap.get('success'),
            'Success should be true.'
        );

        System.assertEquals(
            1,
            Integer.valueOf(String.valueOf(responseMap.get('unreadCount'))),
            'Unread count should be 1.'
        );

        List<Object> notifications =
            (List<Object>) responseMap.get('notifications');

        System.assertEquals(
            2,
            notifications.size(),
            'Two notifications should be returned.'
        );
    }

    @IsTest
    static void getNotificationsMissingContactIdTest() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/mobile/notifications';
        request.httpMethod = 'GET';

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        AreliaClientNotificationApi.getNotifications();
        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing contactId should return 400.'
        );

        System.assert(
            RestContext.response.responseBody.toString()
                .contains('Contact Id is required.'),
            'Response should contain contact id required message.'
        );
    }

    @IsTest
    static void getNotificationsInvalidContactIdTest() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/mobile/notifications';
        request.httpMethod = 'GET';
        request.params.put('contactId', 'invalid-contact-id');

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        AreliaClientNotificationApi.getNotifications();
        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Invalid contactId should return 400.'
        );

        System.assert(
            RestContext.response.responseBody.toString()
                .contains('Invalid Contact Id.'),
            'Response should contain invalid contact id message.'
        );
    }

    @IsTest
    static void markNotificationAsReadSuccessTest() {
        Contact contactRec = createContact();

        Mobile_Notification__c notificationRec = createNotification(
            contactRec.Id,
            'Vendor Status Updated',
            'Vendor status has been updated.',
            'VENDOR_STATUS_UPDATE',
            'a020000000000001',
            false
        );

        insert notificationRec;

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/mobile/notifications';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(
            JSON.serialize(
                new Map<String, Object>{
                    'notificationId' => String.valueOf(notificationRec.Id)
                }
            )
        );

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        AreliaClientNotificationApi.markNotificationAsRead();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'POST mark read should return 200.'
        );

        Mobile_Notification__c updatedNotification = [
            SELECT Id, Read__c
            FROM Mobile_Notification__c
            WHERE Id = :notificationRec.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            updatedNotification.Read__c,
            'Notification should be marked as read.'
        );
    }

    @IsTest
    static void markNotificationAsReadEmptyBodyTest() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/mobile/notifications';
        request.httpMethod = 'POST';

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        AreliaClientNotificationApi.markNotificationAsRead();
        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Empty request body should return 400.'
        );

        System.assert(
            RestContext.response.responseBody.toString()
                .contains('Request body is required.'),
            'Response should contain request body required message.'
        );
    }

    @IsTest
    static void markNotificationAsReadInvalidJsonTest() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/mobile/notifications';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('{invalid-json');

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        AreliaClientNotificationApi.markNotificationAsRead();
        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Invalid JSON should return 400.'
        );

        System.assert(
            RestContext.response.responseBody.toString()
                .contains('Invalid request body.'),
            'Response should contain invalid request body message.'
        );
    }

    @IsTest
    static void markNotificationAsReadMissingNotificationIdTest() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/mobile/notifications';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(
            JSON.serialize(
                new Map<String, Object>{
                    'notificationId' => ''
                }
            )
        );

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        AreliaClientNotificationApi.markNotificationAsRead();
        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing notification id should return 400.'
        );

        System.assert(
            RestContext.response.responseBody.toString()
                .contains('Notification Id is required.'),
            'Response should contain notification id required message.'
        );
    }

    @IsTest
    static void markNotificationAsReadNotFoundTest() {
        Contact contactRec = createContact();

        Mobile_Notification__c notificationRec = createNotification(
            contactRec.Id,
            'Temporary Notification',
            'This notification will be deleted.',
            'GENERAL',
            'a030000000000001',
            false
        );

        insert notificationRec;

        Id deletedNotificationId = notificationRec.Id;
        delete notificationRec;

        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/mobile/notifications';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(
            JSON.serialize(
                new Map<String, Object>{
                    'notificationId' => String.valueOf(deletedNotificationId)
                }
            )
        );

        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        AreliaClientNotificationApi.markNotificationAsRead();
        Test.stopTest();

        System.assertEquals(
            404,
            RestContext.response.statusCode,
            'Deleted notification id should return 404.'
        );

        System.assert(
            RestContext.response.responseBody.toString()
                .contains('Notification not found.'),
            'Response should contain notification not found message.'
        );
    }

    private static Contact createContact() {
        Contact contactRec = new Contact(
            LastName = 'Notification Test Client',
            Email = 'notification.client@example.com'
        );

        insert contactRec;

        return contactRec;
    }

    private static Mobile_Notification__c createNotification(
        Id contactId,
        String title,
        String messageBody,
        String notificationType,
        String relatedRecordId,
        Boolean isRead
    ) {
        Mobile_Notification__c notificationRec =
            new Mobile_Notification__c();

        setNameIfEditable(notificationRec, title);

        notificationRec.Contact__c = contactId;
        notificationRec.Title__c = title;
        notificationRec.Message__c = messageBody;
        notificationRec.Notification_Type__c = notificationType;
        notificationRec.Related_Record_Id__c = relatedRecordId;
        notificationRec.Read__c = isRead;
        notificationRec.Sent_On__c = System.now();

        return notificationRec;
    }

    private static void setNameIfEditable(
        Mobile_Notification__c notificationRec,
        String title
    ) {
        Schema.DescribeFieldResult nameDescribe =
            Mobile_Notification__c.Name.getDescribe();

        if (nameDescribe.isCreateable()) {
            notificationRec.put('Name', title);
        }
    }
}
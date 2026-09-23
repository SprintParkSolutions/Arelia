@RestResource(urlMapping='/mobile/device-token')
global with sharing class MobileDeviceTokenApi {

    global class TokenRequest {
        public String action;
        public String contactId;
        public String deviceId;
        public String fcmToken;
        public String platform;
    }

    @HttpPost
    global static void handleDeviceToken() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            TokenRequest input = (TokenRequest) JSON.deserialize(
                req.requestBody.toString(),
                TokenRequest.class
            );

            if (input == null) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('Request body is required');
                return;
            }

            String actionName = String.isBlank(input.action)
                ? 'save'
                : input.action.trim().toLowerCase();

            if (actionName == 'deactivate') {
                deactivateDeviceToken(input, res);
                return;
            }

            saveDeviceToken(input, res);

        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('Error: ' + e.getMessage());
        }
    }

    private static void saveDeviceToken(
        TokenRequest input,
        RestResponse res
    ) {
        if (
            String.isBlank(input.contactId) ||
            String.isBlank(input.deviceId) ||
            String.isBlank(input.fcmToken)
        ) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(
                'contactId, deviceId and fcmToken are required'
            );
            return;
        }

        List<Contact> contacts = [
            SELECT Id
            FROM Contact
            WHERE Id = :input.contactId
            LIMIT 1
        ];

        if (contacts.isEmpty()) {
            res.statusCode = 404;
            res.responseBody = Blob.valueOf('Contact not found');
            return;
        }

        /*
         * IMPORTANT:
         * We are NOT filtering with FCM_Token__c because Salesforce does not allow it.
         * We fetch active records and compare FCM token inside Apex.
         */
        List<Mobile_Device_Token__c> candidateTokens = [
            SELECT Id,
                   Contact__c,
                   Device_Id__c,
                   FCM_Token__c,
                   Platform__c,
                   Active__c,
                   Last_Seen__c
            FROM Mobile_Device_Token__c
            WHERE Active__c = true
            OR Device_Id__c = :input.deviceId
        ];

        Mobile_Device_Token__c currentToken;

        for (Mobile_Device_Token__c tokenRec : candidateTokens) {
            if (tokenRec.Device_Id__c == input.deviceId) {
                currentToken = tokenRec;
                break;
            }
        }

        List<Mobile_Device_Token__c> tokensToDeactivate =
            new List<Mobile_Device_Token__c>();

        for (Mobile_Device_Token__c tokenRec : candidateTokens) {
            Boolean sameDevice =
                tokenRec.Device_Id__c == input.deviceId;

            Boolean sameFcm =
                !String.isBlank(tokenRec.FCM_Token__c) &&
                tokenRec.FCM_Token__c == input.fcmToken;

            Boolean sameRecord =
                currentToken != null &&
                currentToken.Id != null &&
                tokenRec.Id == currentToken.Id;

            if (
                !sameRecord &&
                tokenRec.Active__c == true &&
                (sameDevice || sameFcm)
            ) {
                tokenRec.Active__c = false;
                tokensToDeactivate.add(tokenRec);
            }
        }

        if (!tokensToDeactivate.isEmpty()) {
            update tokensToDeactivate;
        }

        if (currentToken == null) {
            currentToken = new Mobile_Device_Token__c();
            currentToken.Device_Id__c = input.deviceId;
        }

        currentToken.Contact__c = input.contactId;
        currentToken.Device_Id__c = input.deviceId;
        currentToken.FCM_Token__c = input.fcmToken;
        currentToken.Platform__c = String.isBlank(input.platform)
            ? 'Android'
            : input.platform;
        currentToken.Active__c = true;
        currentToken.Last_Seen__c = System.now();

        upsert currentToken;

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(
            'Device token saved successfully. Old duplicate tokens deactivated: ' +
            String.valueOf(tokensToDeactivate.size())
        );
    }

    private static void deactivateDeviceToken(
        TokenRequest input,
        RestResponse res
    ) {
        if (
            String.isBlank(input.deviceId) &&
            String.isBlank(input.fcmToken)
        ) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(
                'deviceId or fcmToken is required to deactivate token'
            );
            return;
        }

        List<Mobile_Device_Token__c> candidateTokens = [
            SELECT Id,
                   Contact__c,
                   Device_Id__c,
                   FCM_Token__c,
                   Active__c
            FROM Mobile_Device_Token__c
            WHERE Active__c = true
            OR Device_Id__c = :input.deviceId
        ];

        List<Mobile_Device_Token__c> tokensToDeactivate =
            new List<Mobile_Device_Token__c>();

        for (Mobile_Device_Token__c tokenRec : candidateTokens) {
            Boolean sameDevice =
                !String.isBlank(input.deviceId) &&
                tokenRec.Device_Id__c == input.deviceId;

            Boolean sameFcm =
                !String.isBlank(input.fcmToken) &&
                !String.isBlank(tokenRec.FCM_Token__c) &&
                tokenRec.FCM_Token__c == input.fcmToken;

            if (
                tokenRec.Active__c == true &&
                (sameDevice || sameFcm)
            ) {
                tokenRec.Active__c = false;
                tokensToDeactivate.add(tokenRec);
            }
        }

        if (!tokensToDeactivate.isEmpty()) {
            update tokensToDeactivate;
        }

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(
            'Device token deactivated successfully. Count: ' +
            String.valueOf(tokensToDeactivate.size())
        );
    }
}
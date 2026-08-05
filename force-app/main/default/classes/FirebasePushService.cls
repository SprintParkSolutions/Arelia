public with sharing class FirebasePushService {

    private static final String PROJECT_ID = 'areliaspace-e5f22';

    public static void sendPushToToken(
        String fcmToken,
        String title,
        String messageBody,
        Map<String, String> dataPayload
    ) {
        if (String.isBlank(fcmToken)) {
            throw new FirebasePushException('FCM token is empty.');
        }

        String accessToken = FirebaseAuthService.getAccessToken();

        String endpoint =
            'https://fcm.googleapis.com/v1/projects/' +
            PROJECT_ID +
            '/messages:send';

        Map<String, Object> notificationMap = new Map<String, Object>{
            'title' => title,
            'body' => messageBody
        };

        Map<String, Object> androidNotification = new Map<String, Object>{
            'channel_id' => 'high_importance_channel',
            'sound' => 'default'
        };

        Map<String, Object> androidMap = new Map<String, Object>{
            'priority' => 'HIGH',
            'notification' => androidNotification
        };

        Map<String, Object> messageMap = new Map<String, Object>{
            'token' => fcmToken,
            'notification' => notificationMap,
            'android' => androidMap
        };

        if (dataPayload != null && !dataPayload.isEmpty()) {
            messageMap.put('data', dataPayload);
        }

        Map<String, Object> requestBody = new Map<String, Object>{
            'message' => messageMap
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(requestBody));
        req.setTimeout(120000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('FCM Send Status: ' + res.getStatusCode());
        System.debug('FCM Send Body: ' + res.getBody());

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new FirebasePushException('FCM send failed: ' + res.getBody());
        }
    }

    public class FirebasePushException extends Exception {}
}
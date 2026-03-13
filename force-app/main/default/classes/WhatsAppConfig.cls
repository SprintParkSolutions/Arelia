public without sharing class WhatsAppConfig {
    public static final String API_VERSION = 'v23.0';

    public static String phoneNumberId() { return System.Label.WA_Phone_Number_ID; }
    public static String accessToken()   { return System.Label.WA_Access_Token; }
    public static String verifyToken()   { return System.Label.WA_Verify_Token; }

    public static String messagesEndpoint() {
        return 'callout:Graph_Facebook/' + API_VERSION + '/' + phoneNumberId() + '/messages';
    }

    // Media meta endpoint used by WhatsAppMediaService
    public static String mediaMetaEndpoint(String mediaId) {
        return 'callout:Graph_Facebook/' + API_VERSION + '/' + mediaId + '?fields=url,mime_type,sha256,file_size,filename';
    }
}
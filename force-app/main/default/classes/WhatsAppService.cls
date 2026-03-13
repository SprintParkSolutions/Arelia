public without sharing class WhatsAppService {

    public class SendResult {
        @AuraEnabled public String  toNumber;
        @AuraEnabled public Integer statusCode;
        @AuraEnabled public String  messageId;
        @AuraEnabled public String  error;
        @AuraEnabled public String  rawResponse;
    }

    @AuraEnabled
    public static SendResult sendText(String toE164, String body) {
        if (String.isBlank(toE164) || String.isBlank(body)) {
            SendResult sr = new SendResult(); sr.error = 'toE164 and body are required'; return sr;
        }
        Map<String,Object> payload = new Map<String,Object>{
            'messaging_product' => 'whatsapp',
            'to'   => toE164,
            'type' => 'text',
            'text' => new Map<String,Object>{ 'body' => body }
        };
        SendResult res = doSend(payload, toE164);

        if (res != null && String.isBlank(res.error)) {
            WhatsAppChatStore.append(toE164, 'OUT', body, res.messageId, null, null, null, null);
        }
        return res;
    }

    @AuraEnabled
    public static SendResult sendTemplate(String toE164, String templateName, String langCode, List<String> bodyParams) {
        if (String.isBlank(toE164) || String.isBlank(templateName) || String.isBlank(langCode)) {
            SendResult sr = new SendResult(); sr.error = 'toE164, templateName, langCode are required'; return sr;
        }
        List<Object> components = new List<Object>();
        if (bodyParams != null && !bodyParams.isEmpty()) {
            List<Object> params = new List<Object>();
            for (String p : bodyParams) params.add(new Map<String,Object>{ 'type' => 'text', 'text' => p });
            components.add(new Map<String,Object>{ 'type' => 'body', 'parameters' => params });
        }
        Map<String,Object> payload = new Map<String,Object>{
            'messaging_product' => 'whatsapp',
            'to'        => toE164,
            'type'      => 'template',
            'template'  => new Map<String,Object>{
                'name'     => templateName,
                'language' => new Map<String,Object>{ 'code' => langCode },
                'components' => components
            }
        };
        SendResult res = doSend(payload, toE164);

        if (res != null && String.isBlank(res.error)) {
            WhatsAppChatStore.append(toE164, 'OUT', '[TEMPLATE] ' + templateName, res.messageId, null, null, null, null);
        }
        return res;
    }

    // Send a Salesforce File (auto public link when available)
    @AuraEnabled
    public static SendResult sendMediaFromDocument(Id contentDocumentId, String toE164, String caption) {
        if (contentDocumentId == null || String.isBlank(toE164)) {
            SendResult sr = new SendResult(); sr.error = 'contentDocumentId and toE164 are required'; return sr;
        }

        ContentVersion cv = [
            SELECT Id, Title, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            ORDER BY VersionNumber DESC
            LIMIT 1
        ];
        String ext = (cv.FileExtension == null) ? '' : cv.FileExtension.toLowerCase();
        String filename = (cv.Title == null ? 'file' : cv.Title) + (String.isBlank(ext) ? '' : '.' + ext);

        String publicUrl = WhatsAppMediaService.ensurePublicLink(contentDocumentId);
        if (String.isBlank(publicUrl)) {
            SendResult sr = new SendResult(); sr.error = 'Could not generate public link (enable Content Deliveries & Public Links)'; return sr;
        }

        String type = inferTypeFromExtension(ext); // image | video | audio | document
        Map<String,Object> media = new Map<String,Object>{ 'link' => publicUrl };
        if (!String.isBlank(caption)) media.put('caption', caption);
        if (type == 'document' && !String.isBlank(filename)) media.put('filename', filename);

        Map<String,Object> payload = new Map<String,Object>{
            'messaging_product' => 'whatsapp',
            'to'                => toE164,
            'type'              => type
        };
        payload.put(type, media);

        SendResult res = doSend(payload, toE164);
        if (res != null && String.isBlank(res.error)) {
            WhatsAppChatStore.append(
                toE164, 'OUT',
                String.isBlank(caption) ? '[' + type + ']' : caption,
                res.messageId, 'sent',
                (type == 'document' ? 'application' : type),
                contentDocumentId, publicUrl
            );
        }
        return res;
    }

    private static String inferTypeFromExtension(String ext) {
        if (String.isBlank(ext)) return 'document';
        String e = ext.toLowerCase();
        if (e == 'jpg' || e == 'jpeg' || e == 'png' || e == 'gif' || e == 'webp') return 'image';
        if (e == 'mp4' || e == '3gp') return 'video';
        if (e == 'mp3' || e == 'm4a' || e == 'ogg') return 'audio';
        return 'document';
    }

    private static SendResult doSend(Object payload, String toNumber) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(WhatsAppConfig.messagesEndpoint());
        req.setMethod('POST');
        req.setTimeout(120000);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + WhatsAppConfig.accessToken());
        req.setBody(JSON.serialize(payload));

        Http http = new Http();
        SendResult out = new SendResult();
        out.toNumber = toNumber;

        try {
            HTTPResponse res = http.send(req);
            out.statusCode = res.getStatusCode();
            out.rawResponse = res.getBody();

            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
                if (parsed != null && parsed.containsKey('messages')) {
                    List<Object> msgs = (List<Object>) parsed.get('messages');
                    if (msgs != null && !msgs.isEmpty()) {
                        Map<String,Object> m = (Map<String,Object>) msgs[0];
                        Object idVal = m.get('id');
                        out.messageId = (idVal == null) ? null : String.valueOf(idVal);
                    }
                }
            } else {
                Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
                if (parsed != null && parsed.containsKey('error')) out.error = JSON.serialize(parsed.get('error'));
                else out.error = res.getStatus() + ' ' + res.getBody();
            }
        } catch (Exception e) {
            out.error = e.getMessage();
        }
        return out;
    }
}